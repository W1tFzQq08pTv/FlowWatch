<div align="center">
  <img src=".github/assets/app-icon.png" width="96" height="96" alt="FlowWatch" />
  <h1>FlowWatch</h1>
  <p>Lightweight macOS menu bar network monitor: live speed, traffic stats, and trends.</p>
</div>

[简体中文](README.md) | English

> 🖥 Windows version: [FlowWatch-Win](https://github.com/W1tFzQq08pTv/FlowWatch-Win)

## Features
- Real-time upload/download speed in the menu bar
- Menu popup with current speed, today's total, and a 7-day trend chart (Charts, macOS 13+)
- Dedicated statistics details window with overview, trends, and fun stats sections
- Per-app traffic monitoring with date range filters and sorting
- Custom sampling interval and display style
- Automatic update checks with last/next check time
- Optional file logging (daily logs, kept for 7 days)

## Data & Privacy
- Traffic stats are calculated locally from system network interface counters; no packet content is captured.
- Settings and daily totals are stored on your device only (UserDefaults).
- Logs (if enabled) are written locally and never uploaded or synced.
- No account is required, and the app does not upload or sync your data.

## Statistics Details
The statistics details window keeps the main popup focused while providing a fuller view of historical traffic.

- Overview: total download, total upload, total traffic, recorded days, and active days
- Trends: 7-day total, 7-day daily average, historical daily average, today vs yesterday, and peak day
- Fun stats: traffic title, upload/download ratio, download share, most active date, and latest active day

## Install
### Homebrew
```bash
brew tap w1tfzqq08ptv/flowwatch
brew install --cask flowwatch
```

### Download from Releases
Download the latest DMG from GitHub Releases:
[FlowWatch Releases](https://github.com/W1tFzQq08pTv/FlowWatch/releases)

## Screenshots
| Status bar: speed | Status bar: today | Status bar: speed + today |
| --- | --- | --- |
| <img src=".github/assets/statusbar-speed.png" width="260" alt="Status bar speed" /> | <img src=".github/assets/statusbar-today.png" width="260" alt="Status bar today" /> | <img src=".github/assets/statusbar-speed-today.png" width="260" alt="Status bar speed and today" /> |

| Menu Popup | Statistics Details |
| --- | --- |
| <img src=".github/assets/popup-en.png" width="360" alt="Menu Popup" /> | <img src=".github/assets/statistics-en.png" width="520" alt="Statistics Details" /> |

| Per-App Traffic | Settings |
| --- | --- |
| <img src=".github/assets/perapp-traffic-en.png" width="520" alt="Per-App Traffic" /> | <img src=".github/assets/settings-en.png" width="520" alt="Settings" /> |
