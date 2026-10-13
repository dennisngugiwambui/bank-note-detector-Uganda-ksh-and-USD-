"""Merge banknote datasets from different sources into one classification dataset.

Each entry in sources.yaml names a dataset, its layout, and how its class names
map onto unified labels (``KES_100``, ``USD_20``, ``background``, ...).

Supported layouts:
  folders  root/<class>/.../*.jpg            (Kaggle and Teachable Machine style)
  yolo     Roboflow/YOLO export with data.yaml; every box is cropped into its own sample

The reference repos share two problems that this script fixes:
  * Near-duplicate leakage. Kaggle note sets hold many augmented copies of one
    photo, and a random per-image split puts copies in both train and test.
    Here, near-duplicates (dHash) are grouped and each group stays in one split.
  * Fake labels. Curency_Detection wrote a full-frame box for every
    classification image. Here, YOLO boxes are cropped instead.

Outputs: <out>/{train,val,test}/<label>/*.jpg, manifest.csv, conflicts.csv
"""

from __future__ import annotations

import argparse
import csv
import random
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

import yaml
from PIL import Image, ImageEnhance, ImageOps

from config import BACKGROUND, IMAGE_EXTENSIONS, STORE_MAX_SIDE, is_valid_label


@dataclass
class Sample:
    source: str
    label: str
    path: Path
    box: tuple[float, float, float, float] | None = None  # normalized cx, cy, w, h
    hash: int = 0
    group: int = -1
    split: str = ""


# ----------------------------------------------------------------------------
# Collection
# ----------------------------------------------------------------------------

def _images_under(root: Path):
    for p in sorted(root.rglob("*")):
        if p.suffix.lower() in IMAGE_EXTENSIONS and p.is_file():
            yield p


def collect_folders(src: dict) -> list[Sample]:
    root = Path(src["root"])
    mapping: dict[str, str] = {str(k): v for k, v in (src.get("mapping") or {}).items()}
    fixed_label = src.get("label")
    depth = int(src.get("class_depth", 0))  # 0 = first folder under root, -1 = immediate parent
    samples, unmapped = [], Counter()
    for p in _images_under(root):
        rel = p.relative_to(root).parts
        if fixed_label:
            label = fixed_label
        else:
            if len(rel) < 2:
                continue
            cls = rel[-2] if depth == -1 else rel[depth]
            label = mapping.get(cls)
            if label is None:
                unmapped[cls] += 1
                continue
        samples.append(Sample(src["name"], label, p))
    if unmapped:
        print(f"  [{src['name']}] skipped unmapped classes: {dict(unmapped)}")
    return samples


def collect_yolo(src: dict) -> list[Sample]:
    root = Path(src["root"])
    data_yaml = yaml.safe_load((root / "data.yaml").read_text(encoding="utf-8"))
    names = data_yaml["names"]
    if isinstance(names, dict):
        names = [names[i] for i in sorted(names)]
    mapping: dict[str, str] = {str(k): v for k, v in (src.get("mapping") or {}).items()}
    min_side = float(src.get("min_box_side", 0.05))
    samples, unmapped = [], Counter()
    for label_file in sorted(root.rglob("*.txt")):
        if "labels" not in label_file.parts:
            continue
        img_dir = Path(*["images" if part == "labels" else part for part in label_file.parent.parts])
        image = next((img_dir / (label_file.stem + ext) for ext in IMAGE_EXTENSIONS
                      if (img_dir / (label_file.stem + ext)).exists()), None)
        if image is None:
            continue
        for line in label_file.read_text().splitlines():
            parts = line.split()
            if len(parts) != 5:
                continue  # skip segmentation polygons and malformed lines
            cls_name = str(names[int(parts[0])])
            label = mapping.get(cls_name)
            if label is None:
                unmapped[cls_name] += 1
                continue
            cx, cy, w, h = map(float, parts[1:])
            if min(w, h) < min_side:
                continue
            samples.append(Sample(src["name"], label, image, (cx, cy, w, h)))
    if unmapped:
        print(f"  [{src['name']}] skipped unmapped classes: {dict(unmapped)}")
    return samples


# ----------------------------------------------------------------------------
# Image loading and hashing
# ----------------------------------------------------------------------------

def load_sample_image(s: Sample, pad: float = 0.08) -> Image.Image:
    img = ImageOps.exif_transpose(Image.open(s.path)).convert("RGB")
    if s.box:
        W, H = img.size
        cx, cy, w, h = s.box
        w, h = w * (1 + 2 * pad), h * (1 + 2 * pad)
        img = img.crop((max(0, (cx - w / 2) * W), max(0, (cy - h / 2) * H),
                        min(W, (cx + w / 2) * W), min(H, (cy + h / 2) * H)))
    img.thumbnail((STORE_MAX_SIDE, STORE_MAX_SIDE), Image.BILINEAR)
    return img


def dhash(img: Image.Image) -> int:
    g = img.convert("L").resize((9, 8), Image.BILINEAR)
    px = list(g.getdata())
    bits = 0
    for row in range(8):
        for col in range(8):
            bits = (bits << 1) | (px[row * 9 + col] > px[row * 9 + col + 1])
    return bits


def group_near_duplicates(samples: list[Sample], max_distance: int = 3) -> None:
    """Union-find over dHash. With 4 chunks of 16 bits, any two hashes within
    distance 3 share at least one identical chunk, so only same-bucket pairs
    need comparing."""
    parent = list(range(len(samples)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for chunk in range(4):
        buckets = defaultdict(list)
        for i, s in enumerate(samples):
            buckets[(s.hash >> (16 * chunk)) & 0xFFFF].append(i)
        for idx in buckets.values():
            for a in range(len(idx)):
                for b in range(a + 1, len(idx)):
                    i, j = idx[a], idx[b]
                    if bin(samples[i].hash ^ samples[j].hash).count("1") <= max_distance:
                        parent[find(i)] = find(j)
    for i, s in enumerate(samples):
        s.group = find(i)


# ----------------------------------------------------------------------------
# Splitting
# ----------------------------------------------------------------------------

def split_by_group(samples: list[Sample], val: float, test: float, seed: int) -> None:
    rng = random.Random(seed)
    by_label: dict[str, dict[int, list[Sample]]] = defaultdict(lambda: defaultdict(list))
    for s in samples:
        by_label[s.label][s.group].append(s)
    for label, groups in by_label.items():
        group_list = list(groups.values())
        rng.shuffle(group_list)
        total = sum(len(g) for g in group_list)
        taken = {"test": 0, "val": 0}
        for g in group_list:
            if taken["test"] < test * total:
                split = "test"
            elif taken["val"] < val * total:
                split = "val"
            else:
                split = "train"
            if split != "train":
                taken[split] += len(g)
            for s in g:
                s.split = split


# ----------------------------------------------------------------------------
# Synthetic composites: a note pasted onto a real background at a random
# scale, angle and position. This follows the Seeing AI lesson that live
# frames show the note small, off-centre and rotated, unlike tight dataset
# crops.
# ----------------------------------------------------------------------------

def make_composite(note: Image.Image, bg: Image.Image, rng: random.Random, size: int = 512) -> Image.Image:
    bg = ImageOps.fit(bg, (size, size), Image.BILINEAR)
    bg = ImageEnhance.Brightness(bg).enhance(rng.uniform(0.6, 1.3))
    note = note.copy()
    target = rng.uniform(0.45, 0.95) * size
    scale = target / max(note.size)
    note = note.resize((max(8, int(note.width * scale)), max(8, int(note.height * scale))), Image.BILINEAR)
    angle = rng.uniform(0, 360)
    mask = Image.new("L", note.size, 255).rotate(angle, expand=True, resample=Image.BILINEAR)
    note = note.rotate(angle, expand=True, resample=Image.BILINEAR)
    if note.width > size or note.height > size:
        f = size / max(note.size)
        note = note.resize((int(note.width * f), int(note.height * f)), Image.BILINEAR)
        mask = mask.resize(note.size, Image.BILINEAR)
    x = rng.randint(0, size - note.width)
    y = rng.randint(0, size - note.height)
    bg.paste(note, (x, y), mask)
    return bg


def write_composites(out: Path, train: list[Sample], per_class: int, extra_bg_dir: str | None, seed: int) -> int:
    rng = random.Random(seed)
    bg_paths = [s.path for s in train if s.label == BACKGROUND and s.box is None]
    if extra_bg_dir:
        bg_paths += list(_images_under(Path(extra_bg_dir)))
    if not bg_paths:
        print("  no background images; skipping composites")
        return 0
    by_label = defaultdict(list)
    for s in train:
        if s.label != BACKGROUND:
            by_label[s.label].append(s)
    written = 0
    for label, items in by_label.items():
        (out / "train" / label).mkdir(parents=True, exist_ok=True)
        for k in range(per_class):
            s = rng.choice(items)
            bg = ImageOps.exif_transpose(Image.open(rng.choice(bg_paths))).convert("RGB")
            img = make_composite(load_sample_image(s), bg, rng)
            img.save(out / "train" / label / f"syn_{k:05d}.jpg", quality=92)
            written += 1
    return written


# ----------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sources", default="sources.yaml")
    ap.add_argument("--out", default="data/unified")
    ap.add_argument("--val", type=float, default=0.15)
    ap.add_argument("--test", type=float, default=0.15)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--dup-distance", type=int, default=3, help="dHash Hamming distance treated as duplicate (max 3)")
    ap.add_argument("--composites-per-class", type=int, default=0, help="synthetic train images per note class")
    ap.add_argument("--background-dir", default=None, help="extra background photos for composites")
    args = ap.parse_args()

    cfg = yaml.safe_load(Path(args.sources).read_text(encoding="utf-8"))
    samples: list[Sample] = []
    for src in cfg["sources"]:
        collect = collect_yolo if src.get("format") == "yolo" else collect_folders
        found = collect(src)
        print(f"{src['name']}: {len(found)} samples")
        samples += found

    bad = sorted({s.label for s in samples if not is_valid_label(s.label)})
    if bad:
        print(f"WARNING: labels outside config.KNOWN_DENOMINATIONS: {bad}")

    print("Hashing images...")
    kept = []
    for s in samples:
        try:
            s.hash = dhash(load_sample_image(s))
            kept.append(s)
        except Exception as e:  # corrupt files are common in scraped sets
            print(f"  unreadable {s.path}: {e}")
    samples = kept
    group_near_duplicates(samples, min(args.dup_distance, 3))

    # Near-duplicates carrying different labels are label noise. Report them
    # and drop the whole group.
    labels_per_group = defaultdict(set)
    for s in samples:
        labels_per_group[s.group].add(s.label)
    conflicted = {g for g, ls in labels_per_group.items() if len(ls) > 1}
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    with open(out / "conflicts.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["group", "label", "source", "path"])
        for s in samples:
            if s.group in conflicted:
                w.writerow([s.group, s.label, s.source, s.path])
    samples = [s for s in samples if s.group not in conflicted]
    n_groups = len({s.group for s in samples})
    print(f"{len(samples)} samples in {n_groups} duplicate groups; dropped {len(conflicted)} conflicting groups")

    split_by_group(samples, args.val, args.test, args.seed)

    counters = defaultdict(Counter)
    with open(out / "manifest.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["path", "label", "split", "source", "group"])
        for i, s in enumerate(samples):
            dst = out / s.split / s.label / f"{s.source}_{i:06d}.jpg"
            dst.parent.mkdir(parents=True, exist_ok=True)
            load_sample_image(s).save(dst, quality=92)
            w.writerow([dst.relative_to(out).as_posix(), s.label, s.split, s.source, s.group])
            counters[s.split][s.label] += 1

    if args.composites_per_class:
        n = write_composites(out, [s for s in samples if s.split == "train"],
                             args.composites_per_class, args.background_dir, args.seed)
        print(f"wrote {n} synthetic composites into train/")

    labels = sorted({s.label for s in samples})
    print(f"\n{'label':<12}{'train':>8}{'val':>8}{'test':>8}")
    for label in labels:
        row = [counters[sp][label] for sp in ("train", "val", "test")]
        flag = "  <- under 150 train images" if row[0] < 150 else ""
        print(f"{label:<12}{row[0]:>8}{row[1]:>8}{row[2]:>8}{flag}")
    if BACKGROUND not in labels:
        print("\nWARNING: no 'background' class. The model will name a note even when none is in view.")


if __name__ == "__main__":
    main()
