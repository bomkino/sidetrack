# Sidetrack 1.5.0 — Gauntlet ledger

## Actual goal

Make Sidetrack a calmer place to begin, leave, return, and close a working day without turning it into a tracker, dashboard, or system to maintain.

## Frozen acceptance bar

- One explicit, persisted day state: open, away, or closed.
- `Step Away` pauses a running focus or rest and remembers whether it was running.
- Returning never happens automatically. One explicit choice may resume; another returns paused.
- Screen lock or display sleep may mark the page away. Missing, stale, or absent activity data never does.
- Closing the day archives the readable Markdown page before changing state, pauses any running timer, and keeps the page recoverable.
- A calendar boundary never silently declares the day finished. The prior day is safety-archived once, remains intact, and offers `Begin today` or `Keep this day`.
- Beginning today clears the daily page and timer, advances the placeholder bank, and preserves preferences, distraction history, and the north star.
- The normal focus page gains no permanent dashboard, timeline, score, activity feed, network dependency, or polling loop.
- Every new state is operable by mouse, keyboard, menus, and VoiceOver with literal copy and a predictable outcome.
- The 720 × 1280 portrait page, Mission Control/full-screen behavior, local JSON recovery, universal build, macOS 13 target, and idle event-driven architecture do not regress.

## Protected baseline

- Source baseline: existing uncommitted 1.4.3 repair on Git `82c91d1af600b7a096119e9e297600ee123a8ed5`.
- Baseline source/test/script/resource digest: `6d5a8ffab861caa70ec28902988912ab8298632b30adb32d12427372cd0aebea`.
- Baseline tests: `192 / 192`.
- Existing local 1.4.3 portrait, accessibility, timer-extension, packaging, and universal-build repairs are protected material.

## Evidence required to hold

- Deterministic transition, migration, archive-boundary, timer, and regression tests.
- Clean native build, strict signature, `arm64 + x86_64`, macOS 13 minimum, and wrapper-preserving ZIP.
- Live 720 × 1280 portrait checks for open, away, closed, next-day, long-copy, and return choices.
- Live screen-lock/sleep notification path where practical; otherwise a bounded notification-harness result labelled accurately.
- Keyboard and VoiceOver semantic audit of every new action.
- Mission Control/full-screen round trip and rapid-resize check.
- Idle CPU and stable-memory sample; no continuous animation or sub-minute polling.
- One final fresh-context critic verdict of `holds`.

## Attempt policy

- Maximum three builder/critic rounds.
- Repair only decisive failures against this bar.
- Do not commit, push, merge, publish, release, or replace GitHub state without separate authority.

## Rounds

### Round 0 — define

- Computer History reported itself running while its event stream was over an hour stale. Conclusion: missing activity is not reliable presence evidence.
- Chronicle/TimeKeeper pattern: explicit start, break, and sleep boundaries; stale evidence fails closed.
- Carry pattern: ask rather than watch, preserve the way back, make interruption non-punitive, and keep shutdown reopenable.
- Candidate architecture: event-driven local day state plus macOS lock/sleep hints only.

### Round 1 — build and inspect

- Added a Codable `DaySession` and pure `DayEngine` for open, away, closed, return ownership, safety archive, and fresh-day preservation.
- Added literal on-page choices, contextual keys, a Day menu, VoiceOver actions, and macOS screen-sleep/session-lock wiring. Wake never resumes.
- Added 16 deterministic lifecycle and migration assertions; total suite is now `208 / 208`.
- Live portrait inspection caught one choice-layout ordering bug that piled return copy before rectangles were measured. Repaired before acceptance.
- Live 640 × 900 inspection caught seven-step clipping. Repaired by tightening only supporting steps below 1120 points; all seven now remain visible while the main thought keeps its scale.
- Live menu review caught an ambiguous `Step Away` fallback that could return instead. Removed the hidden toggle and made lifecycle menu availability match the current state.
- The pre-critic source audit caught an in-process midnight gap: a running app archived the old page but offered the boundary question only after relaunch. The minute boundary now pauses into the same intact away state immediately, but only after the archive succeeds.
- Verified old-open launch becomes away, safety-archives exactly once, and does not create a duplicate on relaunch.
- Verified open, away, closed, prior-day, begin-today, long-copy, seven-step, 640 × 900, 720 × 1280, full-screen, and Mission Control surfaces on the real left portrait display.
- Verified away-state VoiceOver semantics: peripheral controls remain discoverable but disabled; the two return/close choices remain enabled and expose literal help.
- Six settled idle samples reported `0.0%` CPU. RSS settled from 26.6 MB to 12.3 MB; the JSON hash and mtime did not change.

### Round 2 — fresh critic repair

- Fresh critic found that a safety-archived old page could be reopened, edited, stepped away from, and closed while still trusting the stale pre-edit Markdown. Archive-bearing content now invalidates the marker; timer/layout/lifecycle-only changes do not.
- Fresh critic found that lifecycle transitions registered whole-state undo closures. Older task undo could therefore restore an open running timer from an away or closed page. Lifecycle transitions now clear the old undo boundary and use their visible return/reopen path instead.
- Fresh critic found an elapsed-deadline race: stepping away or closing just after zero could preserve a paused zero timer and later restart a full phase. Both transitions now refresh first; finished work/rest remains an awaiting-choice state and never acquires resume ownership.
- Fresh critic found archive/reset and the new minute-boundary path could snapshot while a visible in-place editor still held newer text. Export, boundary archive, reset, close, and termination now commit that field before their durable action; the fresh-day snapshot is taken only afterward.
- Live regression reproduced the full stale-archive path: marked snapshot → rewrite → start focus → step away → Cmd-Z → close → Cmd-Z. The marker cleared on rewrite; both undo attempts left the boundary and paused timer intact; the new `2026-08-15-2.md` contains the rewritten sentence and all seven steps.
- Builder’s final archive audit caught manual export still naming an intentionally open prior-day page with today’s date. Export now derives both filename and Markdown heading/count from `activeDayKey`.
- Fresh critic caught the first dirty-marker repair overloading one key: Keep yesterday → edit → next minute would archive and ask again. The persisted boundary-offered key now remains stable, while a separate exact-snapshot key alone is invalidated by page content. Keep stays kept; close still writes the newer page.
- The same review caught the minute callback still committing any editor on an acknowledged old day. Editor commit is now gated by `needsSafetyArchive`: the first boundary is made durable; choosing Keep restores uninterrupted editing afterward.
- Launch uses that same pending-boundary predicate. A deliberate Keep survives relaunch instead of being reinterpreted as a fresh away event solely because the page date is old.
- Fresh critic then found manual close was still manufacturing the boundary-offered key. Close now records only an exact archive; close → reopen → edit still receives tomorrow’s first boundary. Reopening an already-old closed page explicitly acknowledges that visible choice.
- Bounded AppKit notification harness compiled the real `AppDelegate`, `FocusView`, and production views against `SidetrackCore`, launched with an isolated JSON file, posted `NSWorkspace.screensDidSleepNotification`, then `screensDidWakeNotification`. Receipt: `PASS: screensDidSleep -> away+paused; screensDidWake -> still away+paused`. Persisted state after wake remained `away`, `resumeTimerOnReturn: true`, timer `paused`, with 2,399 seconds preserved. Harness and receipt data live under `build/qa/notification-harness/`; no actual user session was locked.

### Round 3 — Actual Goal adversarial pass

- Rejected the deterministic suite, compiler, static screenshots, and prior `holds` verdict as sufficient proof. New tests target the costly false wins: readable-but-impossible JSON, random reachable sequences, exact editor commits, real AX presses, true shipped-font geometry, process churn, and source/build/install/public divergence.
- The first randomized run found release-mode traps in copy-bank rotation at `Int.max` and negative history lengths. The malformed-file run then reproduced lost recovery points, impossible running/closed state, negative counts, invalid day keys, and older lifecycle fields blanking human text.
- A real AppKit harness reproduced six retained Preferences panels, stale text behind the fresh-day sheet, a modal termination blocker, and a maximum distraction-count trap. Each received a causal repair and permanent regression.
- The final critic rejected row-count screenshots as reachability proof. The former hard caps could persist an eighth item while hiding it from drawing, hit-testing, and VoiceOver; compact portrait now exposes every remainder through one native overflow route, including visible on-page editors for hidden items.
- Failure injection found creation commits mutating memory before disk. Repeated Enter or quit attempts could therefore append the same unsaved thought twice. Commits are now transactional, field teardown is re-entrancy-safe, and recovered storage creates exactly one item.
- Retained whole-state undo snapshots could rewind later timer, preference, counter, or fresh-day choices. Task undo now restores only the page fields it changed; day boundaries clear the older undo boundary and keep their explicit visible recovery path.
- Malformed item IDs, completion flags, one bad array element, and duplicate UUIDs could still erase words or alias controls. Field-level salvage now keeps readable neighbours and normalizes every live task/subtask identity before AppKit sees it.
- A fabricated exact-archive marker could clear a closed page after its Markdown was deleted or changed. Sidetrack now compares the claimed archive with the current rendered bytes before deduplicating; missing or mismatched recovery is written again.
- A forced midnight save failure once prevented the timer refresh as well as the archive. The page still fails closed, while elapsed focus/rest state now reaches its correct awaiting choice in memory.
- Final independent stress receipts before packaging: `2,041,154` core assertions over `256,000` reachable transitions; `865` AppKit assertions over `606` real renders; AddressSanitizer repeated the full core stress without a memory violation.
- The final visual critic caught two dense-state defects outside the happy-path portrait: hidden-item editors left the `+ N more` label ghosted beneath the field, and the optional main-first portrait arrangement clipped every main step against Today's heading. Overflow copy and semantics now yield to the live editor; main-first keeps the full height of its separate main column. Both 640 × 900 and 720 × 1280 arrangements have direct-step, overflow, in-bounds, and editor-restoration regressions. The fresh visual verdict is `holds`.
- The final state critic then found loaded away/closed timers were canonicalized against stale wall time before the explicit hold was enforced. A deadline hours in the past could finish an away timer; a future one could consume held seconds. Non-open pages now detach that deadline first, then repair the persisted seconds. Past and future regressions cover away ownership and closed-state clearing.
- Live process stress covered `180` resizes, `72` menu-tracking events, six full-screen round trips, and six Mission Control transitions. The prior v1.4.2 macOS/ViewBridge crash did not reproduce. RSS peaked while AppKit owned full-screen surfaces, then settled near `10.5 MB`; CPU returned to `0.0%`.
- `leaks` reported about `20 KB`, rooted in macOS Link/AppIntents XPC and accessibility weak-reference containers rather than Sidetrack-owned objects. That is recorded as framework evidence, not falsely claimed as zero leaked bytes.

### Final verify

- Frozen candidate source digest: `45dd31003bf9c6cfe6f04599d9d07f1e9af6235e1fd6d06d8297d5aee1cedac9`. Scope: sorted files under `.github`, `Assets`, `Resources`, `Scripts`, `Sources`, and `Tests`, reduced from each file's SHA-256.
- Deterministic suite: `251 / 251`.
- Core stress: `2,041,154` assertions across `256,000` randomized actions; the same suite passed under AddressSanitizer.
- AppKit stress: `865` assertions across `606` rendered layouts.
- Candidate app and ZIP-stream executable SHA-256: `17cab1b483ce6f1d175d900edb7d1ede07c5013a7d22a7dd3bc324a767fc653c`; ZIP SHA-256: `f88ac69534b15a26e25bd61cbee2ba5191c04854e1e9233d38a718367422c0e0`.
- Strict ad-hoc signature integrity, `1.5.0` build `8`, `x86_64 + arm64`, macOS `13.0` minimum on both slices, and a clean 12-entry wrapper-preserving ZIP. No TeamIdentifier or notarization is claimed.
- Fresh-context visual critic: `holds`. Fresh-context release critic: `holds` on this exact repaired snapshot and package pair.
- The exact build is the sole `/Applications/Sidetrack.app`, launched and visually verified full-screen on the real left portrait display with the human page preserved. GitHub main/latest release remain the older public state; CI, push, and release readbacks are pending and must be recorded only after they happen.
