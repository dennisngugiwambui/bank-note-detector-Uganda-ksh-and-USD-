"""tf.data input pipeline, shared by training, export and evaluation.

Preprocessing contract, mirrored exactly by the Android app (Letterbox.kt):
  1. Decode as RGB.
  2. Letterbox to IMG_SIZE x IMG_SIZE: keep the aspect ratio, pad with black,
     centre the image (tf.image.resize_with_pad, bilinear).
  3. Feed raw float pixels in 0..255. The model's first layer normalizes them.

The reference repos each used a different normalization: mean/std 127.5,
mean/std 128, or a 1/255 rescale. Putting it inside the model removes that
whole class of mismatch bugs.
"""

from __future__ import annotations

from pathlib import Path

import keras
import tensorflow as tf

from config import IMAGE_EXTENSIONS, IMG_SIZE

AUTOTUNE = tf.data.AUTOTUNE


def list_split(root: Path, split: str, labels: list[str] | None = None):
    split_dir = root / split
    if labels is None:
        labels = sorted(p.name for p in split_dir.iterdir() if p.is_dir())
    paths, ys = [], []
    for i, label in enumerate(labels):
        for p in sorted((split_dir / label).glob("*")):
            if p.suffix.lower() in IMAGE_EXTENSIONS:
                paths.append(str(p))
                ys.append(i)
    return paths, ys, labels


def load_letterboxed(path: tf.Tensor, size: int = IMG_SIZE) -> tf.Tensor:
    img = tf.io.decode_image(tf.io.read_file(path), channels=3, expand_animations=False)
    img = tf.image.resize_with_pad(tf.cast(img, tf.float32), size, size, method="bilinear")
    return tf.clip_by_value(img, 0.0, 255.0)


def _photometric(img: tf.Tensor) -> tf.Tensor:
    """Per-image camera-realistic distortions. Input and output are 0..255 floats."""
    x = img / 255.0
    x = tf.image.random_saturation(x, 0.6, 1.4)
    x = tf.image.random_hue(x, 0.04)  # small shifts only: colour separates denominations
    # white-balance / colour-temperature shift
    x = x * tf.random.uniform([1, 1, 3], 0.85, 1.15)
    x = tf.clip_by_value(x, 0.0, 1.0)
    # JPEG re-compression, as in camera frames
    x = tf.image.random_jpeg_quality(x, 40, 95)
    # occasional defocus blur, done by a downscale and upscale
    def blur(t):
        s = tf.shape(t)[:2]
        small = tf.cast(tf.cast(s, tf.float32) * tf.random.uniform([], 0.35, 0.7), tf.int32)
        return tf.image.resize(tf.image.resize(t[None], small), s)[0]

    x = tf.cond(tf.random.uniform([]) < 0.25, lambda: blur(x), lambda: x)
    return x * 255.0


def _cutout(img: tf.Tensor) -> tf.Tensor:
    """Random rectangle covering up to ~25% of the frame, like a finger or another note.
    Applied to half of the images."""
    apply = tf.cast(tf.random.uniform([]) < 0.5, tf.float32)
    h, w = tf.shape(img)[0], tf.shape(img)[1]
    ch = tf.cast(tf.cast(h, tf.float32) * tf.random.uniform([], 0.15, 0.5), tf.int32)
    cw = tf.cast(tf.cast(w, tf.float32) * tf.random.uniform([], 0.15, 0.5), tf.int32)
    y = tf.random.uniform([], 0, h - ch + 1, dtype=tf.int32)
    x = tf.random.uniform([], 0, w - cw + 1, dtype=tf.int32)
    color = tf.random.uniform([3], 0, 255)
    patch = tf.ones([ch, cw, 3]) * color
    paddings = [[y, h - y - ch], [x, w - x - cw], [0, 0]]
    mask = tf.pad(tf.ones([ch, cw, 3]), paddings) * apply
    return img * (1 - mask) + tf.pad(patch, paddings) * apply


def geometric_augmenter() -> keras.Sequential:
    # No horizontal flip: a mirrored note never appears in real use and its text
    # reads backwards. Curency_Detection trains with fliplr=0.5.
    return keras.Sequential([
        keras.layers.RandomRotation(0.5, fill_mode="constant", fill_value=0.0),  # any angle
        keras.layers.RandomZoom((-0.25, 0.25), fill_mode="constant", fill_value=0.0),
        keras.layers.RandomTranslation(0.12, 0.12, fill_mode="constant", fill_value=0.0),
        keras.layers.RandomContrast(0.3),
        keras.layers.RandomBrightness(0.3, value_range=(0.0, 255.0)),
    ], name="augment")


def make_dataset(paths, ys, num_classes, batch, training, size=IMG_SIZE, seed=0):
    ds = tf.data.Dataset.from_tensor_slices((paths, ys))
    if training:
        ds = ds.shuffle(len(paths), seed=seed, reshuffle_each_iteration=True)
    ds = ds.map(lambda p, y: (load_letterboxed(p, size), y), num_parallel_calls=AUTOTUNE)
    if training:
        ds = ds.map(lambda x, y: (_cutout(_photometric(x)), y), num_parallel_calls=AUTOTUNE)
    ds = ds.batch(batch, drop_remainder=training)
    if training:
        aug = geometric_augmenter()
        ds = ds.map(lambda x, y: (tf.clip_by_value(aug(x, training=True), 0.0, 255.0), y),
                    num_parallel_calls=AUTOTUNE)
    ds = ds.map(lambda x, y: (x, tf.one_hot(y, num_classes)), num_parallel_calls=AUTOTUNE)
    return ds.prefetch(AUTOTUNE)
