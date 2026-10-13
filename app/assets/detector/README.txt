Put a COCO object detector here (used by "Objects" mode):
  model.tflite   EfficientDet-Lite0 int8 (recommended), or the SSD MobileNet detect.tflite
                 from the Blind-People-Smart-AID / Braillo repos (300x300, uint8)
  labels.txt     COCO label map, one per line. A leading "???" line is handled automatically.
Run tool/fetch_detector.ps1 to download EfficientDet-Lite0.
