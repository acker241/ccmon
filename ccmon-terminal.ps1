# ccmon-terminal — compact terminal monitor (% limits + ETA, USD-based)
# Alternative to overlay: runs in cmd/Windows Terminal, pin to taskbar.

$ErrorActionPreference = 'SilentlyContinue'
$host.UI.RawUI.WindowTitle = 'ccmon'

try {
    $buf = $host.UI.RawUI.BufferSize
    $buf.Width = 48; $buf.Height = 200
    $host.UI.RawUI.BufferSize = $buf
    $win = $host.UI.RawUI.WindowSize
    $win.Width = 48; $win.Height = 13
    $host.UI.RawUI.WindowSize = $win
} catch {}

function Format-Duration($mins) {
    if ($mins -lt 0 -or [double]::IsInfinity($mins) -or [double]::IsNaN($mins)) { return '--' }
    $h = [math]::Floor($mins / 60)
    $m = [math]::Floor($mins % 60)
    if ($h -gt 99) { return "99h+" }
    if ($h -gt 0) { return "${h}h${m}m" }
    return "${m}m"
}

function Write-Bar($label, $used, $limit) {
    $pct = if ($limit -gt 0) { [math]::Min(999, [math]::Round(100 * $used / $limit)) } else { 0 }
    $w = 12
    $clamped = [math]::Min(100, [math]::Max(0, $pct))
    $filled = [math]::Floor($w * $clamped / 100)
    $bar = ('#' * $filled) + ('.' * ($w - $filled))
    $color = if ($pct -ge 80) { 'Red' } elseif ($pct -ge 50) { 'Yellow' } else { 'Green' }
    Write-Host ("  {0,-7} " -f $label) -NoNewline -ForegroundColor DarkGray
    Write-Host $bar -NoNewline -ForegroundColor $color
    Write-Host (' {0,3}%' -f $pct) -ForegroundColor White
}

function Get-WindowTokens($minutes) {
    $cutoff = (Get-Date).ToUniversalTime().AddMinutes(-$minutes)
    $sum = 0L
    $files = Get-ChildItem "$env:USERPROFILE\.claude\projects\*\*.jsonl" -ErrorAction SilentlyContinue |
             Where-Object { $_.LastWriteTimeUtc -ge $cutoff.AddMinutes(-5) }
    $ts = [DateTime]::MinValue
    foreach ($f in $files) {
        try { $lines = [System.IO.File]::ReadAllLines($f.FullName) } catch { continue }
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $obj = $null
            try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if (-not $obj.timestamp -or -not $obj.message.usage) { continue }
            if (-not [DateTime]::TryParse([string]$obj.timestamp,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::AssumeUniversal -bor
                    [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$ts)) { continue }
            if ($ts -lt $cutoff) { continue }
            $u = $obj.message.usage
            $sum += ([long]($u.input_tokens) + [long]($u.output_tokens) +
                     [long]($u.cache_creation_input_tokens) + [long]($u.cache_read_input_tokens))
        }
    }
    return $sum
}

while ($true) {
    try {
        $blocksRaw = & npx -y ccusage@latest blocks --json 2>$null
        $dailyRaw  = & npx -y ccusage@latest daily --json 2>$null
        $weeklyRaw = & npx -y ccusage@latest weekly --json 2>$null

        $blocks = ($blocksRaw | ConvertFrom-Json).blocks
        $daily  = ($dailyRaw  | ConvertFrom-Json).daily
        $weekly = ($weeklyRaw | ConvertFrom-Json).weekly

        $active = $blocks | Where-Object { $_.isActive -eq $true } | Select-Object -First 1
        $today  = $daily  | Sort-Object period | Select-Object -Last 1
        $thisWk = $weekly | Sort-Object period | Select-Object -Last 1

        $sessHist   = @($blocks | Where-Object { -not $_.isActive -and -not $_.isGap })
        $dailyHist  = @($daily  | Where-Object { -not $today  -or $_.period -ne $today.period })
        $weeklyHist = @($weekly | Where-Object { -not $thisWk -or $_.period -ne $thisWk.period })

        $sessLim = if ($env:CCMON_SESSION_LIMIT) { [double]$env:CCMON_SESSION_LIMIT }
            elseif ($sessHist.Count -gt 0)   { [double]($sessHist   | Measure-Object -Property costUSD   -Maximum).Maximum }
            elseif ($active)                 { [math]::Max(0.01, [double]$active.costUSD) } else { 0.01 }
        $dailyLim = if ($env:CCMON_DAILY_LIMIT) { [double]$env:CCMON_DAILY_LIMIT }
            elseif ($dailyHist.Count -gt 0)  { [double]($dailyHist  | Measure-Object -Property totalCost -Maximum).Maximum }
            elseif ($today)                  { [math]::Max(0.01, [double]$today.totalCost) } else { 0.01 }
        $weeklyLim = if ($env:CCMON_WEEKLY_LIMIT) { [double]$env:CCMON_WEEKLY_LIMIT }
            elseif ($weeklyHist.Count -gt 0) { [double]($weeklyHist | Measure-Object -Property totalCost -Maximum).Maximum }
            elseif ($thisWk)                 { [math]::Max(0.01, [double]$thisWk.totalCost) } else { 0.01 }

        $sessCost   = if ($active) { [double]$active.costUSD } else { 0 }
        $dailyCost  = if ($today)  { [double]$today.totalCost }  else { 0 }
        $weeklyCost = if ($thisWk) { [double]$thisWk.totalCost } else { 0 }
        $resetLeft  = if ($active) { Format-Duration $active.projection.remainingMinutes } else { '--' }

        $rateAvgPerMin = if ($active) { [double]$active.burnRate.costPerHour / 60 } else { 0 }
        $costPerTok    = if ($active -and $active.totalTokens -gt 0) {
                            [double]$active.costUSD / [double]$active.totalTokens
                         } else { 0 }
        $tok30 = Get-WindowTokens 30
        $tok60 = Get-WindowTokens 60
        $rate30 = if ($costPerTok -gt 0) { ($tok30 * $costPerTok) / 30 } else { 0 }
        $rate60 = if ($costPerTok -gt 0) { ($tok60 * $costPerTok) / 60 } else { 0 }

        $remCost = [math]::Max(0, $sessLim - $sessCost)
        $etaAvg = if ($rateAvgPerMin -gt 0) { $remCost / $rateAvgPerMin } else { -1 }
        $eta30  = if ($rate30 -gt 0)        { $remCost / $rate30        } else { -1 }
        $eta60  = if ($rate60 -gt 0)        { $remCost / $rate60        } else { -1 }

        Clear-Host
        Write-Host "ccmon  " -NoNewline -ForegroundColor DarkGray
        Write-Host (Get-Date).ToString('HH:mm:ss') -ForegroundColor DarkCyan
        Write-Host ""
        Write-Bar 'session' $sessCost   $sessLim
        Write-Bar 'daily'   $dailyCost  $dailyLim
        Write-Bar 'weekly'  $weeklyCost $weeklyLim
        Write-Host ""
        Write-Host "  reset   " -NoNewline -ForegroundColor DarkGray
        Write-Host $resetLeft -ForegroundColor Yellow
        Write-Host "  ETA  " -NoNewline -ForegroundColor DarkGray
        Write-Host "avg " -NoNewline -ForegroundColor DarkGray
        Write-Host ('{0,-6}' -f (Format-Duration $etaAvg)) -NoNewline -ForegroundColor White
        Write-Host "30m " -NoNewline -ForegroundColor DarkGray
        Write-Host ('{0,-6}' -f (Format-Duration $eta30)) -NoNewline -ForegroundColor White
        Write-Host "1h " -NoNewline -ForegroundColor DarkGray
        Write-Host (Format-Duration $eta60) -ForegroundColor White
    } catch {
        Clear-Host
        Write-Host "ccmon error: $_" -ForegroundColor Red
    }

    Start-Sleep -Seconds 30
}
