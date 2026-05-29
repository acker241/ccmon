# ccmon-overlay — desktop overlay (borderless, topmost, draggable)
# Async fetch via RunSpace so UI never blocks.
# Metric switchable via right-click: USD (cost) / Tokens / Percentage (auto-calibrated).
# Auto-checks GitHub for updates on startup.
# Repo: https://github.com/acker241/ccmon

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$posFile    = "$env:USERPROFILE\.ccmon-pos.txt"
$configFile = "$env:USERPROFILE\.ccmon-config.json"
$repoOwner  = 'acker241'
$repoName   = 'ccmon'
$repoUrl    = "https://github.com/$repoOwner/$repoName"

# ---------- config ----------

$script:config = @{
    metric      = 'usd'   # 'usd' | 'tokens' | 'pct'
    lastSeenSha = $null
}

function Load-Config {
    if (Test-Path $configFile) {
        try {
            $j = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($j.metric)      { $script:config.metric      = [string]$j.metric }
            if ($j.lastSeenSha) { $script:config.lastSeenSha = [string]$j.lastSeenSha }
        } catch {}
    }
}
function Save-Config {
    try {
        $script:config | ConvertTo-Json | Set-Content $configFile -Encoding UTF8
    } catch {}
}

Load-Config

# ---------- XAML ----------

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ccmon" SizeToContent="WidthAndHeight"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ResizeMode="NoResize" ShowInTaskbar="False">
  <Border CornerRadius="6" Background="#E61E1E1E" BorderBrush="#3A3A3A" BorderThickness="1" Padding="10,8,10,8">
    <StackPanel>
      <DockPanel LastChildFill="True" Margin="0,0,0,4">
        <TextBlock x:Name="tClock" Foreground="#5DADE2" FontFamily="Consolas" FontSize="11" DockPanel.Dock="Left"/>
        <TextBlock x:Name="tStatus" Foreground="#666" FontFamily="Consolas" FontSize="11" HorizontalAlignment="Right" Text="ccmon"/>
      </DockPanel>

      <Grid Margin="0,2,0,2">
        <Grid.RowDefinitions>
          <RowDefinition/><RowDefinition/><RowDefinition/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="56"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="46"/>
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="session" Foreground="#888" FontFamily="Consolas" FontSize="11"/>
        <TextBlock x:Name="sBar" Grid.Row="0" Grid.Column="1" FontFamily="Consolas" FontSize="11"/>
        <TextBlock x:Name="sPct" Grid.Row="0" Grid.Column="2" Foreground="White" FontFamily="Consolas" FontSize="11" HorizontalAlignment="Right"/>

        <TextBlock Grid.Row="1" Grid.Column="0" Text="daily"   Foreground="#888" FontFamily="Consolas" FontSize="11"/>
        <TextBlock x:Name="dBar" Grid.Row="1" Grid.Column="1" FontFamily="Consolas" FontSize="11"/>
        <TextBlock x:Name="dPct" Grid.Row="1" Grid.Column="2" Foreground="White" FontFamily="Consolas" FontSize="11" HorizontalAlignment="Right"/>

        <TextBlock Grid.Row="2" Grid.Column="0" Text="weekly"  Foreground="#888" FontFamily="Consolas" FontSize="11"/>
        <TextBlock x:Name="wBar" Grid.Row="2" Grid.Column="1" FontFamily="Consolas" FontSize="11"/>
        <TextBlock x:Name="wPct" Grid.Row="2" Grid.Column="2" Foreground="White" FontFamily="Consolas" FontSize="11" HorizontalAlignment="Right"/>
      </Grid>

      <TextBlock x:Name="tReset" Margin="0,4,0,0" Foreground="#FFD93D" FontFamily="Consolas" FontSize="11"/>
      <TextBlock x:Name="tEta"   Foreground="#CCC"   FontFamily="Consolas" FontSize="11"/>
    </StackPanel>
  </Border>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$tClock  = $window.FindName('tClock')
$tStatus = $window.FindName('tStatus')
$sBar = $window.FindName('sBar'); $sPct = $window.FindName('sPct')
$dBar = $window.FindName('dBar'); $dPct = $window.FindName('dPct')
$wBar = $window.FindName('wBar'); $wPct = $window.FindName('wPct')
$tReset = $window.FindName('tReset')
$tEta = $window.FindName('tEta')

# ---------- context menu ----------

$miMetricUsd = New-Object System.Windows.Controls.MenuItem
$miMetricUsd.Header = 'USD (cost)';        $miMetricUsd.IsCheckable = $true
$miMetricTok = New-Object System.Windows.Controls.MenuItem
$miMetricTok.Header = 'Tokens (raw)';      $miMetricTok.IsCheckable = $true
$miMetricPct = New-Object System.Windows.Controls.MenuItem
$miMetricPct.Header = 'Percentage (auto)'; $miMetricPct.IsCheckable = $true

$miMetric = New-Object System.Windows.Controls.MenuItem
$miMetric.Header = 'Metric'
[void]$miMetric.Items.Add($miMetricUsd)
[void]$miMetric.Items.Add($miMetricTok)
[void]$miMetric.Items.Add($miMetricPct)

$miUpdate = New-Object System.Windows.Controls.MenuItem
$miUpdate.Header = 'Check for updates'

$miOpenRepo = New-Object System.Windows.Controls.MenuItem
$miOpenRepo.Header = 'Open GitHub repo'

$miClose = New-Object System.Windows.Controls.MenuItem
$miClose.Header = 'Close'

$menu = New-Object System.Windows.Controls.ContextMenu
[void]$menu.Items.Add($miMetric)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$menu.Items.Add($miUpdate)
[void]$menu.Items.Add($miOpenRepo)
[void]$menu.Items.Add((New-Object System.Windows.Controls.Separator))
[void]$menu.Items.Add($miClose)
$window.ContextMenu = $menu

function Sync-MetricChecks {
    $miMetricUsd.IsChecked = ($script:config.metric -eq 'usd')
    $miMetricTok.IsChecked = ($script:config.metric -eq 'tokens')
    $miMetricPct.IsChecked = ($script:config.metric -eq 'pct')
}
Sync-MetricChecks

# ---------- window behavior ----------

$window.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })
$window.Add_KeyDown({ if ($_.Key -eq 'Escape') { $window.Close() } })

if (Test-Path $posFile) {
    try {
        $p = Get-Content $posFile | ConvertFrom-Json
        $window.Left = [double]$p.Left
        $window.Top  = [double]$p.Top
        $window.WindowStartupLocation = 'Manual'
    } catch {}
} else {
    $window.WindowStartupLocation = 'CenterScreen'
}

$window.Add_Closing({
    try {
        @{ Left = $window.Left; Top = $window.Top } | ConvertTo-Json | Set-Content $posFile
    } catch {}
})

# ---------- worker: fetch usage data ----------

$workerScript = {
    param($userprofile, $metric, $sessLimEnv, $dailyLimEnv, $weeklyLimEnv)

    function Format-Duration($mins) {
        if ($mins -lt 0 -or [double]::IsInfinity($mins) -or [double]::IsNaN($mins)) { return '--' }
        $h = [math]::Floor($mins / 60); $m = [math]::Floor($mins % 60)
        if ($h -gt 99) { return "99h+" }
        if ($h -gt 0) { return "${h}h${m}m" }
        return "${m}m"
    }
    function Get-WindowTokens($minutes) {
        $cutoff = (Get-Date).ToUniversalTime().AddMinutes(-$minutes)
        $sum = 0L
        $files = Get-ChildItem "$userprofile\.claude\projects\*\*.jsonl" -ErrorAction SilentlyContinue |
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

    $blocksRaw = & npx -y ccusage@latest blocks --json 2>$null
    $dailyRaw  = & npx -y ccusage@latest daily --json 2>$null
    $weeklyRaw = & npx -y ccusage@latest weekly --json 2>$null

    $blocks = ($blocksRaw | ConvertFrom-Json).blocks
    $daily  = ($dailyRaw  | ConvertFrom-Json).daily
    $weekly = ($weeklyRaw | ConvertFrom-Json).weekly

    $active = $blocks | Where-Object { $_.isActive -eq $true } | Select-Object -First 1
    $today  = $daily  | Sort-Object period | Select-Object -Last 1
    $thisWk = $weekly | Sort-Object period | Select-Object -Last 1

    # Property pick based on metric.
    $sessProp = if ($metric -eq 'tokens') { 'totalTokens' } else { 'costUSD' }
    $dayProp  = if ($metric -eq 'tokens') { 'totalTokens' } else { 'totalCost' }
    $wkProp   = if ($metric -eq 'tokens') { 'totalTokens' } else { 'totalCost' }

    $sessHist   = @($blocks | Where-Object { -not $_.isActive -and -not $_.isGap })
    $dailyHist  = @($daily  | Where-Object { -not $today  -or $_.period -ne $today.period })
    $weeklyHist = @($weekly | Where-Object { -not $thisWk -or $_.period -ne $thisWk.period })

    # 'pct' mode ignores env vars and forces auto-calibration (previous personal max).
    $useEnv = ($metric -ne 'pct')

    $sessLim = if ($useEnv -and $sessLimEnv) { [double]$sessLimEnv }
        elseif ($sessHist.Count -gt 0)   { [double]($sessHist   | Measure-Object -Property $sessProp -Maximum).Maximum }
        elseif ($active)                 { [math]::Max(0.01, [double]$active.$sessProp) } else { 0.01 }
    $dailyLim = if ($useEnv -and $dailyLimEnv) { [double]$dailyLimEnv }
        elseif ($dailyHist.Count -gt 0)  { [double]($dailyHist  | Measure-Object -Property $dayProp -Maximum).Maximum }
        elseif ($today)                  { [math]::Max(0.01, [double]$today.$dayProp) } else { 0.01 }
    $weeklyLim = if ($useEnv -and $weeklyLimEnv) { [double]$weeklyLimEnv }
        elseif ($weeklyHist.Count -gt 0) { [double]($weeklyHist | Measure-Object -Property $wkProp -Maximum).Maximum }
        elseif ($thisWk)                 { [math]::Max(0.01, [double]$thisWk.$wkProp) } else { 0.01 }

    $sessCur = if ($active) { [double]$active.$sessProp } else { 0 }
    $dayCur  = if ($today)  { [double]$today.$dayProp }  else { 0 }
    $wkCur   = if ($thisWk) { [double]$thisWk.$wkProp }  else { 0 }

    $sessPct   = if ($sessLim   -gt 0) { [math]::Min(999, [math]::Round(100 * $sessCur / $sessLim))   } else { 0 }
    $dailyPct  = if ($dailyLim  -gt 0) { [math]::Min(999, [math]::Round(100 * $dayCur  / $dailyLim))  } else { 0 }
    $weeklyPct = if ($weeklyLim -gt 0) { [math]::Min(999, [math]::Round(100 * $wkCur   / $weeklyLim)) } else { 0 }

    # ETA: rate in active metric per minute.
    $costPerTok = if ($active -and $active.totalTokens -gt 0) {
                    [double]$active.costUSD / [double]$active.totalTokens
                  } else { 0 }
    $rateAvgPerMin = if ($active) {
        if ($metric -eq 'tokens') { [double]$active.burnRate.tokensPerMinute }
        else                      { [double]$active.burnRate.costPerHour / 60 }
    } else { 0 }

    $tok30 = Get-WindowTokens 30
    $tok60 = Get-WindowTokens 60
    if ($metric -eq 'tokens') {
        $rate30 = $tok30 / 30
        $rate60 = $tok60 / 60
    } else {
        $rate30 = if ($costPerTok -gt 0) { ($tok30 * $costPerTok) / 30 } else { 0 }
        $rate60 = if ($costPerTok -gt 0) { ($tok60 * $costPerTok) / 60 } else { 0 }
    }

    $remVal = [math]::Max(0, $sessLim - $sessCur)
    $etaAvg = if ($rateAvgPerMin -gt 0) { $remVal / $rateAvgPerMin } else { -1 }
    $eta30  = if ($rate30 -gt 0)        { $remVal / $rate30        } else { -1 }
    $eta60  = if ($rate60 -gt 0)        { $remVal / $rate60        } else { -1 }

    $resetLeft = if ($active) { Format-Duration $active.projection.remainingMinutes } else { '--' }

    return @{
        clock     = (Get-Date).ToString('HH:mm:ss')
        sessPct   = $sessPct
        dailyPct  = $dailyPct
        weeklyPct = $weeklyPct
        reset     = "reset  $resetLeft"
        eta       = ("ETA  avg {0}  30m {1}  1h {2}" -f (Format-Duration $etaAvg), (Format-Duration $eta30), (Format-Duration $eta60))
        metric    = $metric
    }
}

# ---------- worker: update check ----------

$updateScript = {
    param($owner, $repo)
    try {
        $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/commits/master" `
                -Headers @{ 'User-Agent' = 'ccmon' } -TimeoutSec 5
        return @{ sha = [string]$resp.sha }
    } catch {
        return @{ sha = $null; error = "$_" }
    }
}

# ---------- dispatcher state ----------

$script:fetchPS = $null;   $script:fetchHandle = $null
$script:updatePS = $null;  $script:updateHandle = $null
$script:updateAvailable = $false

function Get-BarString($pct) {
    $w = 12
    $clamped = [math]::Min(100, [math]::Max(0, $pct))
    $filled = [math]::Floor($w * $clamped / 100)
    return (('#' * $filled) + ('.' * ($w - $filled)))
}
function Get-PctColor($pct) {
    if ($pct -ge 80) { return '#FF6B6B' }
    if ($pct -ge 50) { return '#FFD93D' }
    return '#6BCB77'
}

function Get-StatusText {
    $base = 'ccmon'
    if ($script:updateAvailable) { return "$base ↑" }
    return $base
}
function Get-StatusColor {
    if ($script:updateAvailable) { return '#FFD93D' }
    return '#666'
}

function Start-AsyncFetch {
    if ($script:fetchPS) { return }
    $script:fetchPS = [PowerShell]::Create()
    $null = $script:fetchPS.AddScript($workerScript).
        AddArgument($env:USERPROFILE).
        AddArgument($script:config.metric).
        AddArgument($env:CCMON_SESSION_LIMIT).
        AddArgument($env:CCMON_DAILY_LIMIT).
        AddArgument($env:CCMON_WEEKLY_LIMIT)
    $script:fetchHandle = $script:fetchPS.BeginInvoke()
    $tStatus.Text = '...'
    $tStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#666')
}

function Start-UpdateCheck {
    if ($script:updatePS) { return }
    $script:updatePS = [PowerShell]::Create()
    $null = $script:updatePS.AddScript($updateScript).AddArgument($repoOwner).AddArgument($repoName)
    $script:updateHandle = $script:updatePS.BeginInvoke()
}

function Apply-Result($r) {
    $tClock.Text = $r.clock
    $tStatus.Text = (Get-StatusText)
    $tStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom((Get-StatusColor))

    $sBar.Text = Get-BarString $r.sessPct
    $sBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom((Get-PctColor $r.sessPct))
    $sPct.Text = "$($r.sessPct)%"

    $dBar.Text = Get-BarString $r.dailyPct
    $dBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom((Get-PctColor $r.dailyPct))
    $dPct.Text = "$($r.dailyPct)%"

    $wBar.Text = Get-BarString $r.weeklyPct
    $wBar.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom((Get-PctColor $r.weeklyPct))
    $wPct.Text = "$($r.weeklyPct)%"

    $tReset.Text = $r.reset
    $tEta.Text   = $r.eta
}

# ---------- menu handlers ----------

function Set-Metric($m) {
    $script:config.metric = $m
    Save-Config
    Sync-MetricChecks
    Start-AsyncFetch
}
$miMetricUsd.Add_Click({ Set-Metric 'usd' })
$miMetricTok.Add_Click({ Set-Metric 'tokens' })
$miMetricPct.Add_Click({ Set-Metric 'pct' })

$miUpdate.Add_Click({
    $script:updateAvailable = $false
    $tStatus.Text = 'check...'
    Start-UpdateCheck
})
$miOpenRepo.Add_Click({ Start-Process $repoUrl })
$miClose.Add_Click({ $window.Close() })

# ---------- timers ----------

$pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$pollTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$pollTimer.Add_Tick({
    if ($script:fetchHandle -and $script:fetchHandle.IsCompleted) {
        try {
            $out = $script:fetchPS.EndInvoke($script:fetchHandle)
            if ($out -and $out.Count -gt 0) {
                $r = $out[0]
                if ($r -is [hashtable]) { Apply-Result $r }
            }
        } catch {
            $tStatus.Text = 'err'
            $tStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#FF6B6B')
        } finally {
            $script:fetchPS.Dispose()
            $script:fetchPS = $null
            $script:fetchHandle = $null
        }
    }
    if ($script:updateHandle -and $script:updateHandle.IsCompleted) {
        try {
            $out = $script:updatePS.EndInvoke($script:updateHandle)
            if ($out -and $out.Count -gt 0) {
                $r = $out[0]
                if ($r -is [hashtable] -and $r.sha) {
                    $prev = $script:config.lastSeenSha
                    $script:config.lastSeenSha = $r.sha
                    Save-Config
                    $script:updateAvailable = ($prev -and $prev -ne $r.sha)
                    $tStatus.Text = (Get-StatusText)
                    $tStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom((Get-StatusColor))
                }
            }
        } catch {} finally {
            $script:updatePS.Dispose()
            $script:updatePS = $null
            $script:updateHandle = $null
        }
    }
})
$pollTimer.Start()

$refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$refreshTimer.Interval = [TimeSpan]::FromSeconds(30)
$refreshTimer.Add_Tick({ Start-AsyncFetch })
$refreshTimer.Start()

$window.Add_Loaded({
    Start-AsyncFetch
    Start-UpdateCheck
})

[void]$window.ShowDialog()
