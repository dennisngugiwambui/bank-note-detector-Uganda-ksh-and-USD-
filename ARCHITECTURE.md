# Multi-Currency Banknote Identifier Architecture

## 1. System Overview
An offline, edge-AI Android mobile application designed to detect and verbally announce banknotes from five national currencies:
- **INR** (Indian Rupee)
- **KES** (Kenyan Shilling)
- **EGP** (Egyptian Pound)
- **UGX** (Ugandan Shilling)
- **USD** (United States Dollar)

The system is optimized for accessibility (visually impaired users), operating completely on-device without internet access, with high throughput (>=30 FPS frame analysis) and low latency (<15 ms inference).

```
+-----------------------------------------------------------------------------------+
|                               SYSTEM DATAFLOW PIPELINE                            |
+-----------------------------------------------------------------------------------+

 [ CameraX Live Feed (30 FPS) ]
               |
               v
 [ ImageAnalysis.Analyzer ]  ---> Converts ImageProxy to RGBA Bitmap, applies rotation
               |
               v
 [ BanknoteClassifier (TFLite) ]
      * Model: MobileNetV2 (INT8 Quantized, ~3.2 MB)
      * Inputs: 224 x 224 x 3, normalized to [-1, 1]
      * Hardware Delegate: NNAPI / GPU (with 4-thread CPU fallback)
               |
               v
 [ Post-Processing & Filtering ]
      * Confidence Threshold check (>= 82%)
      * Negative Class rejection ('Background' class)
      * Multi-Frame Temporal Filter (>= 3 consecutive hits)
      * Speech Cooldown Debouncer (2500 ms minimum interval)
               |
        +------+------+
        |             |
        v             v
 [ Visual HUD ]    [ Android TTS Engine ]
  Name, Denom,      "100 Kenyan Shilling"
  Confidence %
```

---

## 2. Model & ML Architecture

### 2.1 Base Model Selection
- **Backbone**: MobileNetV2 (pretrained on ImageNet-1k)
- **Input Resolution**: `224 x 224 x 3` (RGB)
- **Normalization Formula**: 
  $$\hat{x} = \frac{x}{127.5} - 1.0 \quad \in [-1.0, 1.0]$$
- **Custom Classification Head**:
  - `GlobalAveragePooling2D`
  - `BatchNormalization`
  - `Dropout(0.3)`
  - `Dense(128, activation='relu')`
  - `Dropout(0.2)`
  - `Dense(N_CLASSES, activation='softmax', dtype='float32')`

### 2.2 Class Label Nomenclature
Format: `[ISO_4217_CODE]_[DENOMINATION]`

| Currency | ISO Code | Denomination Classes |
|---|---|---|
| Indian Rupee | INR | `INR_10`, `INR_20`, `INR_50`, `INR_100`, `INR_200`, `INR_500`, `INR_2000` |
| Kenyan Shilling | KES | `KES_50`, `KES_100`, `KES_200`, `KES_500`, `KES_1000` |
| Egyptian Pound | EGP | `EGP_5`, `EGP_10`, `EGP_20`, `EGP_50`, `EGP_100`, `EGP_200` |
| Ugandan Shilling | UGX | `UGX_1000`, `UGX_2000`, `UGX_5000`, `UGX_10000`, `UGX_20000`, `UGX_50000` |
| United States Dollar | USD | `USD_1`, `USD_2`, `USD_5`, `USD_10`, `USD_20`, `USD_50`, `USD_100` |
| Negative / Clutter | N/A | `Background` (desks, hands, empty wallet, ambient rooms) |

### 2.3 Optimization & Quantization
- **Method**: Full Integer (INT8) Post-Training Quantization with representative dataset calibration.
- **Model Size Target**: < 5.0 MB (Actual: ~3.2 MB).
- **Latency Target**: < 15 ms on mid-tier mobile chipsets.

---

## 3. Android Software Architecture

### 3.1 Technology Stack
- **Language**: Kotlin 1.9+
- **Camera Pipeline**: CameraX 1.3+ (`androidx.camera:camera-*`)
- **Inference Runtime**: TensorFlow Lite 2.14+ (`org.tensorflow:tensorflow-lite`, `tensorflow-lite-support`, `tensorflow-lite-gpu`)
- **Accessibility / Audio Output**: Native Android `android.speech.tts.TextToSpeech`
- **UI Framework**: Material Design 3, ViewBinding, ConstraintLayout

### 3.2 Key Software Components
1. **`BanknoteClassifier.kt`**:
   - Manages the lifecycle of `Interpreter` and hardware delegates.
   - Converts input bitmaps using `TensorImage` and `ImageProcessor`.
   - Parses label string into structured currency representations.
2. **`BanknoteAnalyzer.kt`**:
   - Implements `ImageAnalysis.Analyzer`.
   - Normalizes camera sensor rotation.
   - Applies temporal debounce logic (prevents audio spamming).
3. **`MainActivity.kt`**:
   - Manages CameraX lifecycle bindings.
   - Orchestrates TextToSpeech initialization and playback queue (`QUEUE_FLUSH`).
   - Updates HUD overlays with live recognition state.

---

## 4. Operational Requirements & Edge-Case Handling

1. **False Positive Suppression**:
   - The dedicated `Background` class prevents hallucinations when no note is in the frame.
   - Any prediction with confidence `< 82%` is suppressed.
2. **Audio Debouncing**:
   - Predictions must match for at least 3 consecutive frames before triggering TTS.
   - Successive announcements of the same bill enforce a 2.5-second cooldown.
   - Switching to a different banknote triggers speech immediately once 3-frame stability is verified.
3. **Expansion Strategy**:
   - New currencies are introduced by appending the standardized class names into the dataset without altering existing indices, followed by fine-tuning the classification head.
