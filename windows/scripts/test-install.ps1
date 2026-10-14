param([string]$Version = '0.1.0-beta.1')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$installer = "$root/dist/Neighbor-Setup-$Version-x64.exe"
$target = Join-Path $env:LOCALAPPDATA 'Programs/WhatsUpMyNeighbor-CI'
function Invoke-Checked([string]$File,[string]$Arguments) {
    $p = Start-Process -FilePath $File -ArgumentList $Arguments -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "$File failed with exit code $($p.ExitCode)" }
}
try {
    Invoke-Checked $installer "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"$target`" /LOG=`"$root/dist/install.log`""
    if (!(Test-Path "$target/Neighbor.exe")) { throw 'Installed executable missing' }
    $sentinel = Join-Path $env:LOCALAPPDATA 'WhatsUpMyNeighbor/upgrade-test.txt'
    New-Item -ItemType Directory -Force (Split-Path $sentinel) | Out-Null
    'upgrade-preserves-user-data' | Set-Content $sentinel
    $process = Start-Process "$target/Neighbor.exe" '--smoke-test' -PassThru
    if (!$process.WaitForExit(20000)) { $process.Kill(); throw 'App smoke test timed out' }
    if ($process.ExitCode -ne 0) { throw 'App launch smoke failed' }
    Invoke-Checked $installer "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"$target`""
    if ((Get-Content $sentinel) -ne 'upgrade-preserves-user-data') { throw 'Upgrade removed user data' }
    Invoke-Checked "$target/unins000.exe" '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
    if (Test-Path "$target/Neighbor.exe") { throw 'Uninstall left executable' }
    if (!(Test-Path $sentinel)) { throw 'Uninstall unexpectedly removed user data' }
    'PASS install, launch, upgrade/reinstall, uninstall, user-data preservation' | Set-Content "$root/dist/install-tests.txt"
} finally {
    if (Test-Path "$target/unins000.exe") { Invoke-Checked "$target/unins000.exe" '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
}
