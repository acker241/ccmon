# ccmon-overlay — desktop overlay (borderless, topmost, draggable)
# Async fetch via RunSpace so UI never blocks.
# Repo: https://github.com/acker241/ccmon

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$posFile = "$env:USERPROFILE\.ccmon-pos.txt"

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

# ---------- window behavior ----------

$window.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })
$window.Add_KeyDown({ if ($_.Key -eq 'Escape') { $window.Close() } })

$menu = New-Object System.Windows.Controls.ContextMenu
$miClose = New-Object System.Windows.Controls.MenuItem
$miClose.Header = 'Close'
$miClose.Add_Click({ $window.Close() })
$menu.Items.Add($miClose) | Out-Null
$window.ContextMenu = $menu

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

# ---------- async fetch worker ----------

$workerScript = {
    param($userprofile, $sessLimEnv, $dailyLimEnv, $weeklyLimEnv)

    function Format-Tokens($n) {
        if ($n -ge 1e9) { return ('{0:N2}B' -f ($n/1e9)) }
        if ($n -ge 1e6) { return ('{0:N1}M' -f ($n/1e6)) }
        if ($n -ge 1e3) { return ('{0:N1}k' -f ($n/1e3)) }
        return "$n"
    }
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

    $sessLim = if ($sessLimEnv) { [long]$sessLimEnv } else {
        ($blocks | Where-Object { -not $_.isGap } | Measure-Object -Property totalTokens -Maximum).Maximum
    }
    $dailyLim = if ($dailyLimEnv) { [long]$dailyLimEnv } else {
        ($daily | Measure-Object -Property totalTokens -Maximum).Maximum
    }
    $weeklyLim = if ($weeklyLimEnv) { [long]$weeklyLimEnv } else {
        ($weekly | Measure-Object -Property totalTokens -Maximum).Maximum
    }

    $sessUsed   = if ($active) { $active.totalTokens } else { 0 }
    $dailyUsed  = if ($today)  { $today.totalTokens }  else { 0 }
    $weeklyUsed = if ($thisWk) { $thisWk.totalTokens } else { 0 }

    $sessPct   = if ($sessLim   -gt 0) { [math]::Min(100, [math]::Round(100 * $sessUsed   / $sessLim))   } else { 0 }
    $dailyPct  = if ($dailyLim  -gt 0) { [math]::Min(100, [math]::Round(100 * $dailyUsed  / $dailyLim))  } else { 0 }
    $weeklyPct = if ($weeklyLim -gt 0) { [math]::Min(100, [math]::Round(100 * $weeklyUsed / $weeklyLim)) } else { 0 }

    $rateAvg = if ($active) { [double]$active.burnRate.tokensPerMinute } else { 0 }
    $tok30 = Get-WindowTokens 30
    $tok60 = Get-WindowTokens 60
    $rate30 = $tok30 / 30
    $rate60 = $tok60 / 60

    $remTok = [math]::Max(0, $sessLim - $sessUsed)
    $etaAvg = if ($rateAvg -gt 0) { $remTok / $rateAvg } else { -1 }
    $eta30  = if ($rate30  -gt 0) { $remTok / $rate30  } else { -1 }
    $eta60  = if ($rate60  -gt 0) { $remTok / $rate60  } else { -1 }

    $resetLeft = if ($active) { Format-Duration $active.projection.remainingMinutes } else { '--' }

    return @{
        clock     = (Get-Date).ToString('HH:mm:ss')
        sessPct   = $sessPct
        dailyPct  = $dailyPct
        weeklyPct = $weeklyPct
        reset     = "reset  $resetLeft"
        eta       = ("ETA  avg {0}  30m {1}  1h {2}" -f (Format-Duration $etaAvg), (Format-Duration $eta30), (Format-Duration $eta60))
    }
}

# ---------- async dispatcher ----------

$script:fetchPS = $null
$script:fetchHandle = $null

function Get-BarString($pct) {
    $w = 12
    $filled = [math]::Floor($w * $pct / 100)
    return (('#' * $filled) + ('.' * ($w - $filled)))
}
function Get-PctColor($pct) {
    if ($pct -ge 80) { return '#FF6B6B' }
    if ($pct -ge 50) { return '#FFD93D' }
    return '#6BCB77'
}

function Start-AsyncFetch {
    if ($script:fetchPS) { return }
    $script:fetchPS = [PowerShell]::Create()
    $null = $script:fetchPS.AddScript($workerScript).
        AddArgument($env:USERPROFILE).
        AddArgument($env:CCMON_SESSION_LIMIT).
        AddArgument($env:CCMON_DAILY_LIMIT).
        AddArgument($env:CCMON_WEEKLY_LIMIT)
    $script:fetchHandle = $script:fetchPS.BeginInvoke()
    $tStatus.Text = '...'
    $tStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#666')
}

function Apply-Result($r) {
    $tClock.Text = $r.clock
    $tStatus.Text = 'ccmon'

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
})
$pollTimer.Start()

$refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$refreshTimer.Interval = [TimeSpan]::FromSeconds(30)
$refreshTimer.Add_Tick({ Start-AsyncFetch })
$refreshTimer.Start()

$window.Add_Loaded({ Start-AsyncFetch })

[void]$window.ShowDialog()
