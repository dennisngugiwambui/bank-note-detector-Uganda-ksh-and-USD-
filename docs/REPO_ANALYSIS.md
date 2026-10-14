# Reference repo analysis

All 7 repos were cloned and read on 2026-10-13. For each one: how it trains,
how it runs inference, what is broken, and what this project reuses or fixes.

## Summary

| Repo | Currency | Approach | Model / runtime | Background class | Main problems |
|---|---|---|---|---|---|
| vkannantech/Curency_Detection | INR notes + coins | YOLO11/26 **detection** (Ultralytics) | PyTorch → ONNX/TFLite, Raspberry Pi | `None` class | Fake full-frame boxes, leaky split, broken label names |
| hiruthikj/currency-recognition | INR 20/50/100/500 | **No ML**: ORB keypoints + brute-force matching vs 4 templates | OpenCV desktop script | Ratio threshold only | Binarizes before ORB, crashes on edge cases, visualizes wrong match |
| Braillo/braillo-android-version | Egyptian (by the labels) | Image classifier + SSD COCO + OCR + barcode | Java, TFLite `MN26_30.tflite` | No | Reloads model every frame, single-frame 0.4 threshold, cryptic labels |
| Riaz-Mahmud/Blind-People-Smart-AID | BDT 100/500/1000 | Teachable Machine classifier + SSD MobileNet COCO | Java, TF Lite example app (Camera2) | **Yes** (`EmptySpace`) | README says ResNet50, but the model file is a Teachable Machine export; ships an unused 17 MB model |
| odhiamboatieno/Kenyan-Currency-Detector | KES 50–1000 | Teachable Machine classifier | Java, TF Lite example app | **No** | Always names a note, even an empty table; no training code or data |
| chandran-jr/Noteify | INR 50–2000 | Teachable Machine classifier | Flutter + deprecated `tflite` plugin | No | Author says it no longer builds; INR 2000 withdrawn from circulation |
| xiaoyongzhu/SeeingAI-Currency-Detection | USD (front/back = 14 classes) | Keras MobileNet v1 transfer learning | Keras → CoreML/ONNX | Described, **missing from the code** | Wrong normalization for the ImageNet weights; `Dense(14)` has no background class |

## How each repo trains and runs, and what is wrong

### 1. Curency_Detection (YOLO, INR)
- **Training** (`scripts/train.py`): Ultralytics YOLO, `imgsz` 960, AdamW, cosine LR, mosaic/mixup, HSV jitter, `fliplr=0.5`.
- **Bug: fake boxes.** `build_unified_dataset.py` takes *classification* folders (Kaggle zips) and writes the label `class 0.5 0.5 0.95 0.95` for every image. The detector then learns "the box is the whole frame". Its mAP looks high but measures nothing about localization, and notes held small in the frame get missed.
- **Bug: leaky split.** `split = 'train' if random.random() < 0.8 else 'valid'` per image. Kaggle INR sets contain augmented copies of the same photo, so copies land in both splits and validation accuracy is inflated.
- **Bug: label names don't match.** `data.yaml` names classes `'10','100',…,'None','1','2'`, but `labels.py` speaks `inr_100_note` and so on. `to_spoken_label('100')` falls through to the raw string, and every `"coin" in to_spoken_label(label)` check in `camera.py` (lines 91 and 222) is always false, so the coin-specific verification never runs.
- `fliplr=0.5` trains on mirrored notes (backwards text), which never occur in real use.
- Hard-coded Windows paths (`C:\Users\KANNAN-V\Downloads\…`).
- **Reused here:** temporal majority voting over a frame window, blur ("shaking") check, low-light handling, duplicate-speech suppression, running total.

### 2. currency-recognition (ORB template matching)
- **Approach:** grayscale → bilateral blur → **Otsu binarization** → morphological open → ORB → BFMatcher + Lowe ratio 0.6; picks the template with the most good matches; accepts at ≥ 5 matches and ≥ 40% of all good matches.
- **Problems:** binarizing before ORB throws away the texture ORB depends on. Only 4 templates (no 10/200 notes, one side only). `des1`/`des2` is `None` on a featureless image, and `knnMatch` pairs with fewer than 2 neighbours raise `ValueError` in `for m, n in all_matches`. The final `drawMatchesKnn` uses `good` from the *last* loop iteration, not the best one, so the visualization is wrong.
- **Possible future use:** keypoint matching plus homography against a reference note is a good *registration* step. It could align a note before checking a specific security-feature region. Not used yet.

### 3. Braillo (Java, multi-feature)
- Currency model `Models/MN26_30.tflite`, labels `lab26.txt` = `10 11 20 22 30 33 … 99` (18 opaque codes mapped to `.mp3` files, likely denomination × side).
- `UI_Connection.currency()` builds `new CurrencyModelClassifier(...)` **on every call**, reloading the interpreter each frame. It speaks the top class from one frame if confidence > 0.4.
- Normalization mean/std 128 (others use 127.5). This only works because each repo's training happened to match it.
- **Reused here:** the feature set (currency + objects + OCR/colour later) as one app with modes.

### 4. Blind-People-Smart-AID (Java, BDT)
- Classifier `model.tflite` (793 KB) / `model_unquant.tflite` (2.09 MB), labels `100, 500, 1000, EmptySpace`. The README claims "Resnet50, 100 epochs", but the file sizes and names are the standard Teachable Machine export, nearly byte-identical in size to the Kenyan repo's model.
- Objects: SSD MobileNet COCO `detect.tflite`, 300×300 quantized, min confidence 0.5.
- Also bundles `mobilenet_v1_1.0_224.tflite` (17 MB) and its quantized copy, which add APK size.
- **Reused here:** the `EmptySpace`/background idea and the COCO detector for "what's in front of me".

### 5. Kenyan-Currency-Detector (Java, KES)
- Labels `1000, 500, 200, 100, 50`, 224 input, float model normalized `(x-127.5)/127.5`. Teachable Machine export inside the stock TF Lite classification example (Camera2 API, Java).
- **No background class**, so it always outputs one of the 5 notes. No dataset or training code is published. It is unclear whether it covers the 2019 note series. **Retrain on your own photos of current notes.**

### 6. Noteify (Flutter, INR)
- Teachable Machine `model_unquant.tflite`, labels `2000/500/200/100/50 rupees`, `tflite` plugin with `threshold: 0.5`, `imageMean/Std 127.5`, flutter_tts, running total.
- The `tflite` plugin is abandoned, and the author notes the app no longer works. **This project uses `tflite_flutter`, the maintained plugin.**

### 7. SeeingAI-Currency-Detection (Keras, USD)
- MobileNet v1 (ImageNet), `pooling='avg'`, `Dense(14, softmax)`, last 10 layers trainable, Adam 1e-3, `ImageDataGenerator(rescale=1/255)`.
- **Bug:** Keras MobileNet ImageNet weights expect inputs in `[-1, 1]`, but this trains with `[0, 1]`.
- **Bug:** the blog describes 15 classes including a background class with 5× more images, but the published code has `Dense(14)` and no background.
- **Most valuable lessons (from its README):** the note should cover at least 1/6 of the frame; vary position and angle; partial occlusion up to 40%; diverse backgrounds. Seeing AI speaks continuously so a blind user can frame the note.

### 8. fake-currency-identification (bkataru, INR, Raspberry Pi)
- Three-lighting method: one photo under normal light, one backlit (watermark, security thread), one under a UV lamp (fluorescent fibres). A separate CNN scores each image, and the note is called genuine only if all three agree.
- Hardware rig: a Raspberry Pi drives white and UV LEDs through GPIO, so lighting is identical for every photo. A phone cannot reproduce that, so lighting varies far more in the field.
- **Bug:** the train and validation images come from the same handful of physical notes photographed repeatedly, so its reported accuracy measures memorisation of those notes.
- **License:** GPL-3.0. Its code and trained weights cannot ship inside a closed app that is resold. **This project re-implements the idea only** (`train_authenticity.py --step print|backlight|uv`) and uses no code or models from it.
- **What we kept:** the multi-step lighting idea and "fail if any step fails". The app guides the user through each step by voice (Settings → Counterfeit check).

## Design reference (Dribbble, Flutter tag)
The UI follows the current fintech/"bento" style seen in those templates: rounded 28 px cards, one strong accent colour (lime by default), large numerals, a floating pill navigation bar, glass panels over the camera, and animated confidence rings. Everything is built from tokens in `app/lib/ui/theme.dart` (`AppTokens`), so a reseller can rebrand by changing the accent and the token values. High-contrast mode (black and yellow) and text size up to 160% exist for low-vision users.

## What this project does differently

| Problem seen | Fix (file) |
|---|---|
| No "no note" output | `background` class + `sources.yaml` background source (`training/prepare_dataset.py`) |
| Leaky random split | dHash near-duplicate grouping, split by group (`prepare_dataset.py`) |
| Fake YOLO boxes | YOLO boxes are cropped into classification samples (`collect_yolo`) |
| Contradicting labels | Near-duplicates with different labels written to `conflicts.csv` and dropped |
| Tight crops ≠ live camera | Synthetic composites: note pasted onto a background at a random scale/angle (`--composites-per-class`) |
| Normalization mismatches | Normalization layer inside the model; the app feeds raw 0..255 |
| Squashed aspect ratio | Letterbox in training (`data.py`) and the app (`frame.dart`) |
| Mirrored-note augmentation | No flips; rotation, zoom, blur, JPEG, white balance, cutout (`data.py`) |
| Uncalibrated confidence | Temperature scaling; threshold chosen by measured precision (`evaluate_tflite.py`) |
| Single-frame announcements | 5-of-7 frame vote + re-arm when the note leaves (`PredictionSmoother`) |
| Model reloaded per frame | Loaded once; inference in a background isolate (`tflite_model.dart`) |
| Deprecated Flutter plugin | `tflite_flutter` + `camera` + `flutter_tts` |
| Counterfeit not handled | Per-currency print / backlight / UV models + manual checks (`docs/COUNTERFEIT_DETECTION.md`) |
| GPL code in a resale product | Clean-room re-implementation of the 3-lighting method |

## 9. Assistive-navigation repos (second review)

These five repos were reviewed for their architecture and for training data or weights that could make NoteLens more accurate.

| Repo | What it is | Reusable data or weights? |
|---|---|---|
| rajshekarm/Smart-Real-Time-Multimodal-Assistance-System | Real-time detection + speech assistant | No custom dataset. Ideas kept: priority classes, cooldowns, speak only on change |
| shrijayan/Vision-Assistance | Camera assistant with spoken output | No custom dataset |
| UzaifTalpur/Smart-Glasses-For-Visually-Impaired | Raspberry Pi + TensorFlow Lite + OpenCV glasses with audio feedback | Stock COCO model only |
| jayjmha/Assistance-System-for-the-Blind-using-Object-Detection | Jetson Nano, YOLOv7 fine-tuned on a custom pedestrian dataset, TensorRT, auditory guidance | GPL, and the dataset is Korean street scenes. Not usable in a closed app that is sold |
| harshgondaliya/Multi-feature-Smart-Stick-for-Blind | Arduino stick: ultrasonic obstacle sensing, water sensing, stick finder | No ML |

None of them has data that would make the money model or the object detector more accurate on Kenyan or Ugandan streets. Their useful ideas were re-implemented, and two problems found in field testing were fixed at the root:

| Field problem | Cause | Fix |
|---|---|---|
| "A car in front was said to be on my left" | Direction came from the raw camera frame, so holding the phone sideways swapped the axes. A label was spoken once and then not updated | Boxes are rotated by the accelerometer pose before computing the bearing. Bearing comes from the camera field of view, in degrees (`scene_tracker.dart`, `orient`) |
| "It tells me when I am already there" | Alerts fired on box size alone, every 600 ms. A fresh isolate was spawned per frame | Distance from known object heights + camera tilt; **time to contact** from the growth rate of the box (regression of ln height over 1.6 s); alerts at TTC < 3.5 s (any obstacle in the walking corridor) or < 5 s (vehicles). Frames are processed back to back through one persistent worker isolate (`frame_worker.dart`) |
| A pen read as "knife", a desk as "dining table, very close" | Single-frame detections, low thresholds, camera pointed down | A track must be seen twice (or be > 0.7). Thresholds per class. No hazards while the phone points at the floor, and large surfaces are ignored |
| Money not announced in Objects mode | Separate modes | The money model also runs on every 2nd frame in Objects mode, with a stricter vote (≥ 0.92, 5 of 6) |
| Text pop-ups useless to blind users | | Pop-ups are off by default. Everything is spoken, with vibration patterns, and proximity pulses speed up as an obstacle nears |

Money model v2 adds coins (KES, INR, EGP, USD), Kenyan 2019-series and Ugandan 2010-series notes, and an embedding output so users can **teach** a note on the phone (`TaughtNotes`, cosine k-NN). Data and licences: `docs/MODEL_DATA_LICENSES.md`.
