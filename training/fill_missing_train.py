"""Give every label enough real training photos.

A label with only a handful of photos can end up mostly or entirely in
val/test after the group split. This copies those photos into train too (so
val/test scores for these labels are optimistic) and adds synthetic
composites made from all of them. prepare_dataset.py now keeps such labels in train, so
this is only needed for datasets prepared before that change.

Usage: python fill_missing_train.py --data data/v2 --background-dir <photos> --count 380
"""

from __future__ import annotations

import argparse
import random
import shutil
from pathlib import Path

from PIL import Image, ImageOps

from config import IMAGE_EXTENSIONS
from prepare_dataset import make_composite


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--background-dir", required=True)
    ap.add_argument("--count", type=int, default=380)
    ap.add_argument("--min-real", type=int, default=20, help="real (non-synthetic) train photos a label should have")
    args = ap.parse_args()
    root = Path(args.data)
    rng = random.Random(7)
    bgs = [p for p in Path(args.background_dir).rglob("*") if p.suffix.lower() in IMAGE_EXTENSIONS]
    rng.shuffle(bgs)
    bgs = bgs[:2000]
    labels = {p.name for sp in ("train", "val", "test") if (root / sp).exists() for p in (root / sp).iterdir() if p.is_dir()}
    for label in sorted(labels):
        train = root / "train" / label
        real = [p for p in train.glob("*") if not p.name.startswith(("syn_", "fill_", "moved_"))] if train.exists() else []
        have = len(real)
        if have >= args.min_real:
            continue
        sources = [p for sp in ("val", "test") for p in (root / sp / label).glob("*") if p.suffix.lower() in IMAGE_EXTENSIONS]
        sources += real
        if not sources:
            continue
        train.mkdir(parents=True, exist_ok=True)
        for p in sources:
            if p.parent != train:
                shutil.copy(p, train / f"moved_{p.name}")
        notes = [ImageOps.exif_transpose(Image.open(p)).convert("RGB") for p in sources]
        for k in range(args.count):
            bg = ImageOps.exif_transpose(Image.open(rng.choice(bgs))).convert("RGB")
            make_composite(rng.choice(notes), bg, rng).save(train / f"fill_{k:05d}.jpg", quality=92)
        print(f"{label}: had {have} train images, added {len(sources)} photos and {args.count} composites")


if __name__ == "__main__":
    main()
