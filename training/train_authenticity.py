"""Train one step of the per-currency genuine-vs-counterfeit check.

The app runs up to three steps, the method from bkataru/fake-currency-identification
(re-implemented here; that repo is GPL-3.0, so none of its code or models are used):

  --step print      ordinary light, fine print texture   -> model.tflite,     threshold.txt
  --step backlight  note held against a window or lamp   -> backlight.tflite, backlight_threshold.txt
                    (watermark, security thread, see-through register)
  --step uv         under a 365 nm UV lamp (fluorescent  -> uv.tflite,        uv_threshold.txt
                    fibres; genuine paper stays dull)

Train each step on photos taken under that step's lighting.

Why patches. Counterfeit cues are fine print texture: inkjet dots, toner halos,
blurred microtext, flat colour where there should be intaglio lines. Shrinking a
whole note to 224 px destroys them. Instead, the photo is resized so its short
side is SHORT_SIDE px (about 2x the classifier's resolution), and the model
looks at random 224 px patches. At inference, a 3x3 grid of patches is scored
and the scores are averaged. AuthenticityChecker in the Flutter app does the
same on a full-resolution still. Backlight and UV cues are large (watermark,
thread, glowing fibres), so those steps use the whole note letterboxed to
224 px instead, like the currency classifier.

Honest limits (see docs/COUNTERFEIT_DETECTION.md). This only learns the kinds
of fakes in your training data. Always run --holdout-counterfeit with fakes from
a different source (printer, paper, maker) and report THAT number, not the
in-distribution one.

Usage:
  python train_authenticity.py --currency UGX \
      --genuine raw/ugx_mendeley/genuine --counterfeit raw/ugx_mendeley/counterfeit \
      --holdout-counterfeit raw/ugx_fakes_other_printer \
      --out runs/auth_ugx --android-assets ../app/assets/authenticity/UGX
  python train_authenticity.py --currency UGX --step backlight \
      --genuine raw/ugx_backlight/genuine --counterfeit raw/ugx_backlight/counterfeit \
      --out runs/auth_ugx_backlight --android-assets ../app/assets/authenticity/UGX
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
from pathlib import Path

import keras
import numpy as np
import tensorflow as tf
from PIL import Image, ImageOps

from config import IMAGE_EXTENSIONS
from export_tflite import convert, probability_model
from prepare_dataset import Sample, dhash, group_near_duplicates, split_by_group
from train_classifier import build_model

LABELS = ["genuine", "counterfeit"]
SHORT_SIDE = 448  # keep in sync with AuthenticityChecker.shortSide
PATCH = 224
GRID = 3


def collect(dirs: list[str], label: str) -> list[Sample]:
    out = []
    for d in dirs or []:
        for p in sorted(Path(d).rglob("*")):
            if p.suffix.lower() in IMAGE_EXTENSIONS:
                out.append(Sample(Path(d).name, label, p))
    return out


def load_resized(path: str) -> np.ndarray:
    img = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    f = SHORT_SIDE / min(img.size)
    img = img.resize((max(PATCH, round(img.width * f)), max(PATCH, round(img.height * f))), Image.BILINEAR)
    return np.asarray(img, dtype=np.uint8)


def load_letterboxed_np(path: str) -> np.ndarray:
    """Whole note scaled into PATCH x PATCH, centred on black (AuthenticityChecker._whole)."""
    img = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    f = PATCH / max(img.size)
    img = img.resize((max(1, round(img.width * f)), max(1, round(img.height * f))), Image.BILINEAR)
    canvas = Image.new("RGB", (PATCH, PATCH))
    canvas.paste(img, ((PATCH - img.width) // 2, (PATCH - img.height) // 2))
    return np.asarray(canvas, dtype=np.uint8)


def grid_patches(arr: np.ndarray) -> np.ndarray:
    h, w = arr.shape[:2]
    ys = np.linspace(0, h - PATCH, GRID).astype(int)
    xs = np.linspace(0, w - PATCH, GRID).astype(int)
    return np.stack([arr[y:y + PATCH, x:x + PATCH] for y in ys for x in xs]).astype(np.float32)


def model_inputs(step: str, path: str) -> np.ndarray:
    """What the app feeds the model for one photo: 9 patches, or 1 whole image."""
    if step == "print":
        return grid_patches(load_resized(path))
    return load_letterboxed_np(path)[None].astype(np.float32)


def patch_dataset(paths: list[str], ys: list[int], batch: int, patches_per_image: int, step: str = "print"):
    whole = step != "print"
    loader = load_letterboxed_np if whole else load_resized
    images = [loader(p) for p in paths]  # dataset is small enough to hold in RAM

    def gen():
        order = list(range(len(images)))
        random.shuffle(order)
        for i in order:
            arr = images[i]
            h, w = arr.shape[:2]
            for _ in range(patches_per_image):
                if whole:
                    # Notes are held either way up; no 90-degree turns, the letterbox is landscape.
                    patch = np.rot90(arr, 2 * random.randint(0, 1))
                else:
                    y, x = random.randint(0, h - PATCH), random.randint(0, w - PATCH)
                    patch = np.rot90(arr[y:y + PATCH, x:x + PATCH], random.randint(0, 3))
                yield patch.astype(np.float32), ys[i]

    ds = tf.data.Dataset.from_generator(gen, output_signature=(
        tf.TensorSpec([PATCH, PATCH, 3], tf.float32), tf.TensorSpec([], tf.int32)))
    # Mild photometric jitter only. Blur and JPEG augmentation would teach the
    # model to ignore the print-quality cues it is supposed to find.
    ds = ds.map(lambda x, y: (tf.clip_by_value(tf.image.random_brightness(x, 25.0), 0, 255), y))
    ds = ds.map(lambda x, y: (tf.clip_by_value(tf.image.random_contrast(x, 0.85, 1.15), 0, 255), y))
    return ds.shuffle(2048).batch(batch).map(lambda x, y: (x, tf.one_hot(y, 2))).prefetch(tf.data.AUTOTUNE)


def image_scores(model, paths: list[str], step: str = "print") -> np.ndarray:
    """P(counterfeit) per image: mean of softmax over its inputs (3x3 patch grid, or whole note)."""
    scores = []
    for p in paths:
        probs = tf.nn.softmax(model(model_inputs(step, p), training=False)).numpy()
        scores.append(probs[:, 1].mean())
    return np.array(scores)


def auc(scores: np.ndarray, y: np.ndarray) -> float:
    pos, neg = scores[y == 1], scores[y == 0]
    if not len(pos) or not len(neg):
        return float("nan")
    return float(np.mean([(s > neg).mean() + 0.5 * (s == neg).mean() for s in pos]))


def report(name: str, scores: np.ndarray, y: np.ndarray, threshold: float) -> dict:
    caught = float((scores[y == 1] >= threshold).mean()) if (y == 1).any() else float("nan")
    false_alarm = float((scores[y == 0] >= threshold).mean()) if (y == 0).any() else float("nan")
    a = auc(scores, y)
    print(f"{name:<22} AUC={a:.3f}  fakes caught={caught:.3f}  genuine flagged={false_alarm:.3f}")
    return {"auc": a, "fakes_caught": caught, "genuine_flagged": false_alarm}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--currency", required=True, help="ISO code, e.g. UGX")
    ap.add_argument("--step", choices=["print", "backlight", "uv"], default="print",
                    help="which lighting the photos were taken under (see module docstring)")
    ap.add_argument("--genuine", nargs="+", required=True)
    ap.add_argument("--counterfeit", nargs="+", required=True)
    ap.add_argument("--holdout-counterfeit", nargs="*", default=[], help="fakes from an unseen source, test only")
    ap.add_argument("--out", required=True)
    ap.add_argument("--alpha", type=float, default=0.5)
    ap.add_argument("--epochs", type=int, default=25)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--patches-per-image", type=int, default=8)
    ap.add_argument("--max-genuine-flag-rate", type=float, default=0.02,
                    help="threshold chosen so at most this share of genuine val notes is flagged")
    ap.add_argument("--android-assets", default=None)
    args = ap.parse_args()
    random.seed(0)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    samples = collect(args.genuine, "genuine") + collect(args.counterfeit, "counterfeit")
    for s in samples:
        s.hash = dhash(Image.open(s.path).convert("RGB"))
    group_near_duplicates(samples)
    split_by_group(samples, val=0.15, test=0.15, seed=0)

    def subset(split):
        items = [s for s in samples if s.split == split]
        return [str(s.path) for s in items], [LABELS.index(s.label) for s in items]

    tr_p, tr_y = subset("train")
    va_p, va_y = subset("val")
    te_p, te_y = subset("test")
    print(f"train={len(tr_p)} val={len(va_p)} test={len(te_p)}  (counterfeit share {np.mean(tr_y):.2f})")

    model, base = build_model(2, PATCH, args.alpha, dropout=0.3)
    base.trainable = True
    for layer in base.layers[:-40]:
        layer.trainable = False
    for layer in base.layers:
        if isinstance(layer, keras.layers.BatchNormalization):
            layer.trainable = False
    model.compile(keras.optimizers.Adam(1e-4),
                  keras.losses.CategoricalCrossentropy(from_logits=True), metrics=["accuracy"])
    pos = max(np.mean(tr_y), 1e-3)
    model.fit(patch_dataset(tr_p, tr_y, args.batch, args.patches_per_image, args.step),
              validation_data=patch_dataset(va_p, va_y, args.batch, 4 if args.step == "print" else 1, args.step),
              epochs=args.epochs, class_weight={0: 0.5 / (1 - pos), 1: 0.5 / pos},
              callbacks=[keras.callbacks.EarlyStopping(monitor="val_loss", patience=5,
                                                       restore_best_weights=True)], verbose=2)

    # Pick the threshold on val so genuine notes are rarely called fake.
    va_scores = image_scores(model, va_p, args.step)
    genuine_scores = np.sort(va_scores[np.array(va_y) == 0])
    k = int(np.ceil((1 - args.max_genuine_flag_rate) * len(genuine_scores))) - 1
    # Just above the k-th genuine score, so that score itself is not flagged (the app uses >=).
    threshold = (float(np.nextafter(genuine_scores[min(max(k, 0), len(genuine_scores) - 1)], 1.0))
                 if len(genuine_scores) else 0.5)
    print(f"\nthreshold P(counterfeit) >= {threshold:.3f}")
    results = {"val": report("val", va_scores, np.array(va_y), threshold),
               "test": report("test (same sources)", image_scores(model, te_p, args.step), np.array(te_y), threshold)}
    holdout = collect(args.holdout_counterfeit, "counterfeit")
    if holdout:
        hp = [str(s.path) for s in holdout]
        results["holdout"] = report("holdout fakes", image_scores(model, hp, args.step), np.ones(len(hp), int), threshold)
        print("^ This is the number to trust. In-distribution test scores overstate real-world performance.")

    model.save(out / "model.keras")
    (out / "labels.txt").write_text("\n".join(LABELS) + "\n", encoding="utf-8")
    meta = {"currency": args.currency, "step": args.step, "labels": LABELS, "img_size": PATCH, "short_side": SHORT_SIDE,
            "grid": GRID, "threshold": threshold, "results": results}
    (out / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

    def representative():
        for p in tr_p[:150]:
            for patch in model_inputs(args.step, p)[::3]:
                yield [patch[None]]

    blob = convert(probability_model(model), "int8", representative)
    (out / "model_int8.tflite").write_bytes(blob)
    print(f"model_int8.tflite {len(blob) / 1e6:.2f} MB")
    if args.android_assets:
        dst = Path(args.android_assets)
        dst.mkdir(parents=True, exist_ok=True)
        # File names AuthenticityChecker looks for: model|backlight|uv.tflite, [step_]threshold.txt
        name, prefix = ("model", "") if args.step == "print" else (args.step, f"{args.step}_")
        shutil.copy(out / "model_int8.tflite", dst / f"{name}.tflite")
        shutil.copy(out / "labels.txt", dst / "labels.txt")
        (dst / f"{prefix}threshold.txt").write_text(f"{threshold:.4f}\n", encoding="utf-8")
        print(f"copied to {dst}")


if __name__ == "__main__":
    main()
