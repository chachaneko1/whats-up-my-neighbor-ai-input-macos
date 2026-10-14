param([string]$Version = '0.1.0-beta.1')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = "$root/dist"
$app = "$output/app"
New-Item -ItemType Directory -Force $app | Out-Null
Get-ChildItem $app -File | Remove-Item
$build = "$root/Neighbor.Windows/bin/Release/net48"
# Explicit payload: CLR/Windows SDK contract metadata, test code and symbols are not runtime payload.
Get-ChildItem $build -File | Where-Object { $_.Extension -in '.exe', '.dll', '.config' } | Copy-Item -Destination $app
Copy-Item "$root/使用說明.txt", "$root/THIRD-PARTY-NOTICES.txt", "$root/../LICENSE" $app
$forbidden = Get-ChildItem $app -File | Where-Object { $_.Name -match 'Tests|\.pdb$|\.winmd$|\.wav$|\.m4a$|whisper|ffmpeg|python|torch' }
if ($forbidden) { throw 'Unexpected files in installer payload' }
$compiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
if (!(Test-Path $compiler)) { $compiler = (Get-Command ISCC.exe -ErrorAction Stop).Source }
& $compiler "/DAppVersion=$Version" "$root/packaging/neighbor.iss"
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
$installer = Get-Item "$output/Neighbor-Setup-$Version-x64.exe"
if ($installer.Length -gt 20000000) { throw "Installer exceeds 20 MB: $($installer.Length) bytes" }
$hash = (Get-FileHash $installer.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $($installer.Name)" | Set-Content "$($installer.FullName).sha256" -Encoding ascii
$sourceCommit = (git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit' }
$signature = (Get-AuthenticodeSignature $installer.FullName).Status.ToString()
$manifest = [ordered]@{ sourceCommit=$sourceCommit; workflowRun=$env:GITHUB_RUN_ID; signatureStatus=$signature; version=$Version; installer=$installer.Name; bytes=$installer.Length; sha256=$hash; signed=($signature -eq 'Valid'); target='Windows 11 x64; Windows 10 22H2 x64'; files=@(Get-ChildItem $app -File | ForEach-Object { @{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()} }) }
$manifest | ConvertTo-Json -Depth 5 | Set-Content "$output/build-manifest.json" -Encoding utf8
Write-Output "Installer size: $($installer.Length) bytes; SHA-256: $hash"
