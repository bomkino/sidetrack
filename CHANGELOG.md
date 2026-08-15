# Changelog

Sidetrack follows small, deliberate releases. The page should become quieter and clearer without becoming busier.

## 1.5.0 — 2026-08-15

### A day with edges

- Adds three small, explicit day states: open, away, and closed. `W` steps away; `L` closes the day. Neither state is inferred from missing activity.
- Pauses a moving focus or rest when you step away and remembers that Sidetrack paused it. On return, choose whether the rhythm should resume or stay held.
- Treats screen sleep and a locked macOS session as trustworthy away signals. Waking never starts work on your behalf.
- Archives before closing. A closed page remains visible and reopenable; beginning today clears only the daily page and rhythm while preserving preferences, the north star, counts, and history.
- Tracks “boundary already offered” separately from “Markdown still exact.” Editing a kept-open prior day never nags or auto-archives again, while closing still saves the page people can actually see.
- Remembers a deliberate `Keep this day` across minute ticks and relaunches instead of treating every old date as a new interruption.
- Keeps manual close separate from midnight acknowledgement. Closing and reopening today cannot suppress tomorrow’s first safety archive; reopening an already-old saved page counts as an explicit Keep.
- Safety-archives a page once when the calendar changes, holds any moving rhythm, then waits. Midnight never declares the old day finished or silently replaces it.
- Adds a quiet Day menu and contextual keyboard paths for leaving, returning, closing, reopening, and beginning today.

### Portrait and interaction polish

- Keeps every saved step, thought, and subthought reachable at 640 × 900 and 720 × 1280. Rows use the available height; anything that cannot fit gathers behind one quiet `+ N more` line with native mouse and VoiceOver actions instead of silently disappearing.
- Opens rewrite and add fields over that overflow line, so even an eighth item remains visibly editable on a compact portrait display.
- Removes the overflow label while its editor is open, then restores it afterward; dense portrait edits no longer leave ghosted copy beneath the text field.
- Gives the optional main-first portrait arrangement the full height of its separate main column. Steps and their overflow route stay below the main thought instead of clipping against Today's heading.
- Dims the peripheral page while away or closed, leaving the main thought and the literal return choice readable.
- Gives every day-state choice its own mouse target and stable VoiceOver button. Ordinary task controls become disabled—not missing—while the page is away or closed.
- Prevents the visible `Step Away` menu action from acting like an undocumented return toggle, and disables day actions whose outcomes do not match the current state.
- Keeps lifecycle boundaries out of task undo history. Cmd-Z can no longer reopen a closed page or restart a timer by restoring an older captured state.
- Refreshes a timer deadline before stepping away or closing, so a just-finished phase remains a finished question instead of becoming a resumable zero-minute timer.
- Commits an in-place text edit before export, close, fresh-day reset, midnight hold, or app termination, so the words visible on the page are the words saved.
- Names and dates a manual Markdown export from the page being viewed, even when yesterday is deliberately kept open after midnight.

### Philosophy and performance

- Keeps day awareness entirely local and event-driven. Sidetrack does not read Computer History, Chronicle, app usage, input activity, or the network.
- Keeps the no-nag rule: a fifteen-minute focus extension is one deliberate extension; an unfinished rest may wait. There is no new five-minute chime loop.
- Preserves idle sleep: the final candidate sampled at `0.0%` CPU with stable data-file hash and mtime between inputs.

### Adversarial hardening

- Makes plain JSON recovery semantic as well as syntactic. Readable files with impossible timer deadlines, negative counts, invalid day keys, extreme copy indices, or contradictory away/closed state now keep the person’s words and repair only machine-owned state.
- Lets older files omit the newer lifecycle fields without blanking their task, north star, preferences, or distraction history. A malformed non-content field falls back locally instead of erasing otherwise readable human text.
- Keeps the previous safe page recoverable when the primary file is externally damaged. A valid running timer remains eligible for backup even though its cached minute count naturally ages; corrupt bytes are preserved separately instead of replacing the rollback.
- Makes copy rotation and the distraction clicker total at integer extremes. Hand-edited `Int.min`/`Int.max` values cannot turn the next fresh day or a counter tap into a process crash.
- Formats the distraction count without a 32-bit varargs mismatch, so a readable file containing a large 64-bit value never turns into a negative-looking counter or history row.
- Salvages readable titles around malformed task IDs, completion flags, array entries, and distraction-history values. Duplicate persisted IDs are repaired before the page is drawn, so a later control can never mutate the first item by alias.
- Commits the visible editor before the fresh-day sheet appears, allows non-critical sheets to yield to ordinary app termination, and reuses one Preferences panel instead of retaining a new floating window on every invocation.
- Makes editor commits transactional. Failed retries keep one exact field draft without appending phantom tasks; switching to check, promote, complete, or delete first attaches the draft to its original item.
- Refreshes that retained Preferences panel from the live page before showing it. A presence choice made from the menu bar can no longer be silently reversed by a later edit in a stale panel.
- Cancels app termination when the visible draft cannot be written. The exact words stay on the live page and Sidetrack explains the local write failure instead of exiting with memory-only state.
- Holds every loaded away timer, repairs contradictory finished-phase durations, and rejects sub-minute phase metadata that no Sidetrack rhythm can produce.
- Detaches stale wall-clock deadlines before repairing an away or closed page, so ten held minutes remain ten held minutes even after the app has been closed for hours.
- Defaults only the malformed sibling inside settings, display, timer, and day-state objects. One hand-edited bad value no longer erases the valid choices beside it.
- Makes disabled VoiceOver controls truly inert and rejects Command-, Option-, Control-, and key-repeat events from the bare-key action map.
- Bounds the full-screen transition wait itself. A lost AppKit callback cannot turn the quiet launch retry into a permanent half-second wake-up loop.
- Verifies archive-marker claims against the Markdown bytes on disk before clearing a page. Missing or mismatched recovery files are recreated; a genuine exact archive still deduplicates cleanly.
- Keeps timer state honest even when a midnight draft cannot be saved: the page stays open, but an elapsed phase still becomes its finished question in memory.
- Adds adversarial CI beside the deterministic suite: 256,000 reachable action sequences, exhaustive time-language checks across five time zones, malformed and corrupted file recovery, 606 real AppKit renders from hostile portrait strips to desktop sizes, shipped-font loading, editor/AX presses, and functional bare-key shortcut checks.
- Survived 180 live window resizes, 72 menu tracking events, six full-screen round trips, and six Mission Control transitions around the old AppKit crash neighborhood. Idle returned to `0.0%` CPU and roughly `10.5 MB` RSS after AppKit released its temporary full-screen surfaces.

## 1.4.3 — 2026-08-15

### Portrait display repair

- Removes the 900-point minimum width that made a 720-point portrait display straddle two monitors, crop its right edge, and behave badly around Mission Control.
- Fits the window constraint to its chosen screen before full-screen entry, after a failed transition, and whenever the display arrangement changes.
- Keeps ordinary windowed use above a useful 640 × 900 floor; the page no longer permits the tiny, colliding postcard state exposed during stress testing.
- Verifies the real left-hand 720 × 1280 display in full screen with long main copy, seven steps, a long Today thought, and a Mission Control round trip.

### Quieter extensions

- Gives “Keep working” one useful fifteen-minute extension instead of asking again after five.
- Leaves “Not yet” genuinely open-ended after a rest. Sidetrack does not chime every five minutes; the existing finite overrun whisper remains the only delayed reminder.

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
- Keeps accessibility reading-order assembly simple enough for the older Swift compiler used by the public macOS 14 CI runner.
- Keeps the event-driven runtime: no continuous redraw loop, no network calls, and no data write during an idle minute.
- Preserves the existing local JSON format and application-support location; no migration is required.

## 1.4.1 — 2026-08-08

- Let late timer whispers return to idle after their finite breath instead of holding the display compositor awake.
- Kept the overrun ladder calm: text at 2×, glyph-aware underline at 3×, both at 4×, then silence at 5×.

## 1.4.0 — 2026-08-08

- Added the forgotten-timer whisper, menu-bar presence choices, portrait-first defaults, north star, OLED focus dimming, live display controls, and the current Swiss editorial grid.
