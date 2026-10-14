"""Convert a trained Keras model to TFLite for the Android app.

The calibrated softmax, softmax(logits / T), is built into the graph, so
the app reads ready-to-use probabilities.

A second output, "features", is the pooled backbone embedding with the mean
training embedding subtracted and L2-normalised. The app compares it by cosine
similarity with notes the user taught on the phone ("Teach a note"), which
covers notes and series the training data lacks.

Variants:
  int8   full-integer, uint8 input. Smallest and fastest on CPU (XNNPACK). Default for the app.
  fp16   float16 weights, float32 input. Use this one with the GPU delegate.

Usage:
  python export_tflite.py --run runs/v1 --data data/unified --android-assets ../android/app/src/main/assets/currency

train_authenticity.py exports its own models through convert().
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
import tempfile
from pathlib import Path

import keras
import numpy as np
import tensorflow as tf

from data import list_split, load_letterboxed


def probability_model(model, temperature: float = 1.0, embedding_mean=None):
    """Wrap a logits model so it outputs softmax(logits / T), and with
    [embedding_mean] also the centred, normalised embedding."""
    x = keras.layers.Rescaling(1.0 / temperature, name="temperature")(model.output)
    probs = keras.layers.Softmax(name="probabilities")(x)
    if embedding_mean is None:
        return keras.Model(model.input, probs)
    emb = model.get_layer("embedding").output
    mean = keras.ops.convert_to_tensor(np.asarray(embedding_mean, "float32"))
    feats = keras.layers.Lambda(lambda e: keras.ops.normalize(e - mean, axis=-1), name="features")(emb)
    return keras.Model(model.input, [probs, feats])


def embedding_mean(model, paths, img: int, count: int = 600):
    emb_model = keras.Model(model.input, model.get_layer("embedding").output)
    xs = [load_letterboxed(tf.constant(p), img) for p in paths[:count]]
    out = [emb_model(tf.stack(xs[i:i + 32]), training=False).numpy() for i in range(0, len(xs), 32)]
    return np.concatenate(out).mean(axis=0)


def convert(prob_model, mode: str, representative) -> bytes:
    """representative: a zero-arg generator yielding [float32 array of shape [1, H, W, 3]].

    The model goes through a SavedModel export. Converting a Keras 3 model
    straight from a tf.function leaves its weights as resource variables, and
    int8 calibration then fails with "READ_VARIABLE ... variable != nullptr".
    """
    with tempfile.TemporaryDirectory() as tmp:
        prob_model.export(tmp, format="tf_saved_model", verbose=False)
        conv = tf.lite.TFLiteConverter.from_saved_model(tmp)
        if mode == "fp16":
            conv.optimizations = [tf.lite.Optimize.DEFAULT]
            conv.target_spec.supported_types = [tf.float16]
        elif mode == "int8":
            conv.optimizations = [tf.lite.Optimize.DEFAULT]
            conv.representative_dataset = representative
            conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
            conv.inference_input_type = tf.uint8   # camera bytes go straight in
            conv.inference_output_type = tf.float32
        return conv.convert()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True, help="folder with model.keras, labels.txt, meta.json")
    ap.add_argument("--data", required=True, help="dataset root, for int8 calibration images")
    ap.add_argument("--modes", nargs="+", default=["int8", "fp16"])
    ap.add_argument("--rep-count", type=int, default=400)
    ap.add_argument("--android-assets", default=None, help="copy the int8 model and labels here")
    ap.add_argument("--no-features", action="store_true", help="export probabilities only")
    args = ap.parse_args()

    run = Path(args.run)
    meta = json.loads((run / "meta.json").read_text(encoding="utf-8"))
    img, temperature = meta["img_size"], meta.get("temperature", 1.0)
    model = keras.models.load_model(run / "model.keras")
    paths, _, _ = list_split(Path(args.data), "train", meta["labels"])
    random.Random(0).shuffle(paths)
    rep = paths[: args.rep_count]
    mean = None if args.no_features else embedding_mean(model, paths, img)
    prob_model = probability_model(model, temperature, mean)

    def representative():
        for p in rep:
            yield [load_letterboxed(tf.constant(p), img)[None]]

    for mode in args.modes:
        blob = convert(prob_model, mode, representative)
        dst = run / f"model_{mode}.tflite"
        dst.write_bytes(blob)
        print(f"{dst}  {len(blob) / 1e6:.2f} MB")

    if args.android_assets:
        assets = Path(args.android_assets)
        assets.mkdir(parents=True, exist_ok=True)
        src = run / ("model_int8.tflite" if "int8" in args.modes else f"model_{args.modes[0]}.tflite")
        shutil.copy(src, assets / "model.tflite")
        shutil.copy(run / "labels.txt", assets / "labels.txt")
        print(f"copied {src.name} and labels.txt to {assets}")


if __name__ == "__main__":
    main()
