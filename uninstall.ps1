# ccmon uninstaller — removes installed files, shortcuts, position state.

param([string]$InstallDir = "$env:LOCALAPPDATA\ccmon")

$ErrorActionPreference = 'SilentlyContinue'

$paths = @(
    "$env:USERPROFILE\Desktop\ccmon-overlay.lnk"
    "$env:USERPROFILE\Desktop\ccmon.lnk"
    (Join-Path ([Environment]::GetFolderPath('Startup')) 'ccmon-overlay.lnk')
    "$env:USERPROFILE\.ccmon-pos.txt"
    $InstallDir
)
foreach ($p in $paths) {
    if (Test-Path $p) {
        Remove-Item -Recurse -Force $p
        Write-Host "removed $p" -ForegroundColor DarkGray
    }
}
Write-Host "uninstalled." -ForegroundColor Green
