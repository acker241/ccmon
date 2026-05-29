# ccmon calibrate — derives CCMON_*_LIMIT from your Anthropic dashboard.
# Run when ccmon % drifts from the dashboard (recommended: monthly).
#
# How: open https://claude.ai/settings/usage, read the % shown for Sessão atual
# and Limites semanais, type them here. Script computes token limits and sets
# them as persistent user env vars. Restart the overlay after.

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "ccmon calibrate" -ForegroundColor Cyan
Write-Host "---------------" -ForegroundColor DarkGray
Write-Host "Open https://claude.ai/settings/usage in your browser."
Write-Host ""

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Host "npx not found. Install Node.js 18+ first." -ForegroundColor Red
    exit 1
}

Write-Host "Fetching current usage from ccusage..." -ForegroundColor DarkGray
$b = (& npx -y ccusage@latest blocks --active --json 2>$null) | ConvertFrom-Json
$d = (& npx -y ccusage@latest daily --json 2>$null) | ConvertFrom-Json
$w = (& npx -y ccusage@latest weekly --json 2>$null) | ConvertFrom-Json

$sessTok = if ($b.blocks.Count -gt 0) { [long]$b.blocks[0].totalTokens } else { 0 }
$dayTok  = if ($d.daily.Count -gt 0) { [long]($d.daily | Sort-Object period | Select-Object -Last 1).totalTokens } else { 0 }
$wkTok   = if ($w.weekly.Count -gt 0) { [long]($w.weekly | Sort-Object period | Select-Object -Last 1).totalTokens } else { 0 }

function ReadPct($label) {
    while ($true) {
        $raw = Read-Host "  $label % (number only, e.g. 14)"
        $clean = $raw -replace '%', '' -replace ',', '.'
        if ([double]::TryParse($clean, [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]([double]$null))) {
            $v = [double]$clean
            if ($v -gt 0 -and $v -le 100) { return $v }
        }
        Write-Host "    invalid. enter a number 1-100." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Current ccmon-metric tokens:" -ForegroundColor DarkGray
Write-Host ("  session  {0:N0}" -f $sessTok)
Write-Host ("  daily    {0:N0}" -f $dayTok)
Write-Host ("  weekly   {0:N0}" -f $wkTok)
Write-Host ""
Write-Host "Now type the % each shows on the dashboard right now:" -ForegroundColor Yellow
$sessPct = ReadPct "Sessão atual"
$wkPct   = ReadPct "Limites semanais (Todos os modelos)"

$sessLim   = [long][math]::Round($sessTok / ($sessPct / 100))
$weeklyLim = [long][math]::Round($wkTok   / ($wkPct   / 100))
$dailyLim  = [long][math]::Round($weeklyLim / 7)

[Environment]::SetEnvironmentVariable('CCMON_SESSION_LIMIT', "$sessLim",   'User')
[Environment]::SetEnvironmentVariable('CCMON_DAILY_LIMIT',   "$dailyLim",  'User')
[Environment]::SetEnvironmentVariable('CCMON_WEEKLY_LIMIT',  "$weeklyLim", 'User')

Write-Host ""
Write-Host "Derived limits (set as User env vars):" -ForegroundColor Green
Write-Host ("  CCMON_SESSION_LIMIT = {0:N0}" -f $sessLim)
Write-Host ("  CCMON_DAILY_LIMIT   = {0:N0}  (= weekly / 7)" -f $dailyLim)
Write-Host ("  CCMON_WEEKLY_LIMIT  = {0:N0}" -f $weeklyLim)
Write-Host ""
Write-Host "Restart the overlay (ESC + double-click shortcut) to pick up new values." -ForegroundColor Cyan
