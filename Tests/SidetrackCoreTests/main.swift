import Foundation
import SidetrackCore

private var checks = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 17, minute: 16))!
expect(TimeLanguage.clock(date, calendar: calendar) == "Friday, quarter past five", "clock uses calm bucket")
expect(TimeLanguage.dateLine(date, calendar: calendar) == "Friday, 17 July", "date has its own quiet line")
expect(TimeLanguage.compactDateLine(date, calendar: calendar) == "Fri, 17 Jul", "compact windows keep the date readable")

expect(TimeLanguage.timer(seconds: 25 * 60) == "~25 minutes left", "timer rounds to 25 minutes")
expect(TimeLanguage.timer(seconds: 20 * 60) == "~20 minutes left", "timer stays approximate")
expect(TimeLanguage.timer(seconds: 2 * 60) == "a few minutes left", "timer hides precision near end")
expect(TimeLanguage.rhythmLine(phase: .work, status: .idle, seconds: 50 * 60, settings: PomodoroSettings()) == "Ready  ·  50-minute focus", "idle state says exactly what can begin")
expect(TimeLanguage.rhythmLine(phase: .work, status: .running, seconds: 50 * 60, settings: PomodoroSettings()) == "Focus, underway  ·  ~50 minutes left", "running focus is explicit")
expect(TimeLanguage.rhythmLine(phase: .work, status: .paused, seconds: 50 * 60, settings: PomodoroSettings()) == "Focus paused  ·  ~50 minutes left", "paused focus uses the literal state")
expect(TimeLanguage.rhythmLine(phase: .shortBreak, status: .running, seconds: 12 * 60, settings: PomodoroSettings()) == "Short rest, underway  ·  ~12 minutes left", "short rest names its own countdown")
expect(TimeLanguage.rhythmLine(phase: .longBreak, status: .running, seconds: 30 * 60, settings: PomodoroSettings()) == "Long rest, underway  ·  half an hour left", "long rest names its own countdown")

expect(CopyBank.mainPrompt(index: 0) == "what are you returning to?", "first placeholder offers a quiet way back in")
expect(CopyBank.mainPrompt(index: CopyBank.next(0)) != CopyBank.mainPrompt(index: 0), "fresh day advances the copy bank")
expect(AppData.firstRun.mainTask == nil && AppData.firstRun.today.isEmpty, "first launch begins as the user’s empty page")
expect(AppData.firstRun.oneThing.isEmpty, "One Thing begins as a quiet invitation")
expect(CopyBank.oneThingPrompt(index: 0) == "a small north star", "One Thing has a human placeholder")

let late = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 23, minute: 50))!
let offsetLate = TimeLanguage.adjusted(late, offsetMinutes: 15)
expect(TimeLanguage.dateLine(offsetLate, calendar: calendar) == "Saturday, 18 July", "+15 display clock crosses midnight calmly")
expect(TimeLanguage.clockPhrase(offsetLate, calendar: calendar) == "twelve o’clock", "offset clock uses the adjusted day")
let ten = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 10))!
expect(TimeLanguage.dayPhase(ten, calendar: calendar) == "morning", "ten o’clock still belongs to morning")
let midday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 12))!
expect(TimeLanguage.dayPhase(midday, calendar: calendar) == "midday", "midday stays plain and readable")

for hour in 0..<24 {
    let phased = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: hour))!
    expect(!TimeLanguage.dayPhase(phased, calendar: calendar).isEmpty, "every hour has poetic day language")
}
expect(TimeLanguage.dayPhase(date, calendar: calendar) == "late light", "late afternoon has its own language")

for hour in 0..<24 {
    let shifted = BurnInShift.offset(at: date.addingTimeInterval(TimeInterval(hour * 3600)))
    expect(abs(shifted.x) <= 2.2 && abs(shifted.y) <= 1.8, "burn-in drift never becomes visible motion")
}

for minute in 0..<60 {
    let mapped = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 17, minute: minute))!
    let phrase = TimeLanguage.clockPhrase(mapped, calendar: calendar)
    expect(!phrase.contains("about") && !phrase.contains(":"), "every clock minute maps to spoken calm language")
}

let now = Date(timeIntervalSince1970: 1_000)
var workTimer = FocusTimer(status: .running, remainingSeconds: 60, endsAt: now)
expect(TimerEngine.refresh(&workTimer, now: now) == .workEnded, "work end emits event")
expect(workTimer.status == .awaitingWorkChoice, "work waits for choice")
expect(workTimer.endsAt == nil, "work does not auto-start break")
expect(workTimer.phaseEndedAt == now, "work remembers the exact phase finish")

var breakTimer = FocusTimer(phase: .shortBreak, status: .running, remainingSeconds: 60, endsAt: now)
expect(TimerEngine.refresh(&breakTimer, now: now) == .breakEnded, "break end emits event")
expect(breakTimer.status == .awaitingBreakChoice, "break does not auto-restart")

let phaseEnd = Date(timeIntervalSince1970: 2_000)
let overrunDuration = 50
let waitingWork = FocusTimer(
    status: .awaitingWorkChoice,
    remainingSeconds: 0,
    phaseDurationSeconds: overrunDuration,
    phaseEndedAt: phaseEnd
)
expect(TimerEngine.overrunCue(waitingWork, now: phaseEnd.addingTimeInterval(49)) == .none, "overrun stays quiet before twice the phase")
expect(TimerEngine.overrunCue(waitingWork, now: phaseEnd.addingTimeInterval(50)) == .pulse, "twice the phase begins a soft pulse")
expect(TimerEngine.overrunCue(waitingWork, now: phaseEnd.addingTimeInterval(100)) == .underline, "three times the phase adds an underline")
expect(TimerEngine.overrunCue(waitingWork, now: phaseEnd.addingTimeInterval(150)) == .pulseAndUnderline, "four times the phase combines both cues")
expect(TimerEngine.overrunCue(waitingWork, now: phaseEnd.addingTimeInterval(200)) == .quiet, "five times the phase goes quiet for a likely AFK state")
let waitingRest = FocusTimer(
    phase: .shortBreak,
    status: .awaitingBreakChoice,
    remainingSeconds: 0,
    phaseDurationSeconds: 12 * 60,
    phaseEndedAt: phaseEnd
)
expect(TimerEngine.overrunCue(waitingRest, now: phaseEnd.addingTimeInterval(12 * 60)) == .pulse, "the same cue ladder works for short rest")

var mismatchedWorkChoice = FocusTimer(
    phase: .shortBreak,
    status: .awaitingWorkChoice,
    remainingSeconds: 0,
    phaseDurationSeconds: 12 * 60,
    phaseEndedAt: phaseEnd
)
TimerEngine.repairLoadedState(&mismatchedWorkChoice, settings: PomodoroSettings(), now: now)
expect(mismatchedWorkChoice.phase == .work, "a work-finished question repairs a contradictory rest phase")
expect(mismatchedWorkChoice.phaseDurationSeconds == 50 * 60, "a repaired work question uses the focus duration")

var mismatchedBreakChoice = FocusTimer(
    phase: .work,
    status: .awaitingBreakChoice,
    remainingSeconds: 0,
    phaseDurationSeconds: 50 * 60,
    phaseEndedAt: phaseEnd
)
TimerEngine.repairLoadedState(&mismatchedBreakChoice, settings: PomodoroSettings(), now: now)
expect(mismatchedBreakChoice.phase == .shortBreak, "a rest-finished question repairs a contradictory work phase")
expect(mismatchedBreakChoice.phaseDurationSeconds == 12 * 60, "a repaired rest question uses the rest duration")

for impossibleDuration in [1, 59] {
    var tinyDuration = FocusTimer(
        phase: .work,
        status: .paused,
        remainingSeconds: 10 * 60,
        phaseDurationSeconds: impossibleDuration
    )
    TimerEngine.repairLoadedState(&tinyDuration, settings: PomodoroSettings(), now: now)
    expect(tinyDuration.phaseDurationSeconds == 50 * 60, "sub-minute phase duration \(impossibleDuration) is not a reachable timer phase")
}

var cycleTimer = FocusTimer(status: .awaitingWorkChoice, remainingSeconds: 0, completedCyclesInSet: 3)
TimerEngine.takeBreak(&cycleTimer, settings: PomodoroSettings(cyclesPerSet: 4), now: now)
expect(cycleTimer.phase == .longBreak, "long break follows configured cycle count")
expect(cycleTimer.completedCyclesInSet == 0, "cycle set resets after long break")

var shortRestTimer = FocusTimer(status: .awaitingWorkChoice, remainingSeconds: 0)
TimerEngine.takeBreak(&shortRestTimer, settings: PomodoroSettings(), now: now)
expect(shortRestTimer.phase == .shortBreak && shortRestTimer.status == .running, "choosing a short rest starts a distinct timer")
expect(shortRestTimer.remainingSeconds == 12 * 60, "short rest receives the full configured countdown")

var extendedFocus = FocusTimer(status: .awaitingWorkChoice, remainingSeconds: 0)
TimerEngine.keepWorking(&extendedFocus, now: now)
expect(extendedFocus.status == .running && extendedFocus.phase == .work, "keep working begins a distinct focus extension")
expect(extendedFocus.remainingSeconds == 15 * 60, "focus extension leaves a useful quarter-hour before asking again")
expect(extendedFocus.endsAt == now.addingTimeInterval(15 * 60), "focus extension has one calm, explicit finish")

let defaults = PomodoroSettings()
expect(defaults.workMinutes == 50, "default focus is 50 minutes")
expect(defaults.breakMinutes == 12, "default break is 12 minutes")
expect(defaults.cyclesPerSet == 3, "default set contains three cycles")
expect(defaults.longBreakMinutes == 30, "default long break is 30 minutes")
expect(defaults.clockOffsetMinutes == 15, "default display clock is fifteen minutes ahead")
let displayDefaults = DisplaySettings()
expect(displayDefaults.placement == .left, "default second screen is left of main")
expect(displayDefaults.orientation == .vertical, "default composition is vertical")
expect(displayDefaults.panelSide == .right, "default Today list stays on the right")
expect(displayDefaults.alignment == .center, "default text alignment uses balanced edges")
expect(displayDefaults.panelOrder == .todayFirst, "default page gives Today and the counter the top register")
expect(displayDefaults.presence == .both, "default presence keeps Dock and menu bar access")
expect(displayDefaults.dateScale > 1 && displayDefaults.timerScale > 1, "default time is comfortably larger than the old baseline")
var oversizedDisplay = DisplaySettings(mainScale: 9, timerScale: 0.1, todayScale: 2, stepsScale: -1, dateScale: 1.8, counterScale: 0.2)
oversizedDisplay.normalize()
expect(oversizedDisplay.mainScale == 1.35 && oversizedDisplay.timerScale == 0.75, "component scales stay inside their calm bounds")
expect(oversizedDisplay.stepsScale == 0.75 && oversizedDisplay.dateScale == 1.35, "all component scales normalize")
let legacyAppData = try! JSONDecoder().decode(AppData.self, from: Data("{\"today\":[],\"settings\":{}}".utf8))
expect(legacyAppData.display == DisplaySettings(), "older day files receive display defaults")
let oldDisplay = try! JSONDecoder().decode(DisplaySettings.self, from: Data("{\"placement\":\"left\",\"orientation\":\"vertical\",\"panelSide\":\"right\",\"oledDimEnabled\":false,\"mainScale\":1,\"timerScale\":1,\"todayScale\":1,\"stepsScale\":1,\"dateScale\":1,\"counterScale\":1}".utf8))
expect(oldDisplay.alignment == .center && oldDisplay.panelOrder == .todayFirst, "old display settings gain tasteful layout defaults")
expect(oldDisplay.presence == .both, "old display settings keep both macOS access points")
expect(oldDisplay.dateScale > 1 && oldDisplay.todayScale > 1, "old untouched display settings gain readable scale")
let legacySettings = try! JSONDecoder().decode(PomodoroSettings.self, from: Data("{\"workMinutes\":25,\"breakMinutes\":5,\"longBreakMinutes\":30,\"cyclesPerSet\":4,\"chimeEnabled\":false}".utf8))
expect(legacySettings.clockOffsetMinutes == 15, "older settings migrate to the preferred clock offset")

let partialSettings = try! JSONDecoder().decode(
    PomodoroSettings.self,
    from: Data(#"{"workMinutes":75,"breakMinutes":15,"longBreakMinutes":40,"cyclesPerSet":5,"chimeEnabled":"sometimes","clockOffsetMinutes":20}"#.utf8)
)
expect(partialSettings.workMinutes == 75 && partialSettings.breakMinutes == 15 && partialSettings.longBreakMinutes == 40,
       "one malformed settings field does not erase valid custom durations")
expect(partialSettings.cyclesPerSet == 5 && partialSettings.clockOffsetMinutes == 20 && !partialSettings.chimeEnabled,
       "settings repair defaults only the malformed sibling")

let partialDisplay = try! JSONDecoder().decode(
    DisplaySettings.self,
    from: Data(#"{"placement":"right","orientation":"horizontal","panelSide":"left","alignment":"right","panelOrder":"mainFirst","presence":"menuBar","oledDimEnabled":true,"mainScale":1.2,"timerScale":1.1,"todayScale":1.0,"stepsScale":0.95,"dateScale":1.3,"counterScale":"large"}"#.utf8)
)
expect(partialDisplay.placement == .right && partialDisplay.orientation == .horizontal && partialDisplay.panelSide == .left,
       "one malformed display field does not erase valid layout choices")
expect(partialDisplay.alignment == .right && partialDisplay.panelOrder == .mainFirst && partialDisplay.presence == .menuBar,
       "display repair preserves explicit alignment, order, and presence")
expect(abs(partialDisplay.mainScale - 1.2) < 0.001 && abs(partialDisplay.dateScale - 1.3) < 0.001,
       "display repair preserves valid sibling scales")

let partialTimer = try! JSONDecoder().decode(
    FocusTimer.self,
    from: Data(#"{"phase":"shortBreak","status":"paused","remainingSeconds":719,"completedCyclesInSet":2,"phaseDurationSeconds":"twelve"}"#.utf8)
)
expect(partialTimer.phase == .shortBreak && partialTimer.status == .paused && partialTimer.remainingSeconds == 719,
       "one malformed timer field does not reset a valid paused rest")
expect(partialTimer.completedCyclesInSet == 2 && partialTimer.phaseDurationSeconds == nil,
       "timer repair defaults only the malformed sibling")

let partialDay = try! JSONDecoder().decode(
    DaySession.self,
    from: Data(#"{"status":"away","resumeTimerOnReturn":true,"safetyArchivedDayKey":17,"exactArchiveDayKey":"2026-07-17"}"#.utf8)
)
expect(partialDay.status == .away && partialDay.resumeTimerOnReturn,
       "one malformed day marker does not reopen an explicit away page")
expect(partialDay.safetyArchivedDayKey == nil && partialDay.exactArchiveDayKey == "2026-07-17",
       "day repair defaults only the malformed marker")
var resetTimer = FocusTimer(phase: .longBreak, status: .running, remainingSeconds: 10, endsAt: now, completedCyclesInSet: 2)
TimerEngine.reset(&resetTimer, settings: defaults)
expect(resetTimer.phase == .work && resetTimer.status == .idle, "timer reset returns to idle work")
expect(resetTimer.remainingSeconds == 50 * 60, "timer reset restores configured work duration")
var pausedTimer = FocusTimer(status: .paused, remainingSeconds: 17 * 60)
TimerEngine.resetDurationIfIdle(&pausedTimer, settings: PomodoroSettings(workMinutes: 60))
expect(pausedTimer.remainingSeconds == 17 * 60, "preferences never reset a paused session")
var idleTimer = FocusTimer(status: .idle, remainingSeconds: 50 * 60)
TimerEngine.resetDurationIfIdle(&idleTimer, settings: PomodoroSettings(workMinutes: 60))
expect(idleTimer.remainingSeconds == 60 * 60, "new duration applies while the timer is idle")

expect(legacyAppData.day == DaySession(), "older day files migrate to an open, non-tracking day state")
let singleMarkerDay = try! JSONDecoder().decode(
    DaySession.self,
    from: Data("{\"status\":\"away\",\"resumeTimerOnReturn\":false,\"safetyArchivedDayKey\":\"2026-07-17\"}".utf8)
)
expect(singleMarkerDay.exactArchiveDayKey == nil, "single-marker day files migrate without pretending their Markdown is exact")
var awayDay = AppData(
    mainTask: TaskItem(title: "Keep the honest edge"),
    oneThing: "$10k",
    timer: FocusTimer(status: .running, remainingSeconds: 40 * 60, endsAt: now.addingTimeInterval(40 * 60)),
    distractionsByDay: ["2026-07-17": 3],
    activeDayKey: "2026-07-17"
)
DayEngine.stepAway(&awayDay, now: now)
expect(awayDay.day.status == .away, "stepping away becomes an explicit persisted state")
expect(awayDay.timer.status == .paused && awayDay.timer.remainingSeconds == 40 * 60, "stepping away pauses a running timer without losing time")
expect(awayDay.day.resumeTimerOnReturn, "Sidetrack remembers that it—not the person—paused the timer")

var expiredAway = AppData(
    timer: FocusTimer(
        phase: .work,
        status: .running,
        remainingSeconds: 1,
        endsAt: now.addingTimeInterval(-1),
        phaseDurationSeconds: 50 * 60
    )
)
DayEngine.stepAway(&expiredAway, now: now)
expect(expiredAway.timer.status == .awaitingWorkChoice, "stepping away refreshes an elapsed deadline into its finished question")
expect(!expiredAway.day.resumeTimerOnReturn, "an elapsed timer never acquires return-and-resume ownership")
DayEngine.returnToDay(&expiredAway, resumeTimer: true, now: now)
expect(expiredAway.timer.status == .awaitingWorkChoice, "returning cannot turn an elapsed zero timer into a fresh full phase")

var returnedPaused = awayDay
DayEngine.returnToDay(&returnedPaused, resumeTimer: false, now: now)
expect(returnedPaused.day.status == .open && returnedPaused.timer.status == .paused, "returning paused never restarts time")
expect(!returnedPaused.day.resumeTimerOnReturn, "a return choice clears the one-shot resume intention")

var returnedRunning = awayDay
DayEngine.returnToDay(&returnedRunning, resumeTimer: true, now: now)
expect(returnedRunning.day.status == .open && returnedRunning.timer.status == .running, "an explicit return-and-resume choice restarts the held timer")
expect(returnedRunning.timer.endsAt == now.addingTimeInterval(40 * 60), "return-and-resume rebuilds the deadline from preserved time")

var closedDay = returnedRunning
DayEngine.close(&closedDay, now: now)
expect(closedDay.day.status == .closed && closedDay.timer.status == .paused, "closing a day pauses time and leaves a reversible closed page")
expect(closedDay.day.safetyArchivedDayKey == nil, "closing today never pretends that a future calendar boundary was offered")
expect(closedDay.day.exactArchiveDayKey == "2026-07-17", "a closed day records that its Markdown matches the visible page")

var expiredClose = AppData(
    timer: FocusTimer(
        phase: .shortBreak,
        status: .running,
        remainingSeconds: 1,
        endsAt: now.addingTimeInterval(-1),
        phaseDurationSeconds: 12 * 60
    )
)
DayEngine.close(&expiredClose, now: now)
expect(expiredClose.timer.status == .awaitingBreakChoice, "closing refreshes an elapsed rest instead of preserving a resumable zero timer")

let nextDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9))!
var reopenedBeforeBoundary = AppData(
    mainTask: TaskItem(title: "A page that may continue"),
    day: DaySession(status: .closed, exactArchiveDayKey: "2026-07-17"),
    activeDayKey: "2026-07-17"
)
DayEngine.returnToDay(&reopenedBeforeBoundary, resumeTimer: false, now: date, calendar: calendar)
var changedBeforeBoundary = reopenedBeforeBoundary
changedBeforeBoundary.mainTask?.title = "A page changed before midnight"
DayEngine.invalidateSafetyArchiveIfPageChanged(&changedBeforeBoundary, comparedTo: reopenedBeforeBoundary)
expect(DayEngine.needsSafetyArchive(changedBeforeBoundary, now: nextDay, calendar: calendar), "close, reopen, edit, then midnight still receives its first boundary archive")

var reopenedAfterBoundary = AppData(
    day: DaySession(status: .closed, exactArchiveDayKey: "2026-07-17"),
    activeDayKey: "2026-07-17"
)
DayEngine.returnToDay(&reopenedAfterBoundary, resumeTimer: false, now: nextDay, calendar: calendar)
expect(reopenedAfterBoundary.day.safetyArchivedDayKey == "2026-07-17", "reopening a saved older page acknowledges its already-visible calendar choice")

var boundaryDay = awayDay
boundaryDay.day.safetyArchivedDayKey = nil
expect(DayEngine.needsSafetyArchive(boundaryDay, now: nextDay, calendar: calendar), "an open earlier working day receives one safety archive")
boundaryDay.day.safetyArchivedDayKey = boundaryDay.activeDayKey
boundaryDay.day.exactArchiveDayKey = boundaryDay.activeDayKey
expect(!DayEngine.needsSafetyArchive(boundaryDay, now: nextDay, calendar: calendar), "the calendar boundary does not create repeated archive copies")

var editedAfterArchive = boundaryDay
editedAfterArchive.day.status = .open
let archivedSnapshot = editedAfterArchive
editedAfterArchive.mainTask = TaskItem(title: "A truer sentence after midnight")
DayEngine.invalidateSafetyArchiveIfPageChanged(&editedAfterArchive, comparedTo: archivedSnapshot)
expect(editedAfterArchive.day.exactArchiveDayKey == nil, "editing a reopened page invalidates its older exact archive")
expect(editedAfterArchive.day.safetyArchivedDayKey == editedAfterArchive.activeDayKey, "editing does not forget that the calendar boundary was already offered")
expect(!DayEngine.needsSafetyArchive(editedAfterArchive, now: nextDay, calendar: calendar), "keeping and editing an older day never triggers another automatic archive prompt")

var timerOnlyChange = boundaryDay
let timerArchiveSnapshot = timerOnlyChange
timerOnlyChange.timer.remainingSeconds -= 60
DayEngine.invalidateSafetyArchiveIfPageChanged(&timerOnlyChange, comparedTo: timerArchiveSnapshot)
expect(timerOnlyChange.day.exactArchiveDayKey == timerOnlyChange.activeDayKey, "timer-only changes keep an exact page archive current")

var freshDay = awayDay
freshDay.today = [TaskItem(title: "A later thought")]
DayEngine.beginFreshDay(&freshDay, dayKey: "2026-07-18")
expect(freshDay.day == DaySession() && freshDay.activeDayKey == "2026-07-18", "beginning today opens a clean explicit day")
expect(freshDay.mainTask == nil && freshDay.today.isEmpty, "beginning today clears only the daily page")
expect(freshDay.oneThing == "$10k" && freshDay.distractionsByDay["2026-07-17"] == 3, "a new day preserves the north star and earlier distraction history")
expect(freshDay.timer.status == .idle && freshDay.timer.remainingSeconds == defaults.workMinutes * 60, "a new day begins with a fresh configured rhythm")

let exportSample = AppData(
    mainTask: TaskItem(
        title: "Shape the opening until it breathes",
        subtasks: [Subtask(title: "Watch once without reaching for the controls")]
    ),
    oneThing: "$10k"
)
let exported = MarkdownExporter.render(exportSample, date: date, calendar: calendar)
expect(exported.contains("# Friday, 17 July 2026"), "Markdown export has day heading")
expect(exported.contains("- [ ] Shape the opening until it breathes"), "Markdown export contains main thought")
expect(exported.contains("  - [ ] Watch once without reaching for the controls"), "Markdown export contains subthoughts")
expect(exported.contains("North star: $10k"), "Markdown export carries the persistent north star")
expect(exported.contains("## Distractions\n0"), "Markdown export contains daily distraction count")

let longOneThing = AppData(oneThing: "1234567890123456789012345")
expect(longOneThing.oneThing.count == 20, "One Thing stays within its glanceable twenty-character promise")

let testDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build/test-output/\(UUID().uuidString)")
let store = DataStore(fileURL: testDirectory.appendingPathComponent("sidetrack.json"))
let expected = AppData(mainTask: TaskItem(title: "Make the first honest cut"))
do {
    try store.save(expected)
    expect(store.load() == expected, "JSON store round-trips")
    let text = try String(contentsOf: store.fileURL, encoding: .utf8)
    expect(text.contains("Make the first honest cut"), "JSON remains human-readable")
    let archivedURL = try store.archive(expected, for: date, calendar: calendar)
    expect(archivedURL.lastPathComponent == "2026-07-17.md", "automatic archive uses a stable day filename")
    let archived = try String(contentsOf: archivedURL, encoding: .utf8)
    expect(archived.contains("# Friday, 17 July 2026"), "automatic archive writes readable Markdown")
    let secondArchiveURL = try store.archive(expected, for: date, calendar: calendar)
    expect(secondArchiveURL.lastPathComponent == "2026-07-17-2.md", "another fresh start preserves the earlier archive")
    expect(DistractionLog.date(forKey: "2026-07-17", calendar: calendar) == calendar.startOfDay(for: date), "stored day keys return to dates")

    let newer = AppData(mainTask: TaskItem(title: "Make the second honest cut"))
    try store.save(newer)
    try Data("{not-json".utf8).write(to: store.fileURL, options: .atomic)
    expect(store.load() == expected, "a damaged primary file recovers the previous readable state")
    expect(store.load() == expected, "recovery restores the primary file on disk")
    try FileManager.default.removeItem(at: store.fileURL)
    expect(store.load() == expected, "a missing primary file recovers its readable backup")
    expect(FileManager.default.fileExists(atPath: store.fileURL.path), "missing-file recovery restores the primary file")

    let legacyStore = DataStore(fileURL: testDirectory.appendingPathComponent("legacy-seed.json"))
    let legacySeed = AppData(
        mainTask: TaskItem(
            title: "edit wireframe video…",
            subtasks: [
                Subtask(title: "watch once without touching the timeline"),
                Subtask(title: "notice where the feeling slips away"),
                Subtask(title: "make one quiet pass")
            ]
        ),
        today: [
            TaskItem(title: "listen once with eyes closed", subtasks: [Subtask(title: "leave a note where the rhythm breaks")]),
            TaskItem(title: "write tomorrow’s first move"),
            TaskItem(title: "leave one clean thing for morning")
        ],
        distractionsByDay: ["2026-07-17": 2]
    )
    try legacyStore.save(legacySeed)
    let migratedSeed = legacyStore.load()
    expect(migratedSeed.mainTask == nil && migratedSeed.today.isEmpty, "the exact old demo page becomes a clean first page")
    expect(migratedSeed.distractionsByDay["2026-07-17"] == 2, "demo migration preserves personal counters and settings")

    let originalLegacyStore = DataStore(fileURL: testDirectory.appendingPathComponent("original-legacy-seed.json"))
    let originalLegacySeed = AppData(
        mainTask: TaskItem(
            title: "edit wireframe video…",
            subtasks: [
                Subtask(title: "watch the latest render once, without touching it"),
                Subtask(title: "write down where attention wanders"),
                Subtask(title: "make one clean pass")
            ]
        ),
        today: [
            TaskItem(title: "listen once with eyes closed", subtasks: [Subtask(title: "notice where the rhythm slips")]),
            TaskItem(title: "write the next move down"),
            TaskItem(title: "leave one clear note for tomorrow")
        ]
    )
    try originalLegacyStore.save(originalLegacySeed)
    let migratedOriginalSeed = originalLegacyStore.load()
    expect(migratedOriginalSeed.mainTask == nil && migratedOriginalSeed.today.isEmpty, "the original demo page also becomes a clean first page")

    let damagedStore = DataStore(fileURL: testDirectory.appendingPathComponent("damaged.json"))
    try Data("{still-not-json".utf8).write(to: damagedStore.fileURL, options: .atomic)
    let safeEmpty = damagedStore.load()
    expect(safeEmpty.mainTask == nil && safeEmpty.today.isEmpty, "unrecoverable data never becomes sample tasks")
    expect(FileManager.default.fileExists(atPath: damagedStore.unreadableURL.path), "unreadable source data is preserved")

    let awayRunningStore = DataStore(fileURL: testDirectory.appendingPathComponent("away-running.json"))
    let awayRunning = AppData(
        mainTask: TaskItem(title: "Keep this held while away"),
        timer: FocusTimer(
            phase: .work,
            status: .running,
            remainingSeconds: 10 * 60,
            endsAt: Date().addingTimeInterval(10 * 60),
            phaseDurationSeconds: 50 * 60
        ),
        day: DaySession(status: .away, resumeTimerOnReturn: true),
        activeDayKey: "2026-07-17"
    )
    try awayRunningStore.save(awayRunning)
    let repairedAway = awayRunningStore.load()
    expect(repairedAway.day.status == .away && repairedAway.timer.status == .paused,
           "a readable away page can never keep advancing its timer")
    expect(repairedAway.day.resumeTimerOnReturn,
           "repair preserves explicit return ownership after safely pausing an away timer")

    for (index, deadlineOffset) in [-6 * 60 * 60, 6 * 60 * 60].enumerated() {
        let staleAwayStore = DataStore(
            fileURL: testDirectory.appendingPathComponent("away-running-stale-\(index).json")
        )
        let staleAway = AppData(
            mainTask: TaskItem(title: "Keep exactly ten minutes"),
            timer: FocusTimer(
                phase: .work,
                status: .running,
                remainingSeconds: 10 * 60,
                endsAt: Date().addingTimeInterval(TimeInterval(deadlineOffset)),
                phaseDurationSeconds: 50 * 60
            ),
            day: DaySession(status: .away, resumeTimerOnReturn: true),
            activeDayKey: "2026-07-17"
        )
        try staleAwayStore.save(staleAway)
        let heldAway = staleAwayStore.load()
        expect(heldAway.timer.status == .paused && heldAway.timer.remainingSeconds == 10 * 60,
               "away load consumed held seconds from a \(deadlineOffset < 0 ? "past" : "future") deadline")
        expect(heldAway.timer.endsAt == nil && heldAway.day.resumeTimerOnReturn,
               "away load lost explicit resume ownership or retained a wall-clock deadline")

        let staleClosedStore = DataStore(
            fileURL: testDirectory.appendingPathComponent("closed-running-stale-\(index).json")
        )
        var staleClosed = staleAway
        staleClosed.day = DaySession(status: .closed, resumeTimerOnReturn: true)
        try staleClosedStore.save(staleClosed)
        let heldClosed = staleClosedStore.load()
        expect(heldClosed.timer.status == .paused && heldClosed.timer.remainingSeconds == 10 * 60,
               "closed load consumed held seconds from a \(deadlineOffset < 0 ? "past" : "future") deadline")
        expect(heldClosed.timer.endsAt == nil && !heldClosed.day.resumeTimerOnReturn,
               "closed load retained a deadline or return ownership")
    }

    let salvageStore = DataStore(fileURL: testDirectory.appendingPathComponent("salvage.json"))
    let duplicateTaskID = UUID().uuidString
    let duplicateStepID = UUID().uuidString
    let salvageJSON = """
    {
      "mainTask": {
        "id": "not-a-uuid",
        "title": "main words survive",
        "isCompleted": "not-a-bool",
        "subtasks": [
          {"id":"\(duplicateStepID)","title":"first step survives","isCompleted":false},
          {"id":"\(duplicateStepID)","title":"second step survives","isCompleted":"not-a-bool"},
          {"id":"bad","title":17,"isCompleted":false}
        ]
      },
      "today": [
        {"id":"\(duplicateTaskID)","title":"first later thought","isCompleted":false,"subtasks":[]},
        {"id":"broken","title":17,"isCompleted":false,"subtasks":[]},
        {"id":"\(duplicateTaskID)","title":"second later thought","isCompleted":"not-a-bool","subtasks":[]}
      ],
      "distractionsByDay": {"2026-07-17":7,"broken":"many"},
      "activeDayKey": "2026-07-17"
    }
    """
    try Data(salvageJSON.utf8).write(to: salvageStore.fileURL, options: .atomic)
    let salvagedItems = salvageStore.load()
    expect(salvagedItems.mainTask?.title == "main words survive" && salvagedItems.mainTask?.isCompleted == false,
           "a malformed main ID or completion flag erased readable words")
    expect(salvagedItems.mainTask?.subtasks.map(\.title) == ["first step survives", "second step survives"],
           "one irrecoverable subthought erased readable siblings")
    expect(salvagedItems.today.map(\.title) == ["first later thought", "second later thought"],
           "one irrecoverable Today item erased readable neighbours")
    expect(salvagedItems.distractionsByDay["2026-07-17"] == 7,
           "one malformed history entry erased valid distraction history")
    let taskIDs = [salvagedItems.mainTask?.id].compactMap { $0 } + salvagedItems.today.map(\.id)
    let stepIDs = salvagedItems.mainTask?.subtasks.map(\.id) ?? []
    expect(Set(taskIDs).count == taskIDs.count && Set(stepIDs).count == stepIDs.count,
           "duplicate persisted IDs still alias distinct thoughts or steps")
    expect(!FileManager.default.fileExists(atPath: salvageStore.backupURL.path),
           "field-level salvage unnecessarily fell back to a previous page")
    try FileManager.default.removeItem(at: testDirectory)
} catch {
    FileHandle.standardError.write(Data("FAIL: store check: \(error)\n".utf8))
    exit(1)
}

print("Sidetrack checks passed: \(checks)")
