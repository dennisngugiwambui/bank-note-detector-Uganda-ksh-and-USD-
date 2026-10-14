"""Train the multi-currency denomination classifier (MobileNetV2 transfer learning).

Changes from the reference repos (see docs/REPO_ANALYSIS.md):
  * A 'background' class, so the model can say "no note". The Kenyan app and
    Noteify have no such class, and the Seeing AI notebook's Dense(14) dropped
    the background class its blog post describes.
  * Normalization inside the model (inputs are raw 0..255 RGB).
  * Two phases: train the head with the backbone frozen, then fine-tune the top
    of the backbone with BatchNorm kept frozen.
  * Label smoothing and sqrt-inverse-frequency class weights.
  * Temperature scaling on the val set, so a confidence of 0.9 really means
    about 90%. The Android speak threshold depends on this.

Usage:
  python train_classifier.py --data data/unified --out runs/v1
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

import keras
import numpy as np
import tensorflow as tf

from config import BACKGROUND, IMG_SIZE
from data import list_split, make_dataset


def build_model(num_classes: int, img: int, alpha: float, dropout: float):
    inputs = keras.Input((img, img, 3), name="image")  # raw RGB 0..255
    x = keras.layers.Rescaling(1 / 127.5, offset=-1.0, name="normalize")(inputs)
    base = keras.applications.MobileNetV2(input_shape=(img, img, 3), alpha=alpha,
                                          include_top=False, weights="imagenet")
    base.trainable = False
    x = base(x, training=False)  # BN layers stay in inference mode, even while fine-tuning
    x = keras.layers.GlobalAveragePooling2D(name="embedding")(x)  # also exported, for notes taught on the phone
    x = keras.layers.Dropout(dropout)(x)
    logits = keras.layers.Dense(num_classes, name="logits")(x)
    return keras.Model(inputs, logits, name="banknote_classifier"), base


def class_weights(ys: list[int], n: int) -> dict[int, float]:
    counts = Counter(ys)
    raw = {i: 1.0 / np.sqrt(max(counts.get(i, 1), 1)) for i in range(n)}
    mean = np.mean(list(raw.values()))
    return {i: float(w / mean) for i, w in raw.items()}


def fit_temperature(logits: np.ndarray, y: np.ndarray) -> float:
    """Grid-search the temperature that minimizes NLL on held-out data."""
    best_t, best_nll = 1.0, np.inf
    for t in np.arange(0.5, 5.01, 0.05):
        z = logits / t
        z = z - z.max(axis=1, keepdims=True)
        logp = z - np.log(np.exp(z).sum(axis=1, keepdims=True))
        nll = -logp[np.arange(len(y)), y].mean()
        if nll < best_nll:
            best_t, best_nll = float(t), nll
    return best_t


def predict_logits(model, ds) -> tuple[np.ndarray, np.ndarray]:
    xs, ys = [], []
    for x, y in ds:
        xs.append(model(x, training=False).numpy())
        ys.append(np.argmax(y.numpy(), axis=1))
    return np.concatenate(xs), np.concatenate(ys)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="data/unified")
    ap.add_argument("--out", default="runs/v1")
    ap.add_argument("--img", type=int, default=IMG_SIZE)
    ap.add_argument("--alpha", type=float, default=1.0, help="MobileNetV2 width: 0.35/0.5/0.75/1.0")
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--epochs-head", type=int, default=8)
    ap.add_argument("--epochs-ft", type=int, default=30)
    ap.add_argument("--ft-layers", type=int, default=50, help="backbone layers unfrozen in phase 2")
    ap.add_argument("--lr-head", type=float, default=1e-3)
    ap.add_argument("--lr-ft", type=float, default=2e-5)
    ap.add_argument("--dropout", type=float, default=0.3)
    ap.add_argument("--label-smoothing", type=float, default=0.1)
    args = ap.parse_args()

    root, out = Path(args.data), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    tr_p, tr_y, labels = list_split(root, "train")
    va_p, va_y, _ = list_split(root, "val", labels)
    te_p, te_y, _ = list_split(root, "test", labels)
    n = len(labels)
    print(f"{n} classes, train={len(tr_p)} val={len(va_p)} test={len(te_p)}")
    if BACKGROUND not in labels:
        print("WARNING: no background class, so the app cannot reject frames without a note.")

    train_ds = make_dataset(tr_p, tr_y, n, args.batch, training=True, size=args.img)
    val_ds = make_dataset(va_p, va_y, n, args.batch, training=False, size=args.img)
    test_ds = make_dataset(te_p, te_y, n, args.batch, training=False, size=args.img)

    model, base = build_model(n, args.img, args.alpha, args.dropout)
    loss = keras.losses.CategoricalCrossentropy(from_logits=True, label_smoothing=args.label_smoothing)
    weights = class_weights(tr_y, n)
    ckpt = str(out / "best.keras")

    def callbacks(phase):
        return [
            keras.callbacks.ModelCheckpoint(ckpt, monitor="val_accuracy", save_best_only=True),
            keras.callbacks.EarlyStopping(monitor="val_accuracy", patience=6, restore_best_weights=True),
            keras.callbacks.CSVLogger(str(out / f"log_{phase}.csv")),
        ]

    # Phase 1: head only
    model.compile(keras.optimizers.Adam(args.lr_head), loss, metrics=["accuracy"])
    model.fit(train_ds, validation_data=val_ds, epochs=args.epochs_head,
              class_weight=weights, callbacks=callbacks("head"), verbose=2)

    # Phase 2: fine-tune the top of the backbone. BatchNorm stays frozen.
    base.trainable = True
    for layer in base.layers[:-args.ft_layers]:
        layer.trainable = False
    for layer in base.layers:
        if isinstance(layer, keras.layers.BatchNormalization):
            layer.trainable = False
    steps = max(1, len(tr_p) // args.batch) * args.epochs_ft
    lr = keras.optimizers.schedules.CosineDecay(args.lr_ft, decay_steps=steps, alpha=0.05)
    model.compile(keras.optimizers.Adam(lr), loss, metrics=["accuracy"])
    model.fit(train_ds, validation_data=val_ds, epochs=args.epochs_ft,
              class_weight=weights, callbacks=callbacks("finetune"), verbose=2)

    # Calibrate on val, report on test
    val_logits, val_true = predict_logits(model, val_ds)
    temperature = fit_temperature(val_logits, val_true)
    test_logits, test_true = predict_logits(model, test_ds)
    test_acc = float((test_logits.argmax(1) == test_true).mean())
    print(f"temperature={temperature:.2f}  test accuracy={test_acc:.4f}")

    model.save(out / "model.keras")
    (out / "labels.txt").write_text("\n".join(labels) + "\n", encoding="utf-8")
    (out / "meta.json").write_text(json.dumps({
        "labels": labels,
        "img_size": args.img,
        "alpha": args.alpha,
        "temperature": temperature,
        "test_accuracy": test_acc,
        "input": "RGB uint8/float 0..255, letterboxed (resize_with_pad, black)",
    }, indent=2), encoding="utf-8")
    print(f"saved to {out}")


if __name__ == "__main__":
    tf.get_logger().setLevel("ERROR")
    main()
