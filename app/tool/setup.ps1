# Generates the android/ and ios/ platform folders (lib/ and pubspec.yaml are
# left untouched) and applies the settings this app needs.
# Run from the app folder:  powershell -ExecutionPolicy Bypass -File tool\setup.ps1
$ErrorActionPreference = "Stop"
# Windows PowerShell 5.1 "Set-Content -Encoding utf8" writes a byte-order mark, which breaks
# Gradle Kotlin scripts (the plugins {} block is no longer recognised). Write BOM-less UTF-8.
function Write-Utf8NoBom($path, $text) { [IO.File]::WriteAllText((Resolve-Path $path), $text, (New-Object Text.UTF8Encoding $false)) }
Set-Location (Join-Path $PSScriptRoot "..")

flutter create --platforms=android,ios --org com.banknote --project-name banknote_identifier .
# flutter create adds a sample counter test that does not apply to this app.
if (Test-Path test\widget_test.dart) { Remove-Item test\widget_test.dart }

# tflite_flutter needs Android API 26+.
$gradle = @("android\app\build.gradle.kts", "android\app\build.gradle") | Where-Object { Test-Path $_ } | Select-Object -First 1
$g = Get-Content $gradle -Raw
$g = $g -replace 'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdk = 26'
Write-Utf8NoBom $gradle $g
Write-Host "minSdk set to 26 in $gradle"

# iOS camera permission text, which VoiceOver reads to the user.
$plist = "ios\Runner\Info.plist"
$p = Get-Content $plist -Raw
if ($p -notmatch "NSCameraUsageDescription") {
  $entry = "`t<key>NSCameraUsageDescription</key>`n`t<string>The camera is used to identify banknotes and describe objects in front of you. Images never leave your phone.</string>`n</dict>`n</plist>"
  $p = $p -replace "</dict>\s*</plist>\s*$", $entry
  Write-Utf8NoBom $plist $p
  Write-Host "Added NSCameraUsageDescription"
}

flutter pub get
Write-Host "Done. Connect a phone and run: flutter run --release"
