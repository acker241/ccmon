# ccmon-terminal — compact terminal monitor (% limits + ETA)
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

function Format-Tokens($n) {
    if ($n -ge 1e9) { return ('{0:N2}B' -f ($n/1e9)) }
    if ($n -ge 1e6) { return ('{0:N1}M' -f ($n/1e6)) }
    if ($n -ge 1e3) { return ('{0:N1}k' -f ($n/1e3)) }
    return "$n"
}

function Format-Duration($mins) {
    if ($mins -lt 0 -or [double]::IsInfinity($mins) -or [double]::IsNaN($mins)) { return '--' }
    $h = [math]::Floor($mins / 60)
    $m = [math]::Floor($mins % 60)
    if ($h -gt 99) { return "99h+" }
    if ($h -gt 0) { return "${h}h${m}m" }
    return "${m}m"
}

function Write-Bar($label, $used, $limit) {
    $pct = if ($limit -gt 0) { [math]::Min(100, [math]::Round(100 * $used / $limit)) } else { 0 }
    $w = 12
    $filled = [math]::Floor($w * $pct / 100)
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

        $sessLim = if ($env:CCMON_SESSION_LIMIT) { [long]$env:CCMON_SESSION_LIMIT } else {
            ($blocks | Where-Object { -not $_.isGap } | Measure-Object -Property totalTokens -Maximum).Maximum
        }
        $dailyLim = if ($env:CCMON_DAILY_LIMIT) { [long]$env:CCMON_DAILY_LIMIT } else {
            ($daily | Measure-Object -Property totalTokens -Maximum).Maximum
        }
        $weeklyLim = if ($env:CCMON_WEEKLY_LIMIT) { [long]$env:CCMON_WEEKLY_LIMIT } else {
            ($weekly | Measure-Object -Property totalTokens -Maximum).Maximum
        }

        $sessUsed   = if ($active) { $active.totalTokens } else { 0 }
        $dailyUsed  = if ($today)  { $today.totalTokens }  else { 0 }
        $weeklyUsed = if ($thisWk) { $thisWk.totalTokens } else { 0 }
        $resetLeft  = if ($active) { Format-Duration $active.projection.remainingMinutes } else { '--' }

        $rateAvg = if ($active) { [double]$active.burnRate.tokensPerMinute } else { 0 }
        $tok30 = Get-WindowTokens 30
        $tok60 = Get-WindowTokens 60
        $rate30 = $tok30 / 30
        $rate60 = $tok60 / 60

        $remTok = [math]::Max(0, $sessLim - $sessUsed)
        $etaAvg = if ($rateAvg -gt 0) { $remTok / $rateAvg } else { -1 }
        $eta30  = if ($rate30  -gt 0) { $remTok / $rate30  } else { -1 }
        $eta60  = if ($rate60  -gt 0) { $remTok / $rate60  } else { -1 }

        Clear-Host
        Write-Host "ccmon  " -NoNewline -ForegroundColor DarkGray
        Write-Host (Get-Date).ToString('HH:mm:ss') -ForegroundColor DarkCyan
        Write-Host ""
        Write-Bar 'session' $sessUsed   $sessLim
        Write-Bar 'daily'   $dailyUsed  $dailyLim
        Write-Bar 'weekly'  $weeklyUsed $weeklyLim
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
