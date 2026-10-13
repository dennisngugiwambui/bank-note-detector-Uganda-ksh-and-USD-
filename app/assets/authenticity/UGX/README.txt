Counterfeit screening model for Ugandan shillings:
  model.tflite, labels.txt, threshold.txt  <- training/train_authenticity.py --android-assets ../app/assets/authenticity/UGX
To add another currency: create assets/authenticity/<ISO>/, list it in pubspec.yaml, and drop the same three files in.
