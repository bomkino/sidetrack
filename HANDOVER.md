# Sidetrack handover

## Resume here

Workspace:

```text
/Volumes/external_2tb/Google Drive Sync/pitch.dog - google drive/[00] PROJECTS [pitch.dog]/[pitch.dog]/[2026]/[Sidetrack]
```

Read `README.md`, `PHILOSOPHY.md`, then `Docs/design-reference.png`.

## Current truth — 8 August 2026

- Native macOS AppKit app; no SwiftUI, Electron, network, telemetry, or render loop.
- Dark-only editorial interface based on user reference.
- Main thought + literal timer state/click outcome stay together; poetic shifted date/time live on the right while secondary content fades.
- Display clock defaults to +15 minutes and is independently configurable; pomodoro timing remains real.
- Defaults: 50 focus, 12 break, repeated three times, then 30 long break.
- Display preferences now choose the second screen relative to the Mac's main display (left, right, above, or remembered), portrait/landscape composition, and Today-panel side. The default is left + vertical, matching the current working setup.
- Six bounded component scales keep the main thought, rhythm, Today list, steps, date/time, and distraction count adjustable without turning the page into a dashboard. OLED dim mode uses a true black background during a running focus while the thought, rhythm, and time remain legible.
- Main thought and all later thoughts support one level of subthoughts.
- First launch is a genuinely empty page with a rotating bank of quiet invitations. Exact untouched demo pages from older builds migrate to empty without disturbing settings or distraction counts.
- Checks, promotion, contextual right-click actions, native undo, timer reset, copy-bank fresh-day reset, bottom-up reminders, daily distraction increment/decrement, embedded hover hotkeys, seven-day history, manual Markdown export, and automatic midnight/next-launch day archives implemented.
- Compact layout verified from 900 × 600 upward in both split and stacked compositions. Main copy wraps and fits down, low-priority subthoughts hide first, timer instructions own their vertical space, panel-side changes reserve the distraction counter, and resize invalidation prevents stale or clipped canvases after display changes.
- Local writes are atomic with a rolling readable backup; a missing or unreadable primary recovers automatically, and unreadable source JSON is preserved. Save/export failures keep the page intact and explain the local write problem. Repeated same-day archives receive collision-safe suffixes instead of overwriting earlier pages.
- Full-screen launch waits for confirmed app activation, then uses a bounded, transition-aware retry instead of one brittle delayed toggle. It is verified on the remembered second display at 1920×1080 logical / 3840×2160 physical.
- Last verification: `Sidetrack checks passed: 169`; 40 rapid cross-size resizes, split/stacked layout, OLED dim mode, scale normalization/migration, a 202-action input burst, long wrapped editing, focus/paused spacing, preferences, both historical first-run migrations, missing/corrupt data recovery, archive collisions, icon resolution, and full-screen launch verified.
- Settled idle: 0.0% CPU between minute redraws; about 10–32 MB RSS. A portrait full-screen backing surface can make macOS report about 90 MB physical footprint, stable rather than a leak.
- App icon source: `Assets/Sidetrack-icon-source.png`.
- GitHub product portrait: `Docs/Sidetrack-product-portrait.png`; 2400 × 1350, fictional task data, no private user content.
- Built app: `build/Sidetrack.app`; use `build/Sidetrack.app.zip` for installation because the synced workspace can decorate unpacked bundle folders with unrelated Finder icon metadata after signing.
- Installed app: `/Applications/Sidetrack.app`, version 1.2.0 (build 1), 3.2 MB, ad-hoc signature verified. Installed executable SHA-256: `d26e8ec6d097964de315ea7706b6f420b3509e6a7bb180c2a648c81597d8b043`, matching `build/Sidetrack.app`. The next launch should land full-screen on the left vertical display by default.
- Public repository: `https://github.com/bomkino/sidetrack`; branch and release state must be checked live.
- Latest merged release: `https://github.com/bomkino/sidetrack/releases/tag/v1.2.0`; `Sidetrack.app.zip` SHA-256 `441b263d76640c737dc1f68c6ae98e56441fe174858ac15bba3dfb92018d1c19`.

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
