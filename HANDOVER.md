# Sidetrack handover

## Resume here

Workspace:

```text
/Volumes/external_2tb/Google Drive Sync/pitch.dog - google drive/[00] PROJECTS [pitch.dog]/[pitch.dog]/[2026]/[Sidetrack]
```

Read `README.md`, `PHILOSOPHY.md`, then `Docs/design-reference.png`.

## Current truth — 18 July 2026

- Native macOS AppKit app; no SwiftUI, Electron, network, telemetry, or render loop.
- Dark-only editorial interface based on user reference.
- Main thought + approximate timer + spoken clock stay present during focus; secondary content fades.
- Date has its own quiet line.
- Defaults: 50 focus, 12 break, repeated three times, then 30 long break.
- Main thought and all later thoughts support one level of subthoughts.
- Checks, promotion, right-click deletion, native undo, timer reset, fresh-day reset, daily distraction clicker, seven-day clicker history, and Markdown day export implemented.
- Full screen verified on second display at 1920×1080 logical / 3840×2160 physical.
- Last verification: `Sidetrack checks passed: 84`; package signature and plist valid.
- Idle sample: 0.01 CPU seconds across 12 seconds; 7–8 MB RSS in full-screen focus state.
- App icon source: `Assets/Sidetrack-icon-source.png`.
- Built app: `build/Sidetrack.app`.
- Installed app: `/Applications/Sidetrack.app`, version 1.0.0, 3.0 MB, ad-hoc signature verified.
- Local git repository exists on `main` with a clean first commit.

## Finish next

1. Read live git status; run `Scripts/test.sh` and `Scripts/build-app.sh` after any edit.
2. Publish public GitHub repository under `bomkino` when internet is stable.
3. Confirm GitHub license detection shows CC0-1.0.

## Release checks

```sh
Scripts/test.sh
Scripts/build-app.sh
codesign --verify --deep --strict build/Sidetrack.app
plutil -lint build/Sidetrack.app/Contents/Info.plist
```

Do not add accounts, sync, notifications, continuous timers, red urgency, streaks, or productivity scoring. Preserve user’s reference composition and low-luminance palette.
