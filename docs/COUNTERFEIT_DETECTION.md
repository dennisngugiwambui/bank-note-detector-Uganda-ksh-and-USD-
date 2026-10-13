# Detecting genuine vs fake notes: what's possible with a phone

## The honest constraint

Banks verify notes with **UV light** (fluorescent fibres and inks), **transmitted
light** (watermark, see-through register, security thread), **magnetic/IR ink**
and **tactile intaglio**. A phone's camera sees only reflected visible light, so
most of these features are invisible to a single photo.

What a phone *can* catch is **print quality**: inkjet dot patterns, toner halos,
blurred microtext, missing fine lines, wrong paper texture. That's enough to
flag photocopies and home-printed fakes. It is not enough to certify a note as
genuine. So the app says **"no counterfeit signs found"**, never "genuine",
and always tells the user to confirm with a bank or a trusted person when
in doubt.

None of the 7 reference repos does counterfeit detection.

## What's implemented

1. **Identify first, then authenticate.** The denomination classifier runs
   live. "Check fake" uses the last confirmed note to pick a per-currency
   authenticity model (`assets/authenticity/<ISO>/`).
2. **High-resolution patch model** (`training/train_authenticity.py`). The
   photo is resized to a 448 px short side (about 2× the classifier's
   resolution), and a MobileNetV2-0.5 scores 224 px patches. At inference, a
   3×3 grid of patches from a full-resolution still (`takePicture`, not the
   preview stream) is averaged.
3. **Augmentation deliberately excludes blur and JPEG noise.** Those are the
   cues that separate printed fakes from intaglio print.
4. **Threshold chosen so ≤ 2% of genuine notes get flagged.** A false
   "counterfeit" alarm on a real note is harmful, so the threshold is set on
   genuine val notes first.
5. **Guided multi-step check** (idea from bkataru/fake-currency-identification,
   re-implemented because that repo is GPL-3.0). The app speaks each step,
   waits, then takes a full-resolution photo:
   - *Print* (normal light): patch model, `model.tflite` + `threshold.txt`.
   - *Backlight* (note against a window or lamp, Settings → "Watermark step"):
     whole-note model, `backlight.tflite` + `backlight_threshold.txt`.
   - *UV* (only if Settings → "I have a UV lamp"): `uv.tflite` + `uv_threshold.txt`.

   Train each with `train_authenticity.py --step print|backlight|uv`. A step
   only runs if its model file is present. Any failed step means "possible
   counterfeit". All steps scoring under 40% of their threshold means "no signs".
   Anything else is "uncertain, check by hand".
6. **Three-way verdict:** no signs / unclear, retake / possible counterfeit, plus
   spoken **manual checks** (watermark, thread, raised print) from
   `assets/security_features.json` for every currency, including those
   without a model.

## Data you need

| Currency | Genuine | Counterfeit | Status |
|---|---|---|---|
| UGX | Mendeley dataset | Mendeley dataset | Ready to train. Check how its fakes were made (printer type, paper). |
| INR, KES, EGP, USD | Your denomination data | **None public that I found** | Use manual checks only, or build a dataset (below) |

Building a counterfeit set legally: use **specimen notes**, or work with a
bank or police fraud unit that holds seized notes. Photocopying or printing
currency yourself is illegal in most countries (including Kenya, Uganda,
India, Egypt and the US), even for training data.

## How to tell whether it really works

* `train_authenticity.py --holdout-counterfeit <dir>`: test on fakes from a
  **different source** (printer or maker) than training. In-distribution
  accuracy on a single dataset is usually near 100% and means little. The
  model may just learn one printer's dot pattern, or the photo setup the
  counterfeit images were shot with.
* Check that genuine and fake photos were taken under the same conditions.
  Otherwise the model learns the photo conditions (camera, lighting,
  background) instead of the note. Crop to the note to reduce this.
* Field-test on worn, folded and dirty genuine notes. Wear looks like bad
  print, and these notes are the main source of false alarms.

## Roadmap to stronger detection

1. **Guided multi-shot checks** (no extra hardware): ask the user to tilt the
   note, and detect the colour change of colour-shifting ink and the security
   thread across frames. This needs region alignment (ORB + homography, the
   useful part of the `currency-recognition` repo) to find the feature on
   the note.
2. **Transmitted-light check:** hold the note against a lit screen or window.
   The watermark region should change brightness strongly between reflected
   and transmitted shots. A photocopy shows no hidden watermark.
3. **Serial-number OCR** (ML Kit / Tesseract): check the format for the
   currency, and flag the same serial seen twice in one session.
4. **UV accessory** (an inexpensive 365 nm LED clip): fluorescent fibres and
   the UV-reactive thread become visible to the camera. This is the most
   reliable route for a phone and would justify a dedicated "UV mode" model.
