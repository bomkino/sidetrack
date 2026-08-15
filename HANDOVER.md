# Sidetrack handover

## Resume here

Workspace:

```text
/Volumes/external_2tb/Google Drive Sync/pitch.dog - google drive/[00] PROJECTS [pitch.dog]/[pitch.dog]/[2026]/[Sidetrack]
```

Read `README.md`, `PHILOSOPHY.md`, then `Docs/design-reference.png`.

## Current truth — 15 August 2026

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
- The window now constrains itself to its chosen display before full-screen entry and after display changes. The former 900-point minimum width could force a 720-point portrait screen across both monitors; the supported window floor is now 640 × 900, and the actual left-hand 720 × 1280 portrait display passed full-screen, long-copy, seven-step, and Mission Control round-trip checks.
- The daily page now has one explicit persisted lifecycle: open, away, or closed. Step Away pauses a moving rhythm and remembers whether Sidetrack paused it; return may resume or stay paused. Close archives before changing state. A calendar boundary safety-archives once but never silently ends the day.
- macOS screen sleep and session lock may mark an open page away. Wake only refreshes the minute display; it never returns or starts a timer. There is no activity polling and no dependency on Computer History, Chronicle, Screen Time, or accessibility input monitoring.
- The bounded production-wiring harness in `build/qa/notification-harness/` posts AppKit’s screen-sleep and wake notifications through the real `AppDelegate`: sleep persisted an owned away pause; wake left it away and paused. This verifies the notification path without locking the user’s live session.
- Compact portrait windows use available height rather than a hard seven-row cap. Saved overflow stays reachable through one `+ N more` line, a native menu, and named VoiceOver actions; hidden-item editors anchor visibly to that line.
- Local writes are atomic with a rolling readable backup; a missing or unreadable primary recovers automatically, and unreadable source JSON is preserved. Save/export failures keep the page intact and explain the local write problem. Repeated same-day archives receive collision-safe suffixes instead of overwriting earlier pages.
- Full-screen launch waits for confirmed app activation, then uses a bounded, transition-aware retry instead of one brittle delayed toggle. It is verified on the remembered second display at 1920×1080 logical / 3840×2160 physical.
- Last deterministic verification: `Sidetrack checks passed: 251`; the explicit day-state migration and transitions, timer ownership on return, held away/closed deadlines, field-level JSON salvage, duplicate-ID repair, contradictory phase repair, elapsed-deadline handling, boundary-vs-exact archive tracking, close/archive marker, midnight safety archive, and fresh-day preservation rules are covered in addition to the earlier grid, accessibility, timer, persistence, and full-screen checks.
- Settled candidate idle: 0.0% CPU across six samples; RSS fell from 26.6 MB to 12.3 MB after resize/full-screen activity settled. The data-file hash and mtime remained unchanged. Activity Monitor may report a larger physical footprint for a portrait full-screen backing surface, but stable samples—not one number—distinguish it from a leak.
- App icon source: `Assets/Sidetrack-icon-source.png`.
- GitHub product portrait: `Docs/Sidetrack-product-portrait.png`; 2400 × 1350, fictional task data, no private user content.
- Release line: `v1.5.0` (build 8). See `CHANGELOG.md` for the complete human-readable delta. Frozen source/test/script/resource digest: `45dd31003bf9c6cfe6f04599d9d07f1e9af6235e1fd6d06d8297d5aee1cedac9`. Release source commit: `6be8bde32893eca73c72f057d5c88cb1f623a3a8`.
- Built app: `build/Sidetrack.app`; use `build/Sidetrack.app.zip` for installation because the synced workspace can decorate unpacked bundle folders with unrelated Finder icon metadata after signing. The ZIP retains the `Sidetrack.app` wrapper.
- The candidate is universal (`arm64` + `x86_64`), and both slices declare macOS 13.0 as their deployment target. App and ZIP-stream executable SHA-256: `17cab1b483ce6f1d175d900edb7d1ede07c5013a7d22a7dd3bc324a767fc653c`; ZIP SHA-256: `f88ac69534b15a26e25bd61cbee2ba5191c04854e1e9233d38a718367422c0e0`.
- The archive passes strict ad-hoc signature integrity. It has no TeamIdentifier and is not Developer ID signed or notarized; Gatekeeper acceptance on another Mac is not claimed.
- `/Applications/Sidetrack.app` is now the only Sidetrack bundle in `/Applications`: `1.5.0` build `8`, executable SHA-256 `17cab1b483ce6f1d175d900edb7d1ede07c5013a7d22a7dd3bc324a767fc653c`. The seven older bundles were moved recoverably to `/Users/kay/.Trash/Sidetrack-old-installs-2026-08-15.TFYsYr`.
- The install was extracted from the frozen ZIP, verified before and after copying, launched from `/Applications`, and visually read back full-screen on the real left 2160 × 3840 physical portrait display. Main thought, step, six Today thoughts, `$10k` north star, custom `50/12/30` rhythm, `+20` clock, display settings, counts, and paused timer were preserved exactly. Pre/post-quit JSON copies live under `build/qa/install-backup.C07Kl7/`.
- Exact-snapshot receipts: `251` deterministic checks; `2,041,154` core assertions across `256,000` randomized actions; `865` AppKit assertions across `606` rendered layouts; and the full randomized suite repeated under AddressSanitizer. The frozen package hashes above were read back from both the app and ZIP. Independent visual and release critics returned `holds`.
- Public repository: `https://github.com/bomkino/sidetrack`; public visibility, default branch `main`, and CC0-1.0 were read back through GitHub. Release source `6be8bde` passed the exact `macOS checks` run `31890555402`: `https://github.com/bomkino/sidetrack/actions/runs/31890555402`.
- `v1.5.0` is GitHub's latest non-draft, non-prerelease release: `https://github.com/bomkino/sidetrack/releases/tag/v1.5.0`. Its annotated tag peels to `6be8bde`. A fresh public download of `Sidetrack.app.zip` passed ZIP integrity and reproduced both frozen hashes exactly; the first truncated network attempt was rejected rather than mistaken for a bad release.
- Release truth is not inferred from this file. Read back GitHub `main`, the latest tag and release asset, exact CI, and the installed bundle before claiming they match.

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
