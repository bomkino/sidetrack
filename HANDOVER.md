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
- Main thought + literal timer state/click outcome stay together; poetic shifted date/time live on the right while secondary content fades.
- Display clock defaults to +15 minutes and is independently configurable; pomodoro timing remains real.
- Defaults: 50 focus, 12 break, repeated three times, then 30 long break.
- Main thought and all later thoughts support one level of subthoughts.
- Checks, promotion, contextual right-click actions, native undo, timer reset, copy-bank fresh-day reset, bottom-up reminders, daily distraction increment/decrement, embedded hover hotkeys, seven-day history, manual Markdown export, and automatic midnight/next-launch day archives implemented.
- Full screen verified on second display at 1920×1080 logical / 3840×2160 physical.
- Last verification: `Sidetrack checks passed: 149`; click-away editing, focus/paused/short-break states, zero-state question, keyboard break start, copy-bank reset, automatic rollover archive, hover controls, preferences, context menus, and full screen verified.
- Settled idle sample: 0.00 additional CPU seconds across 20 seconds; about 10 MB RSS in full screen.
- App icon source: `Assets/Sidetrack-icon-source.png`.
- Built app: `build/Sidetrack.app`.
- Installed app: `/Applications/Sidetrack.app`, version 1.0.0, 3.1 MB, ad-hoc signature verified after the final rebuild.
- Local git repository exists on `main`; publish state must be checked live.

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
