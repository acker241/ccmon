# ccmon installer — copies scripts to %LOCALAPPDATA%\ccmon, creates Desktop shortcut.
# Run: powershell -ExecutionPolicy Bypass -File install.ps1
# Optional: -Startup to also add to Windows Startup folder.

param(
    [switch]$Startup,
    [string]$InstallDir = "$env:LOCALAPPDATA\ccmon"
)

$ErrorActionPreference = 'Stop'

# 1. Check Node.js
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "node not found in PATH. Install Node.js 18+ from https://nodejs.org" -ForegroundColor Red
    exit 1
}
Write-Host "node $(node --version) OK" -ForegroundColor Green

# 2. Copy files
$src = $PSScriptRoot
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$files = @('ccmon-overlay.ps1', 'ccmon-terminal.ps1', 'ccmon-overlay.vbs', 'uninstall.ps1', 'calibrate.ps1')
foreach ($f in $files) {
    $srcPath = Join-Path $src $f
    if (Test-Path $srcPath) {
        Copy-Item -Force $srcPath (Join-Path $InstallDir $f)
        Write-Host "  copied $f" -ForegroundColor DarkGray
    }
}
Write-Host "installed to $InstallDir" -ForegroundColor Green

# 3. Create Desktop shortcut (overlay, hidden console)
$ws = New-Object -ComObject WScript.Shell
$lnk = "$env:USERPROFILE\Desktop\ccmon-overlay.lnk"
$sc = $ws.CreateShortcut($lnk)
$sc.TargetPath = "wscript.exe"
$sc.Arguments = '"' + (Join-Path $InstallDir 'ccmon-overlay.vbs') + '"'
$sc.WorkingDirectory = $InstallDir
$sc.IconLocation = "powershell.exe,0"
$sc.WindowStyle = 7
$sc.Save()
Write-Host "shortcut: $lnk" -ForegroundColor Green

# 4. Optional: Startup folder
if ($Startup) {
    $startup = [Environment]::GetFolderPath('Startup')
    $startupLnk = Join-Path $startup 'ccmon-overlay.lnk'
    $sc2 = $ws.CreateShortcut($startupLnk)
    $sc2.TargetPath = "wscript.exe"
    $sc2.Arguments = '"' + (Join-Path $InstallDir 'ccmon-overlay.vbs') + '"'
    $sc2.WorkingDirectory = $InstallDir
    $sc2.IconLocation = "powershell.exe,0"
    $sc2.WindowStyle = 7
    $sc2.Save()
    Write-Host "startup shortcut: $startupLnk" -ForegroundColor Green
}

Write-Host ""
Write-Host "done. double-click Desktop\ccmon-overlay.lnk to launch." -ForegroundColor Cyan
Write-Host "first run downloads ccusage (~10s)." -ForegroundColor DarkGray
