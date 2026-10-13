"""Evaluate the exported .tflite model (the exact file the phone runs) on the test split.

Reports:
  * overall and per-class accuracy, plus a confusion matrix (CSV)
  * accuracy per source dataset, to show whether one dataset carries the score
  * a confidence-threshold sweep. For a blind user, a wrong denomination is far
    worse than silence, so choose the app's confidence threshold where precision
    is at least 99% and background frames are rarely announced as notes.

Usage:
  python evaluate_tflite.py --model runs/v1/model_int8.tflite --data data/unified
"""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path

import numpy as np
import tensorflow as tf

from config import BACKGROUND
from data import list_split, load_letterboxed


class TfliteRunner:
    def __init__(self, path: str):
        self.interp = tf.lite.Interpreter(model_path=path, num_threads=4)
        self.interp.allocate_tensors()
        self.inp = self.interp.get_input_details()[0]
        self.out = self.interp.get_output_details()[0]
        self.size = int(self.inp["shape"][1])

    def __call__(self, img: np.ndarray) -> np.ndarray:
        x = img[None]
        if self.inp["dtype"] == np.uint8:
            x = np.clip(np.round(x), 0, 255).astype(np.uint8)
        else:
            x = x.astype(np.float32)
        self.interp.set_tensor(self.inp["index"], x)
        self.interp.invoke()
        y = self.interp.get_tensor(self.out["index"])[0].astype(np.float32)
        scale, zero = self.out["quantization"]
        if scale:
            y = (y - zero) * scale
        return y


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--data", required=True)
    ap.add_argument("--labels", default=None, help="defaults to labels.txt next to the model")
    ap.add_argument("--split", default="test")
    args = ap.parse_args()

    labels_file = Path(args.labels) if args.labels else Path(args.model).with_name("labels.txt")
    labels = labels_file.read_text(encoding="utf-8").split()
    root = Path(args.data)
    paths, ys, _ = list_split(root, args.split, labels)
    runner = TfliteRunner(args.model)

    source_of = {}
    manifest = root / "manifest.csv"
    if manifest.exists():
        with open(manifest, newline="") as f:
            for row in csv.DictReader(f):
                source_of[str((root / row["path"]).resolve())] = row["source"]

    probs = np.stack([runner(load_letterboxed(tf.constant(p), runner.size).numpy()) for p in paths])
    y = np.array(ys)
    pred, conf = probs.argmax(1), probs.max(1)
    n = len(labels)

    print(f"\n{args.model}: {len(y)} {args.split} images, accuracy {np.mean(pred == y):.4f}\n")
    cm = np.zeros((n, n), dtype=int)
    for t, p in zip(y, pred):
        cm[t, p] += 1
    print(f"{'class':<12}{'n':>6}{'recall':>8}{'precision':>11}")
    for i, label in enumerate(labels):
        rec = cm[i, i] / max(cm[i].sum(), 1)
        prec = cm[i, i] / max(cm[:, i].sum(), 1)
        print(f"{label:<12}{cm[i].sum():>6}{rec:>8.3f}{prec:>11.3f}")
    out_csv = Path(args.model).with_name(f"confusion_{args.split}.csv")
    with open(out_csv, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["true\\pred"] + labels)
        for i, label in enumerate(labels):
            w.writerow([label] + cm[i].tolist())
    print(f"confusion matrix -> {out_csv}")

    if source_of:
        per = defaultdict(list)
        for p, t, q in zip(paths, y, pred):
            per[source_of.get(str(Path(p).resolve()), "?")].append(t == q)
        print("\nper-source accuracy:")
        for s, hits in sorted(per.items()):
            print(f"  {s:<20}{np.mean(hits):.3f}  (n={len(hits)})")

    bg = labels.index(BACKGROUND) if BACKGROUND in labels else -1
    is_note = y != bg
    print("\nthreshold sweep (note images = test images whose true class is not background)")
    print(f"{'thresh':>7}{'notes answered':>16}{'precision':>11}{'bg false alarms':>17}")
    for t in [0.5, 0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 0.97]:
        speaks = (conf >= t) & (pred != bg)
        answered = speaks[is_note].mean() if is_note.any() else 0
        correct = (pred == y)[speaks]
        precision = correct.mean() if correct.size else float("nan")
        false_alarm = speaks[~is_note].mean() if (~is_note).any() else float("nan")
        print(f"{t:>7.2f}{answered:>16.3f}{precision:>11.4f}{false_alarm:>17.4f}")
    print("\nPick the lowest threshold with precision >= 0.99 and set it in app settings (Detection sensitivity) or PredictionSmoother.")


if __name__ == "__main__":
    main()
