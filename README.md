# Sidetrack

![Sidetrack icon](Assets/Sidetrack-icon-source.png)

Sidetrack is a quiet second-screen focus display for macOS. One sentence holds the center. Everything else waits in the margin.

No account. No sync. No notifications. No streaks. No network calls. No Chromium.

## Why

Some brains do not need another productivity system. They need somewhere gentle to return to.

Sidetrack keeps one thought large, a few subthoughts nearby, and the rest of today small. Its pomodoro refuses false precision: `~20 minutes left`, then `a few minutes left`. Clock time speaks in quarters. Nothing rings unless you explicitly ask for one soft chime. Nothing starts a break without you.

Read [PHILOSOPHY.md](PHILOSOPHY.md) for the thinking behind it.

## What it does

- Opens full-screen on the last-used display.
- Holds one editable main thought plus one level of subthoughts.
- Keeps later thoughts and their subthoughts in a quiet margin.
- Runs a manual `50 / 12 / 50 / 12 / 50 / 30` focus rhythm.
- Fades secondary material during focus.
- Counts distractions with a tiny daily `0000` clicker; right-click shows seven days.
- Exports the day as readable Markdown.
- Saves everything locally as readable JSON.

## Keys

- `N` — hold a new thought
- `S` — add a subthought to the main thought
- `E` — write over the main thought
- `Space` — start or pause focus
- `P` — promote the next thought
- `X` — complete the main thought
- `D` — count one distraction
- `,` — preferences
- `⌃⌘F` — enter or leave full screen
- `⇧⌘E` — export day as Markdown
- `⌘Z` — undo deletion or reset

Click circles to check items. Click a later thought to promote it. Right-click any thought or subthought to delete it.

## Privacy and files

Sidetrack never uses the network. Runtime data lives at:

```text
~/Library/Application Support/Sidetrack/sidetrack.json
```

The file is pretty-printed JSON. Export uses a normal macOS save panel and creates a plain `.md` file wherever you choose.

## Build

Requires macOS 13 or newer and Apple Command Line Tools.

```sh
Scripts/test.sh
Scripts/build-app.sh
```

Built app appears at `build/Sidetrack.app`. Build uses `swiftc` directly so no full Xcode install is required.

## Performance

Sidetrack is native AppKit with custom event-driven drawing. No continuous render loop exists. Clock, vague timer, and pixel drift redraw once per minute; edits redraw on input.

Measured on a 4K second display during development:

- `0.00s` CPU consumed across a 12-second idle sample
- roughly `7–8 MB` resident memory at rest
- roughly `385 KB` executable

## Freedom

Sidetrack source and original artwork are dedicated to the public domain under [CC0 1.0 Universal](LICENSE): copy it, fork it, sell it, remake it, or remove every decision made here.

Bundled Newsreader typeface remains under the SIL Open Font License 1.1. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
