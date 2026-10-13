"""End-to-end smoke test of the training pipeline on a tiny synthetic dataset.

It checks that every script runs and the outputs connect: folder and YOLO
sources, duplicate grouping, composites, training, int8/fp16 export,
evaluation of the .tflite, and the authenticity model. It says nothing about
real accuracy.

  python smoke_test.py            (about 5-10 minutes on CPU)
"""

from __future__ import annotations

import random
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
CLASSES = {"INR_100": (120, 80, 160), "KES_50": (200, 60, 40), "UGX_5000": (40, 150, 70), "USD_20": (60, 120, 90)}


def fake_note(label: str, rng: random.Random) -> Image.Image:
    base = CLASSES[label]
    img = Image.new("RGB", (300, 150), tuple(min(255, c + rng.randint(-15, 15)) for c in base))
    d = ImageDraw.Draw(img)
    idx = list(CLASSES).index(label)
    for k in range(idx + 2):  # class-specific bar count
        x = 30 + k * 40
        d.rectangle([x, 20, x + 15, 130], fill=(255, 255, 255))
    d.ellipse([200, 30, 280, 120], outline=(0, 0, 0), width=4)
    return img


def fake_background(rng: random.Random) -> Image.Image:
    arr = np.random.default_rng(rng.randint(0, 1 << 30)).integers(0, 255, (200, 260, 3), dtype=np.uint8)
    return Image.fromarray(arr).filter(ImageFilter.GaussianBlur(rng.uniform(2, 8)))


def stripes(rng: random.Random, fake: bool) -> Image.Image:
    img = Image.new("RGB", (640, 320), (230, 220, 200))
    d = ImageDraw.Draw(img)
    for x in range(0, 640, 3):
        d.line([x, 0, x + rng.randint(-5, 5), 320], fill=(40, 60, 90), width=1)
    if fake:
        img = img.filter(ImageFilter.GaussianBlur(1.6))
    return img


def build_raw(root: Path) -> None:
    rng = random.Random(0)
    for label in CLASSES:
        out = root / "folders" / label
        out.mkdir(parents=True)
        for i in range(30):
            note = fake_note(label, rng).rotate(rng.uniform(-10, 10), expand=True)
            note.save(out / f"{i}.jpg")
            if i < 5:  # near-duplicates, which must stay in one split
                note.point(lambda v: min(255, v + 3)).save(out / f"{i}_dup.jpg")
    bg = root / "folders" / "bg"
    bg.mkdir()
    for i in range(60):
        fake_background(rng).save(bg / f"{i}.jpg")
    # YOLO-format source with notes pasted into larger scenes
    yolo = root / "yolo"
    (yolo / "train" / "images").mkdir(parents=True)
    (yolo / "train" / "labels").mkdir(parents=True)
    (yolo / "data.yaml").write_text("names: ['inr100', 'kes50']\n")
    for i in range(20):
        scene = fake_background(rng).resize((640, 480))
        cls = i % 2
        note = fake_note(["INR_100", "KES_50"][cls], rng)
        x, y = rng.randint(0, 300), rng.randint(0, 300)
        scene.paste(note, (x, y))
        scene.save(yolo / "train" / "images" / f"{i}.jpg")
        cx, cy = (x + 150) / 640, (y + 75) / 480
        (yolo / "train" / "labels" / f"{i}.txt").write_text(f"{cls} {cx:.4f} {cy:.4f} {300 / 640:.4f} {150 / 480:.4f}\n")
    for kind, n in (("genuine", 30), ("counterfeit", 30), ("holdout_fake", 8)):
        d = root / "auth" / kind
        d.mkdir(parents=True)
        for i in range(n):
            stripes(rng, fake=kind != "genuine").save(d / f"{i}.jpg")


def run(*args: str) -> None:
    print("\n$", " ".join(args), flush=True)
    subprocess.run([sys.executable, *args], cwd=HERE, check=True)


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        raw = tmp / "raw"
        build_raw(raw)
        sources = tmp / "sources.yaml"
        sources.write_text(f"""
sources:
  - name: folders
    format: folders
    root: {(raw / 'folders').as_posix()}
    mapping: {{INR_100: INR_100, KES_50: KES_50, UGX_5000: UGX_5000, USD_20: USD_20, bg: background}}
  - name: yolo
    format: yolo
    root: {(raw / 'yolo').as_posix()}
    mapping: {{inr100: INR_100, kes50: KES_50}}
""")
        data, runs = tmp / "unified", tmp / "runs"
        run("prepare_dataset.py", "--sources", str(sources), "--out", str(data), "--composites-per-class", "10")
        run("train_classifier.py", "--data", str(data), "--out", str(runs / "cls"), "--alpha", "0.35",
            "--img", "96", "--epochs-head", "2", "--epochs-ft", "2", "--batch", "8")
        run("export_tflite.py", "--run", str(runs / "cls"), "--data", str(data), "--rep-count", "20",
            "--android-assets", str(tmp / "assets" / "currency"))
        run("evaluate_tflite.py", "--model", str(runs / "cls" / "model_int8.tflite"), "--data", str(data))
        run("train_authenticity.py", "--currency", "UGX", "--genuine", str(raw / "auth" / "genuine"),
            "--counterfeit", str(raw / "auth" / "counterfeit"), "--holdout-counterfeit", str(raw / "auth" / "holdout_fake"),
            "--out", str(runs / "auth"), "--alpha", "0.35", "--epochs", "2", "--patches-per-image", "2",
            "--android-assets", str(tmp / "assets" / "authenticity" / "UGX"))
        run("train_authenticity.py", "--currency", "UGX", "--step", "backlight", "--genuine", str(raw / "auth" / "genuine"),
            "--counterfeit", str(raw / "auth" / "counterfeit"), "--out", str(runs / "auth_backlight"),
            "--alpha", "0.35", "--epochs", "2", "--patches-per-image", "2",
            "--android-assets", str(tmp / "assets" / "authenticity" / "UGX"))
        produced = sorted(p.relative_to(tmp).as_posix() for p in (tmp / "assets").rglob("*") if p.is_file())
        print("\nassets produced:", produced)
        expected = {"assets/currency/model.tflite", "assets/currency/labels.txt",
                    "assets/authenticity/UGX/model.tflite", "assets/authenticity/UGX/labels.txt",
                    "assets/authenticity/UGX/threshold.txt", "assets/authenticity/UGX/backlight.tflite",
                    "assets/authenticity/UGX/backlight_threshold.txt"}
        missing = expected - set(produced)
        assert not missing, f"missing outputs: {missing}"
        print("SMOKE TEST PASSED")


if __name__ == "__main__":
    main()
