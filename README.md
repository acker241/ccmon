# ccmon

Compact desktop overlay for monitoring Claude Code token usage on Windows.

Shows session / daily / weekly usage as % bars, plus ETA to exhaust the current session block at 3 different burn rates (avg, last 30 min, last 1 h).

```
┌──────────────────────────────┐
│ 14:23:01                ccmon│
│                              │
│ session ##########..  64%    │
│ daily   #####.......  31%    │
│ weekly  ##........... 14%    │
│                              │
│ reset  2h47m                 │
│ ETA  avg 12h0m  30m 3h3m  1h 5h3m │
└──────────────────────────────┘
```

- Borderless, always-on-top, draggable, semi-transparent
- ESC or right-click → Close to dismiss
- Position remembered between launches
- Refresh every 30s, fully async (UI never blocks)
- Reads `~/.claude/projects/**/*.jsonl` for windowed burn rates

## Requirements

- Windows 10+
- PowerShell 5.1+ (preinstalled) or 7+
- Node.js 18+ (for `ccusage` via `npx`)

## Install

```powershell
git clone https://github.com/<your-user>/ccmon.git
cd ccmon
powershell -ExecutionPolicy Bypass -File install.ps1
```

Add `-Startup` to auto-launch on Windows boot:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Startup
```

Files are copied to `%LOCALAPPDATA%\ccmon`, a shortcut is created on the Desktop.

## Run

Double-click `Desktop\ccmon-overlay.lnk`. First launch downloads `ccusage` (~10s).

Alternative: terminal mode (pinnable to taskbar):
```powershell
powershell -File "$env:LOCALAPPDATA\ccmon\ccmon-terminal.ps1"
```

## Configure limits

By default the bars auto-calibrate against your **historical maximum** (your personal record). To show % against your actual Anthropic plan limits, set these env vars (values in tokens):

```powershell
[Environment]::SetEnvironmentVariable('CCMON_SESSION_LIMIT', '92000000',    'User')
[Environment]::SetEnvironmentVariable('CCMON_DAILY_LIMIT',   '1500000000',  'User')
[Environment]::SetEnvironmentVariable('CCMON_WEEKLY_LIMIT',  '10600000000', 'User')
```

### How to derive your limits

Open https://claude.ai/settings/usage. For each bar, compute:

`limit = current_tokens_used / current_dashboard_pct`

Where `current_tokens_used` comes from running `npx ccusage blocks --active --json` (session) or `daily --json` / `weekly --json`. Recalibrate monthly — the ratio drifts as cache-read share changes.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

Removes files, shortcuts, and saved overlay position.

## How it works

- `ccusage blocks/daily/weekly --json` gives session-block, daily, weekly token totals
- Raw JSONL parsing computes windowed burn rates (30 min, 1 h) not exposed by ccusage
- ETA = `(session_limit - session_used) / rate_tokens_per_minute`
- WPF window (PowerShell + XAML) renders the overlay
- Async work runs in a background runspace; UI dispatcher polls completion every 200ms

## License

MIT
