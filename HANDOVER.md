# Sidetrack handover

## Resume here

Workspace:

```text
/Volumes/external_2tb/Google Drive Sync/pitch.dog - google drive/[00] PROJECTS [pitch.dog]/[pitch.dog]/[2026]/[Sidetrack]
```

Read `README.md`, `PHILOSOPHY.md`, then `Docs/design-reference.png`.

## Current truth — 9 August 2026

- Native macOS AppKit app; no SwiftUI, Electron, network, telemetry, or render loop.
- Dark-only editorial interface based on user reference.
- Main thought + literal timer state/click outcome stay together; poetic shifted date/time live on the right while secondary content fades.
- Finished focus/rest choices carry a quiet overrun ladder: one text breath at 2×, a glyph-aware hairline at 3× that skips descender ink, both at 4×, silence at 5×. Each threshold performs one finite Core Animation breath, then returns the display cycle to sleep; no reminder animation repeats forever.
- Display clock defaults to +15 minutes and is independently configurable; pomodoro timing remains real.
- Defaults: 50 focus, 12 break, repeated three times, then 30 long break.
- Display preferences now choose the second screen relative to the Mac's main display (left, right, above, or remembered), portrait/landscape composition, Today-panel side, balanced/left/right edge alignment, and main-vs-Today order. The default is left + vertical, matching the current working setup. Preference changes preview immediately on the page.
- Presence preference can expose Sidetrack in the Dock, the menu bar, or both; menu-bar-only mode keeps a small branded status item and leaves the page available without a Dock/Cmd-Tab entry.
- Portrait’s default is a day-first editorial grid: Today and the distraction counter live in the top register; the main thought, rhythm, and time settle onto a lower baseline. The main-first two-column composition remains available as a deliberate swap.
- Six bounded component scales keep the main thought, rhythm, Today list, steps, date/time, and distraction count adjustable without turning the page into a dashboard. OLED dim mode uses a true black background during a running focus while the thought, rhythm, and time remain legible.
- Main thought and all later thoughts support one level of subthoughts.
- A 20-character north star sits beside the distraction count, persists across day changes, exports to Markdown, and is editable by click or `G`.
- The shortcut whisper belongs only to the distraction counter. Hovering the north star leaves it visible and editable; visible copy and Markdown call it “north star,” not “One Thing.”
- Custom-drawn content now has a stable VoiceOver reading order and semantic actions for the date/time, main thought, steps, Today list, timer choices, distraction count, north star, and add-thought invitation.
- First launch is a genuinely empty page with a rotating bank of quiet invitations. Exact untouched demo pages from older builds migrate to empty without disturbing settings or distraction counts.
- Checks, promotion, contextual right-click actions, native undo, timer reset, copy-bank fresh-day reset, bottom-up reminders, daily distraction increment/decrement, embedded hover hotkeys, seven-day history, manual Markdown export, and automatic midnight/next-launch day archives implemented.
- Compact layout verified from 900 × 600 upward in both split and stacked compositions. Main copy wraps and fits down, low-priority subthoughts hide first, timer instructions own their vertical space, panel-side changes reserve the distraction counter, and resize invalidation prevents stale or clipped canvases after display changes.
- Local writes are atomic with a rolling readable backup; a missing or unreadable primary recovers automatically, and unreadable source JSON is preserved. Save/export failures keep the page intact and explain the local write problem. Repeated same-day archives receive collision-safe suffixes instead of overwriting earlier pages.
- Full-screen launch waits for confirmed app activation, then uses a bounded, transition-aware retry instead of one brittle delayed toggle. It is verified on the remembered second display at 1920×1080 logical / 3840×2160 physical.
- Last core verification: `Sidetrack checks passed: 189`; the new grid, scale migration, alignment/order model, live-preference callback path, presence preference, north-star persistence/export, overrun cue ladder, and morning/midday language are covered in addition to the existing resize, OLED, editing, timer, persistence, archive, icon, and full-screen checks.
- Settled idle: 0.0% CPU between minute redraws. The installed 1.4.1 process sampled at 7.3–8.5 MB RSS after launch; Activity Monitor may report a larger physical footprint for a portrait full-screen backing surface, but repeated samples remain stable rather than growing like a leak.
- App icon source: `Assets/Sidetrack-icon-source.png`.
- GitHub product portrait: `Docs/Sidetrack-product-portrait.png`; 2400 × 1350, fictional task data, no private user content.
- Release line: `v1.4.2` (build 5). See `CHANGELOG.md` for the complete human-readable delta.
- Built app: `build/Sidetrack.app`; use `build/Sidetrack.app.zip` for installation because the synced workspace can decorate unpacked bundle folders with unrelated Finder icon metadata after signing. The ZIP retains the `Sidetrack.app` wrapper.
- The release build is universal (`arm64` + `x86_64`), and both slices declare macOS 13.0 as their deployment target. An x86_64 launch under Rosetta and the native arm64 UI pass both completed without a startup failure.
- Local installation target: `/Applications/Sidetrack.app`. Verify its version, signature, architectures, and executable hash against the built app after every install; preserve the replaced bundle as a versioned backup.
- Public repository: `https://github.com/bomkino/sidetrack`; default branch `main`; CC0-1.0 detected.
- Release truth is not inferred from this file. Read back GitHub `main`, the `v1.4.2` tag and release asset, exact CI, and the installed bundle before claiming they match.

## Finish next

1. Read live git status; run `Scripts/test.sh` and `Scripts/build-app.sh` after any edit.
2. Recheck GitHub default branch, license detection, and CI before the next release.

## Release checks

```sh
Scripts/test.sh
Scripts/build-app.sh
codesign --verify --deep --strict build/Sidetrack.app
plutil -lint build/Sidetrack.app/Contents/Info.plist
```

Do not add accounts, sync, notifications, continuous timers, red urgency, streaks, or productivity scoring. Preserve user’s reference composition and low-luminance palette.
