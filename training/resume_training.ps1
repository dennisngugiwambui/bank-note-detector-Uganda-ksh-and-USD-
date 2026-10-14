# Continues training the NoteLens money model where it stopped.
# Safe to run any time: if training already finished, it only re-exports.
#
#   Right-click > Run with PowerShell, or from this folder:  .\resume_training.ps1
#
# Progress is saved after every epoch in runs\v2\state.json, so turning the
# laptop off loses at most the epoch that was running.

Set-Location $PSScriptRoot
$env:PYTHONIOENCODING = "utf8"
$env:TF_CPP_MIN_LOG_LEVEL = "2"
$py = ".\.venv\Scripts\python.exe"

& $py train_classifier.py --data data/v2 --out runs/v2 --epochs-head 5 --epochs-ft 12 --batch 32 2>&1 |
    Tee-Object -FilePath train_v2.log -Append
if ($LASTEXITCODE -ne 0) { Write-Host "Training stopped with an error. Run this script again to resume."; exit 1 }

# Export into the app and measure accuracy on held-out photos.
& $py export_tflite.py --run runs/v2 --data data/v2 --android-assets ../app/assets/currency
& $py evaluate_tflite.py --model runs/v2/model_int8.tflite --data data/v2
Write-Host "Done. Rebuild the app: cd ..\app; flutter build apk --release --split-per-abi"
