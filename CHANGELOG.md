# Changelog

Sidetrack follows small, deliberate releases. The page should become quieter and clearer without becoming busier.

## 1.4.2 — 2026-08-09

### Timer clarity

- Keeps every finished-focus and finished-rest choice on the same typographic edge as the main thought and timer state, including right-aligned portrait layouts.
- Gives each visible choice its own click target and VoiceOver action: begin the rest, keep working, start focus, or stay where you are.
- Lifts the pause/resume invitation from near-invisible to quietly readable while preserving the low-luminance hierarchy.

### North star and keyboard care

- Restricts the shortcut whisper to the distraction count itself. Hovering the north star no longer hides it or unexpectedly opens the shortcut map.
- Renames visible “One Thing” actions and Markdown output to the gentler “north star”; stored data remains unchanged.
- Clarifies the hover map’s `R` shortcut as “fresh day,” matching its confirmed behavior and confirmation step.
- Audits the documented bare-key controls, finished-phase keys, menu equivalents, and full-screen commands against the implemented handlers, removing one undocumented duplicate completion key.

### Accessibility

- Gives the custom-drawn page a stable VoiceOver reading order instead of presenting it as one opaque canvas.
- Exposes the shifted date and time, main thought, steps, Today thoughts and subthoughts, timer states and choices, distraction count, north star, and “hold a thought” action.
- Adds semantic custom actions for rewriting, checking, completing, deleting, promoting, adding steps, undoing a distraction, and rewriting the north star.
- Reuses accessibility elements across redraws so focus does not jump when the minute changes.

### Fit and finish

- Makes preference scale readouts exact (`1.15x`, `1.25x`, and so on) instead of rounding away meaningful differences.
- Uses the same language in the Task menu as the page: main thought, next thought, and complete main thought.
- Shortens the frequent counter-hover fade to a restrained 180 ms and continues to respect Reduce Motion.

### Compatibility and performance

- Builds one universal application containing native Apple-silicon and Intel slices.
- Pins both slices to the promised macOS 13 deployment target and makes the build fail if either architecture or target disappears.
- Keeps the event-driven runtime: no continuous redraw loop, no network calls, and no data write during an idle minute.
- Preserves the existing local JSON format and application-support location; no migration is required.

## 1.4.1 — 2026-08-08

- Let late timer whispers return to idle after their finite breath instead of holding the display compositor awake.
- Kept the overrun ladder calm: text at 2×, glyph-aware underline at 3×, both at 4×, then silence at 5×.

## 1.4.0 — 2026-08-08

- Added the forgotten-timer whisper, menu-bar presence choices, portrait-first defaults, north star, OLED focus dimming, live display controls, and the current Swiss editorial grid.
