"""Shared constants for the banknote training pipeline.

The unified label format is ``<ISO currency>_<denomination>`` (e.g. ``KES_100``),
plus one ``background`` class for "no banknote in view". The Android app parses
the same format, so keep the two in sync.
"""

from __future__ import annotations

BACKGROUND = "background"

# Notes currently in circulation. Used only to warn about unexpected labels
# (typos, withdrawn notes, coins). It does not filter anything.
KNOWN_DENOMINATIONS: dict[str, list[int]] = {
    # INR 2000 was withdrawn from circulation in 2023 (still legal tender).
    "INR": [10, 20, 50, 100, 200, 500, 2000],
    "KES": [50, 100, 200, 500, 1000],
    "EGP": [1, 5, 10, 20, 50, 100, 200],
    "UGX": [1000, 2000, 5000, 10000, 20000, 50000],
    "USD": [1, 2, 5, 10, 20, 50, 100],
}

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

# Classifier input. Pixels go in as raw RGB 0..255. The model normalizes
# them internally, so Android never has to know the mean and std.
IMG_SIZE = 224

# Longest side of images stored by prepare_dataset.py. That is big enough for
# 224 crops after augmentation, and small enough to keep the dataset light.
STORE_MAX_SIDE = 512


def is_valid_label(label: str) -> bool:
    if label == BACKGROUND:
        return True
    parts = label.split("_")
    if len(parts) != 2 or not parts[1].isdigit():
        return False
    return parts[0] in KNOWN_DENOMINATIONS and int(parts[1]) in KNOWN_DENOMINATIONS[parts[0]]
