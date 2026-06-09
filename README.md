# Codex Token Bar

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a>
</p>

<table align="center">
  <tr>
    <td align="center" width="180">
      <img src="Assets/AppIcon.png" width="112" alt="Codex Token Bar app icon"><br>
      <strong>Codex Token Bar</strong>
    </td>
    <td align="center" width="280">
      <img src="Assets/wechat-group-qr.jpeg" width="220" alt="WeChat group QR code for HTT repositories"><br>
      WeChat group for discussion, releases, and update notes.
    </td>
  </tr>
</table>

A local-first macOS SwiftUI app for visualizing Codex token usage and live output speed from local session logs.

<p align="center">
  <img src="Assets/DashboardPreview.png" alt="Codex Token Bar screenshot" width="100%">
</p>

<p align="center">
  <img src="Assets/FloatingPanelPreview.png" alt="Floating live token-rate panel" width="420">
</p>

## Install

Recommended one-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/hututuo/codex-token-bar/main/install.sh | bash
```

The installer downloads the latest `.app.zip` release, unpacks it, installs the app into `/Applications` when writable or `~/Applications` otherwise, removes the common `com.apple.quarantine` flag, and opens the app.

This helps avoid the common macOS "app is damaged and can't be opened" message caused by browser-downloaded unsigned apps being quarantined. It is not a full replacement for Apple Developer ID signing and notarization. Company MDM, security software, or stricter macOS policy can still block unsigned apps.

## Update

Use the same one-line command to update. It always downloads the latest GitHub release and replaces the existing app:

```bash
curl -fsSL https://raw.githubusercontent.com/hututuo/codex-token-bar/main/install.sh | bash
```

## Optional Codex Desktop Sidebar Patch

Some Codex Desktop builds load the project sidebar from only the first global recent-conversation page. If a workspace has many older local conversations outside that first page, the sidebar can show only a few conversations even though the local database still contains them.

Codex Token Bar includes an optional local hot patch for the installed Codex Desktop app:

```bash
curl -fsSL https://raw.githubusercontent.com/hututuo/codex-token-bar/main/scripts/patch_codex_desktop_sidebar.sh | bash -s -- install
```

Check patch status:

```bash
curl -fsSL https://raw.githubusercontent.com/hututuo/codex-token-bar/main/scripts/patch_codex_desktop_sidebar.sh | bash -s -- status
```

Rollback to the latest backup:

```bash
curl -fsSL https://raw.githubusercontent.com/hututuo/codex-token-bar/main/scripts/patch_codex_desktop_sidebar.sh | bash -s -- rollback
```

The patch backs up `app.asar` and the original code signature under `~/Library/Application Support/CodexTokenBar/codex-desktop-sidebar-patch/backups/`, rewrites the Desktop renderer bundle locally, ad-hoc re-signs `Codex.app`, then reopens Codex. It does not modify `~/.codex` data. Future official Codex updates may overwrite the patch.

## What It Does

- Auto-detects local Codex data from a saved directory, `CODEX_HOME`, `~/.codex`, `~/.config/codex`, or one-level home-directory candidates.
- Reads local Codex `token_count` events from `sessions/**/*.jsonl`.
- Summarizes token usage, calls, streaks, peak usage, and thread count.
- Shows the active data source in the header and provides a fallback directory picker.
- Shows a profile-style yearly heatmap with nearest-cell hover details.
- Heatmap modes use clear metrics: daily totals, calendar-week totals, or cumulative totals through the selected day.
- Tracks live all-session Codex output speed from local stream logs, with a compact drill-down row for a selected session.
- Offers a lightweight floating live-rate panel with total tok/s, lifetime tokens, today's tokens, and today's request count.
- Supports a precise `o200k_base` token-counting toggle for live stream deltas, with a calibrated lightweight estimator as the default.
- Shows recent 24-hour token and request activity at 30-minute granularity, with hover details for each time point.
- Refreshes automatically every minute and also provides a manual refresh button.
- Exports a shareable PNG snapshot and CSV summary.

## Releases

Version notes and downloadable app zips live on the [GitHub Releases page](https://github.com/hututuo/codex-token-bar/releases).

## Privacy

The MVP reads local files only. It does not upload logs, prompts, outputs, or account data.

## Data Sources

The app treats a Codex Home directory as a folder containing:

```text
sessions/
state_5.sqlite
```

`sessions/` is used for precise token-count events. `state_5.sqlite` is used as fallback metadata when available.

## Run

For contributors who want to run from source:

```bash
brew install git-lfs
git lfs install
scripts/prepare_tiktoken_lfs.sh
swift run CodexTokenBar
```

`git-lfs` is needed because the exact `o200k_base` tokenizer uses a binary Swift FFI package. The prepare script fetches only the macOS binary slice needed for this app. If the tokenizer cannot load at runtime, the app falls back to a lightweight calibrated estimator.

## Package A Local App

```bash
brew install git-lfs
git lfs install
chmod +x scripts/package_app.sh
scripts/package_app.sh debug
```

Debug packaging automatically quits the previous local debug app and opens the newly built app. Set `CODEX_TOKEN_BAR_NO_OPEN=1` if you only want to package it.

## Notes

This project intentionally starts as a Swift Package so contributors can build it without an Xcode project. A signed `.app` wrapper can be added later.

## License

MIT
