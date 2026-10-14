"""Shared constants for the banknote training pipeline.

The unified label format is ``<ISO currency>_<denomination>`` (e.g. ``KES_100``),
``<ISO>_<value>_coin`` for coins (``KES_20_coin``), ``<ISO>_<cents>c_coin`` for
coins worth less than one unit (``USD_25c_coin``), plus one ``background`` class for "no banknote in view". The Android app parses
the same format, so keep the two in sync.
"""

from __future__ import annotations

BACKGROUND = "background"

# Notes currently in circulation. Used only to warn about unexpected labels
# (typos, withdrawn notes). It does not filter anything.
KNOWN_DENOMINATIONS: dict[str, list[int]] = {
    # INR 2000 was withdrawn from circulation in 2023 (still legal tender).
    "INR": [10, 20, 50, 100, 200, 500, 2000],
    "KES": [50, 100, 200, 500, 1000],
    "EGP": [1, 5, 10, 20, 50, 100, 200],
    "UGX": [1000, 2000, 5000, 10000, 20000, 50000],
    "USD": [1, 2, 5, 10, 20, 50, 100],
}

# Coins in circulation, as written in labels ("25c" = 25 cents). Must match
# currencyCatalog in app/lib/core/currency.dart.
KNOWN_COINS: dict[str, list[str]] = {
    "KES": ["1", "5", "10", "20"],
    "UGX": ["100", "200", "500", "1000"],
    "INR": ["1", "2", "5", "10", "20"],
    "EGP": ["25c", "50c", "1"],
    "USD": ["1c", "5c", "10c", "25c"],
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
    if len(parts) == 3 and parts[2] == "coin":
        return parts[1] in KNOWN_COINS.get(parts[0], [])
    if len(parts) != 2 or not parts[1].isdigit():
        return False
    return parts[0] in KNOWN_DENOMINATIONS and int(parts[1]) in KNOWN_DENOMINATIONS[parts[0]]
