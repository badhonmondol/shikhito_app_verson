param(
  [Parameter(Mandatory = $true)]
  [string]$Version,

  [string]$Message = "নতুন আপডেটে বাগ ফিক্স ও উন্নতি করা হয়েছে।"
)

$ErrorActionPreference = "Stop"

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
  throw "Version must look like 1.0.5"
}

$updateRepo = "badhonmondol/shikhito_app_verson"
$tag = "v$Version"
$buildNumber = [int]($Version -replace '\.', '')
$root = Split-Path -Parent $PSScriptRoot

Set-Location $root

# Update pubspec.yaml
$pubspecPath = Join-Path $root "pubspec.yaml"
$pubspec = Get-Content $pubspecPath -Raw
$pubspec = $pubspec -replace '(?m)^version:\s*.+$', "version: $Version+$buildNumber"
Set-Content -Path $pubspecPath -Value $pubspec -NoNewline -Encoding UTF8

# Update version.json
$versionJsonPath = Join-Path $root "version.json"
$updateInfo = [ordered]@{
  version = $Version
  apk_url = "https://github.com/$updateRepo/releases/download/$tag/app-release.apk"
  message = $Message
}
$updateInfo | ConvertTo-Json -Depth 3 | Set-Content -Path $versionJsonPath -Encoding UTF8

# Commit and push source to shikhito_app (private)
flutter pub get
git add pubspec.yaml pubspec.lock version.json
git commit -m "Release $tag"
git push

# Clone shikhito_app_verson (public) and copy full Flutter source into it
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "shikhito_app_verson"
if (Test-Path $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
git clone "https://github.com/$updateRepo.git" $tempDir

# Copy Flutter source files (exclude .git and build)
$exclude = @('.git', 'build', '.dart_tool')
Get-ChildItem -Path $root -Force | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
  $dest = Join-Path $tempDir $_.Name
  if ($_.PSIsContainer) {
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
  } else {
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
  }
}

Set-Location $tempDir
git add -A
git commit -m "Release $tag"
git tag $tag
git push origin main
git push origin $tag

Set-Location $root
Write-Host "Done! GitHub Actions at https://github.com/$updateRepo/actions will build APK and publish release $tag"
