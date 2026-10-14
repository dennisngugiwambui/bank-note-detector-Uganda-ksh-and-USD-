# NoteLens: banknote identifier (INR · KES · EGP · UGX · USD)

An offline Flutter app for blind and low-vision users. It has four parts:
- **Money:** identifies banknote denominations live and speaks them, with a running wallet total.
- **Check fake:** a guided, spoken check under normal light, backlight and (optionally) UV light, plus manual checks for every currency. This is a screening aid, not proof. See `docs/COUNTERFEIT_DETECTION.md`.
- **Objects / safety alerts:** EfficientDet-Lite2 (80 everyday objects with positions) plus an ImageNet classifier (1000 things: shoes, clothes, windows...) describe what is in front of the user ("person ahead, chair on your left") and warns, by voice, vibration and banner, when a person, vehicle or obstacle is in the path.
- **Activity centre:** every note, verdict and alert, with filters and unread badges.

First launch goes onboarding (spoken) → sign in / create account / continue as guest → home dashboard.
Everything can be changed in Settings: theme, accent colour, high contrast, text size, voice speed, pitch and language, vibration, recognition certainty, auto light, which currencies to recognise, counterfeit steps, and obstacle alert distance.

## Layout

```
training/                 Python / TensorFlow pipeline
  sources.example.yaml    map each downloaded dataset onto unified labels (copy to sources.yaml)
  prepare_dataset.py      merge, dedupe, group-aware split, YOLO crops, synthetic composites
  train_classifier.py     MobileNetV2 transfer learning + fine-tuning + temperature calibration
  export_tflite.py        int8 (default, ~3 MB) and fp16 TFLite, copies into the app
  evaluate_tflite.py      evaluates the exact .tflite, per-source accuracy, threshold sweep
  train_authenticity.py   per-currency genuine/counterfeit model, --step print|backlight|uv
  smoke_test.py           end-to-end test of every script on synthetic data
app/                      Flutter app (Android + iOS)
  lib/core/               settings, auth (local; swappable for a cloud backend), activity store, currencies
  lib/ml/                 frame preprocessing, TFLite wrapper, classifier, detector, authenticity
  lib/services/           voice + vibration (screen-reader aware)
  lib/scan_controller.dart  camera and scanning logic, no widgets
  lib/ui/                 design system (theme.dart, widgets.dart) and screens
  assets/                 models go here (the object detector is already included)
  test/                   unit + widget tests (15)
docs/REPO_ANALYSIS.md     what the 8 reference repos do and where they break, plus design notes
docs/COUNTERFEIT_DETECTION.md
```

## 1. Install the APK on your phone

Release APKs are built in `app/build/app/outputs/flutter-apk/`:
- `app-arm64-v8a-release.apk` (30 MB): almost every phone from 2017 onward. Use this one.
- `app-armeabi-v7a-release.apk` (26 MB): older 32-bit phones.
- `app-release.apk` (79 MB): works on any phone, if unsure.
1. Copy it to the phone (USB, Google Drive, or WhatsApp to yourself).
2. Open it on the phone. Android asks to allow installs from that source; allow it once.
3. Grant the camera permission when the app asks.

Or with the phone plugged in and USB debugging on: `flutter install --release` from `app/`.

Until you train and copy the currency model (step 2), the app says "currency model not installed".
Objects mode, safety alerts, manual counterfeit checks, settings and the activity centre all work already.

## 2. Train the models

```powershell
cd training
python -m venv .venv; .\.venv\Scripts\activate
pip install -r requirements.txt
python smoke_test.py                        # optional: checks the whole pipeline in ~10 min
# sources.yaml lists every dataset used for model v2 (notes + coins), with licences.
# Put your own phone photos in raw/own_photos/<label>/ (e.g. KES_100, KES_20_coin).
python prepare_dataset.py --sources sources.yaml --out data/v2 --composites-per-class 100 `
  --composites-min-total 380 --background-dir raw/x/rooms/kaggle_room_street_data/house_data
python train_classifier.py --data data/v2 --out runs/v2
python export_tflite.py --run runs/v2 --data data/v2 --android-assets ../app/assets/currency
python evaluate_tflite.py --model runs/v2/model_int8.tflite --data data/v2
```
Labels: `KES_100` (note), `KES_20_coin` (coin), `USD_25c_coin` (cents), `background`.
The exported model has a second output (an embedding) that powers
**Settings → Teach a note**: a helper shows the phone a note or coin for about
6 seconds and NoteLens recognises it from then on, even one the model was
never trained on. Data sources and which ones may be used in a paid release:
`docs/MODEL_DATA_LICENSES.md`.
The sweep prints the lowest threshold with precision ≥ 0.99. Set it as the
default `sensitivity` in `app/lib/core/settings.dart` (users can still change
it under Settings → "Certainty before speaking").

Counterfeit models (UGX first, Mendeley dataset). One run per lighting step:
```powershell
python train_authenticity.py --currency UGX --genuine <genuine dir> --counterfeit <fake dir> `
  --holdout-counterfeit <fakes from another printer> --out runs/auth_ugx --android-assets ../app/assets/authenticity/UGX
python train_authenticity.py --currency UGX --step backlight --genuine <backlit genuine> --counterfeit <backlit fakes> `
  --out runs/auth_ugx_bl --android-assets ../app/assets/authenticity/UGX
```

## 3. Build the app yourself

Needs the Flutter SDK (3.32+), the Android SDK with NDK 28.2.13676358, and JDK 17+.
```powershell
cd app
powershell -ExecutionPolicy Bypass -File tool\setup.ps1   # only once: generates android/ and ios/, sets minSdk 26
flutter test
flutter build apk --release                               # or --split-per-abi for smaller APKs
```
The APK is signed with the debug key so it installs directly. Before selling it
or uploading to Play, create an upload keystore and set `signingConfig` in
`android/app/build.gradle.kts` (see flutter.dev/to/review-gradle-config).

## Reselling / rebranding

- Colours, radius and spacing are tokens in `app/lib/ui/theme.dart`; the accent list is in `settings.dart`.
- App name: `android/app/src/main/AndroidManifest.xml` (`android:label`) and `MaterialApp.title` in `main.dart`.
- Accounts are local to the phone (`LocalAuthService`). To sync across devices, implement `AuthService` with Firebase or your own backend and swap it in `main.dart`.
- Do not include code or models from GPL repositories (e.g. bkataru/fake-currency-identification) in a closed product.

## Adding a currency later

1. Add its notes to `sources.yaml` and its denominations to `training/config.py`.
2. Add it to `currencyCatalog` in `app/lib/core/currency.dart`, and manual checks in `assets/security_features.json`.
3. Retrain and export. Labels are read from `labels.txt`, so no other app code changes.
4. Optional authenticity models: create `assets/authenticity/<ISO>/` and list it in `pubspec.yaml`.
