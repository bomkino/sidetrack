# Sidetrack handover

## Resume here

Workspace:

```text
/Volumes/external_2tb/Google Drive Sync/pitch.dog - google drive/[00] PROJECTS [pitch.dog]/[pitch.dog]/[2026]/[Sidetrack]
```

Read `README.md`, `PHILOSOPHY.md`, then `Docs/design-reference.png`.

## Current truth — 19 July 2026

- Native macOS AppKit app; no SwiftUI, Electron, network, telemetry, or render loop.
- Dark-only editorial interface based on user reference.
- Main thought + literal timer state/click outcome stay together; poetic shifted date/time live on the right while secondary content fades.
- Display clock defaults to +15 minutes and is independently configurable; pomodoro timing remains real.
- Defaults: 50 focus, 12 break, repeated three times, then 30 long break.
- Main thought and all later thoughts support one level of subthoughts.
- Checks, promotion, contextual right-click actions, native undo, timer reset, copy-bank fresh-day reset, bottom-up reminders, daily distraction increment/decrement, embedded hover hotkeys, seven-day history, manual Markdown export, and automatic midnight/next-launch day archives implemented.
- Compact layout verified from 900 × 600 upward. Main copy wraps and fits down, right-column subthoughts hide first, timer instructions own their vertical space, and resize invalidation prevents stale or clipped canvases after display changes.
- Local writes are atomic with a rolling readable backup; unreadable JSON is preserved. Repeated same-day archives receive collision-safe suffixes instead of overwriting earlier pages.
- Full screen verified on second display at 1920×1080 logical / 3840×2160 physical.
- Last verification: `Sidetrack checks passed: 157`; 40 rapid cross-size resizes, a 202-action input burst, long wrapped editing, focus/paused spacing, preferences, data recovery, archive collisions, icon resolution, and full-screen launch verified.
- Settled idle: 0.0% CPU between minute redraws; about 7–11 MB RSS in full screen.
- App icon source: `Assets/Sidetrack-icon-source.png`.
- Built app: `build/Sidetrack.app`.
- Installed app: `/Applications/Sidetrack.app`, version 1.1.0 (build 2), 3.1 MB, ad-hoc signature verified. The running app exposes the full multi-resolution icon and launches full-screen on the remembered second display.
- Public repository: `https://github.com/bomkino/sidetrack`; branch and release state must be checked live.

## Finish next

1. Read live git status; run `Scripts/test.sh` and `Scripts/build-app.sh` after any edit.
2. Confirm GitHub default branch and CC0-1.0 license detection before the next release.

## Release checks

```sh
Scripts/test.sh
Scripts/build-app.sh
codesign --verify --deep --strict build/Sidetrack.app
plutil -lint build/Sidetrack.app/Contents/Info.plist
```

Do not add accounts, sync, notifications, continuous timers, red urgency, streaks, or productivity scoring. Preserve user’s reference composition and low-luminance palette.
