param([string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
dotnet restore "$root/Neighbor.Tests/Neighbor.Tests.csproj" --locked-mode
if ($LASTEXITCODE -ne 0) { throw 'Dependency restore failed' }
dotnet build "$root/Neighbor.Tests/Neighbor.Tests.csproj" -c $Configuration --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
& "$root/Neighbor.Tests/bin/$Configuration/net48/Neighbor.Tests.exe"
if ($LASTEXITCODE -ne 0) { throw 'Windows tests failed' }
