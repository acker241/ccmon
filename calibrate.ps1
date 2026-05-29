# ccmon calibrate — derives CCMON_*_LIMIT (in USD) from your Anthropic dashboard.
# Run when ccmon % drifts from the dashboard. With USD-based metric drift is
# minimal — calibrating once usually lasts months.

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

$sessCost = if ($b.blocks.Count -gt 0) { [double]$b.blocks[0].costUSD } else { 0 }
$dayCost  = if ($d.daily.Count -gt 0) { [double]($d.daily | Sort-Object period | Select-Object -Last 1).totalCost } else { 0 }
$wkCost   = if ($w.weekly.Count -gt 0) { [double]($w.weekly | Sort-Object period | Select-Object -Last 1).totalCost } else { 0 }

function ReadPct($label) {
    while ($true) {
        $raw = Read-Host "  $label % (number only, e.g. 14)"
        $clean = $raw -replace '%', '' -replace ',', '.'
        $parsed = 0.0
        if ([double]::TryParse($clean, [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            if ($parsed -gt 0 -and $parsed -le 100) { return $parsed }
        }
        Write-Host "    invalid. enter a number 1-100." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Current cost (USD):" -ForegroundColor DarkGray
Write-Host ("  session  `${0:N2}" -f $sessCost)
Write-Host ("  daily    `${0:N2}" -f $dayCost)
Write-Host ("  weekly   `${0:N2}" -f $wkCost)
Write-Host ""
Write-Host "Type the % each shows on the dashboard right now:" -ForegroundColor Yellow
$sessPct = ReadPct "Sessão atual"
$wkPct   = ReadPct "Limites semanais (Todos os modelos)"

$sessLim   = [math]::Round($sessCost / ($sessPct / 100), 2)
$weeklyLim = [math]::Round($wkCost   / ($wkPct   / 100), 2)
$dailyLim  = [math]::Round($weeklyLim / 7, 2)

[Environment]::SetEnvironmentVariable('CCMON_SESSION_LIMIT', "$sessLim",   'User')
[Environment]::SetEnvironmentVariable('CCMON_DAILY_LIMIT',   "$dailyLim",  'User')
[Environment]::SetEnvironmentVariable('CCMON_WEEKLY_LIMIT',  "$weeklyLim", 'User')

Write-Host ""
Write-Host "Derived limits (USD, set as User env vars):" -ForegroundColor Green
Write-Host ("  CCMON_SESSION_LIMIT = `${0}" -f $sessLim)
Write-Host ("  CCMON_DAILY_LIMIT   = `${0}  (= weekly / 7)" -f $dailyLim)
Write-Host ("  CCMON_WEEKLY_LIMIT  = `${0}" -f $weeklyLim)
Write-Host ""
Write-Host "Restart the overlay (ESC + double-click shortcut) to pick up new values." -ForegroundColor Cyan
