# Downloads EfficientDet-Lite0 (COCO, int8, about 4.6 MB, Apache-2.0) for Objects mode,
# then extracts the label file embedded in the model's metadata.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$dst = Join-Path $PSScriptRoot "..\assets\detector"
$model = Join-Path $dst "model.tflite"
Invoke-WebRequest "https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/int8/latest/efficientdet_lite0.tflite" -OutFile $model
$zip = [System.IO.Compression.ZipFile]::OpenRead($model)
try {
  [System.IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry("labels.txt"), (Join-Path $dst "labels.txt"), $true)
} finally { $zip.Dispose() }
Write-Host "Saved model.tflite and labels.txt to $dst"
