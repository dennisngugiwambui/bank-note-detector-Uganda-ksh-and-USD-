"""
train_and_export.py
Trains a MobileNetV2 transfer learning model on unified banknote classes,
fine-tunes the network, and converts it to an INT8-quantized TFLite model (< 4 MB).
"""

import os
import sys
from pathlib import Path
import tensorflow as tf
from tensorflow.keras import layers, models, optimizers, callbacks

# ----------------- Configuration -----------------
IMG_SIZE = (224, 224)
BATCH_SIZE = 32
INITIAL_EPOCHS = 15
FINE_TUNE_EPOCHS = 10
DATASET_DIR = Path("dataset")
EXPORT_DIR = Path("export")

def main():
    if not (DATASET_DIR / "train").exists():
        print(f"[!] Error: Training directory '{DATASET_DIR / 'train'}' does not exist.")
        print("[!] Please run prepare_dataset.py first or point to your dataset directory.")
        sys.exit(1)

    EXPORT_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Load Dataset
    print("[*] Loading training and validation datasets...")
    train_ds = tf.keras.utils.image_dataset_from_directory(
        DATASET_DIR / "train",
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        shuffle=True
    )

    val_ds = tf.keras.utils.image_dataset_from_directory(
        DATASET_DIR / "val",
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        shuffle=False
    )

    class_names = train_ds.class_names
    num_classes = len(class_names)
    print(f"[*] Total classes ({num_classes}): {class_names}")

    # Export labels.txt immediately
    labels_path = EXPORT_DIR / "labels.txt"
    with open(labels_path, "w", encoding="utf-8") as f:
        for label in class_names:
            f.write(f"{label}\n")
    print(f"[+] Saved labels to: {labels_path}")

    # Performance optimization
    AUTOTUNE = tf.data.AUTOTUNE
    train_ds = train_ds.cache().prefetch(buffer_size=AUTOTUNE)
    val_ds = val_ds.cache().prefetch(buffer_size=AUTOTUNE)

    # 2. Data Augmentation
    data_augmentation = tf.keras.Sequential([
        layers.RandomRotation(0.15),
        layers.RandomZoom(0.15),
        layers.RandomFlip("horizontal_and_vertical"),
        layers.RandomContrast(0.20),
        layers.RandomTranslation(height_factor=0.1, width_factor=0.1)
    ], name="banknote_augmentation")

    # 3. Model Architecture
    print("[*] Building MobileNetV2 transfer learning model...")
    base_model = tf.keras.applications.MobileNetV2(
        input_shape=(224, 224, 3),
        include_top=False,
        weights="imagenet"
    )
    base_model.trainable = False  # Freeze base in Phase 1

    inputs = tf.keras.Input(shape=(224, 224, 3), name="image_input")
    x = data_augmentation(inputs)
    # Preprocessing scales uint8 [0, 255] to float32 [-1, 1]
    x = tf.keras.applications.mobilenet_v2.preprocess_input(x)
    x = base_model(x, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.BatchNormalization()(x)
    x = layers.Dropout(0.3)(x)
    x = layers.Dense(128, activation="relu")(x)
    x = layers.Dropout(0.2)(x)
    outputs = layers.Dense(num_classes, activation="softmax", dtype="float32", name="predictions")(x)

    model = models.Model(inputs, outputs, name="MobileNetV2_BanknoteClassifier")

    # 4. Phase 1: Train Head Only
    print("\n--- Phase 1: Training Custom Classification Head ---")
    model.compile(
        optimizer=optimizers.Adam(learning_rate=1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"]
    )

    early_stop = callbacks.EarlyStopping(
        monitor="val_loss",
        patience=3,
        restore_best_weights=True
    )

    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=INITIAL_EPOCHS,
        callbacks=[early_stop]
    )

    # 5. Phase 2: Fine-Tuning Top Feature Layers
    print("\n--- Phase 2: Fine-Tuning Top Layers ---")
    base_model.trainable = True
    # Freeze lower feature extractors, unfreeze deeper layers
    fine_tune_at = 100
    for layer in base_model.layers[:fine_tune_at]:
        layer.trainable = False

    model.compile(
        optimizer=optimizers.Adam(learning_rate=1e-5),  # Lower LR prevents catastrophic forgetting
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"]
    )

    model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=FINE_TUNE_EPOCHS,
        callbacks=[early_stop]
    )

    # Save Keras Model
    saved_model_path = EXPORT_DIR / "saved_model"
    model.save(saved_model_path)
    print(f"[+] Saved Keras model to: {saved_model_path}")

    # 6. INT8 Post-Training Quantization
    print("\n--- Converting to INT8 Quantized TFLite ---")
    def representative_dataset_gen():
        for images, _ in train_ds.take(20):
            for i in range(min(5, len(images))):
                yield [tf.expand_dims(images[i], 0)]

    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_path))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.representative_dataset = representative_dataset_gen
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.float32   # Keep float32 interface for Android TensorImage
    converter.inference_output_type = tf.float32

    tflite_model = converter.convert()

    tflite_path = EXPORT_DIR / "banknote_model.tflite"
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)

    size_mb = os.path.getsize(tflite_path) / (1024 * 1024)
    print(f"\n[DONE] Successfully generated TFLite model: {tflite_path}")
    print(f"       Model size: {size_mb:.2f} MB (Target: < 5 MB)")

if __name__ == "__main__":
    main()
