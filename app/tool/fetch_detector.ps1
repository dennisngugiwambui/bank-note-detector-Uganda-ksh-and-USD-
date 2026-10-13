# Downloads the two Objects-mode models (both Apache-2.0) and extracts the
# label files embedded in their metadata.
#
#   assets/detector  EfficientDet-Lite2, COCO 80 objects with positions, 448 px, 7.6 MB.
#                    MUST be a build with the TFLite_Detection_PostProcess op (4 outputs:
#                    boxes, classes, scores, count). The MediaPipe "object_detector"
#                    builds output 19206 raw anchors instead and ObjectDetector finds nothing.
#   assets/scene     EfficientNet-Lite0, ImageNet 1000 classes (shoes, clothes, windows...),
#                    224 px, 5.4 MB. Used for things COCO does not know.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$assets = Join-Path $PSScriptRoot "..\assets"

function Get-Model($url, $dir, $labelEntry) {
  $dst = Join-Path $assets $dir
  New-Item -ItemType Directory -Force $dst | Out-Null
  $model = Join-Path $dst "model.tflite"
  Invoke-WebRequest $url -OutFile $model
  $zip = [System.IO.Compression.ZipFile]::OpenRead($model)
  try {
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry($labelEntry), (Join-Path $dst "labels.txt"), $true)
  } finally { $zip.Dispose() }
  Write-Host "Saved model.tflite and labels.txt to $dst"
}

Get-Model "https://storage.googleapis.com/download.tensorflow.org/models/tflite/task_library/object_detection/android/lite-model_efficientdet_lite2_detection_metadata_1.tflite" "detector" "labelmap.txt"
Get-Model "https://storage.googleapis.com/mediapipe-models/image_classifier/efficientnet_lite0/int8/latest/efficientnet_lite0.tflite" "scene" "labels_without_background.txt"
