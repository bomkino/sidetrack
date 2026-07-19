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
expect(TimeLanguage.rhythmLine(phase: .work, status: .running, seconds: 50 * 60, settings: PomodoroSettings()) == "Focus  ·  ~50 minutes left", "running focus is explicit")
expect(TimeLanguage.rhythmLine(phase: .work, status: .paused, seconds: 50 * 60, settings: PomodoroSettings()) == "Focus paused  ·  ~50 minutes left", "paused focus uses the literal state")
expect(TimeLanguage.rhythmLine(phase: .shortBreak, status: .running, seconds: 12 * 60, settings: PomodoroSettings()) == "Short break  ·  ~12 minutes left", "short break names its own countdown")
expect(TimeLanguage.rhythmLine(phase: .longBreak, status: .running, seconds: 30 * 60, settings: PomodoroSettings()) == "Long break  ·  half an hour left", "long break names its own countdown")

expect(CopyBank.mainPrompt(index: 0) == "edit wireframe video…", "requested main placeholder leads the copy bank")
expect(CopyBank.mainPrompt(index: CopyBank.next(0)) != CopyBank.mainPrompt(index: 0), "fresh day advances the copy bank")

let late = calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 23, minute: 50))!
let offsetLate = TimeLanguage.adjusted(late, offsetMinutes: 15)
expect(TimeLanguage.dateLine(offsetLate, calendar: calendar) == "Saturday, 18 July", "+15 display clock crosses midnight calmly")
expect(TimeLanguage.clockPhrase(offsetLate, calendar: calendar) == "twelve o’clock", "offset clock uses the adjusted day")

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

var breakTimer = FocusTimer(phase: .shortBreak, status: .running, remainingSeconds: 60, endsAt: now)
expect(TimerEngine.refresh(&breakTimer, now: now) == .breakEnded, "break end emits event")
expect(breakTimer.status == .awaitingBreakChoice, "break does not auto-restart")

var cycleTimer = FocusTimer(status: .awaitingWorkChoice, remainingSeconds: 0, completedCyclesInSet: 3)
TimerEngine.takeBreak(&cycleTimer, settings: PomodoroSettings(cyclesPerSet: 4), now: now)
expect(cycleTimer.phase == .longBreak, "long break follows configured cycle count")
expect(cycleTimer.completedCyclesInSet == 0, "cycle set resets after long break")

var shortRestTimer = FocusTimer(status: .awaitingWorkChoice, remainingSeconds: 0)
TimerEngine.takeBreak(&shortRestTimer, settings: PomodoroSettings(), now: now)
expect(shortRestTimer.phase == .shortBreak && shortRestTimer.status == .running, "choosing a short rest starts a distinct timer")
expect(shortRestTimer.remainingSeconds == 12 * 60, "short rest receives the full configured countdown")

let defaults = PomodoroSettings()
expect(defaults.workMinutes == 50, "default focus is 50 minutes")
expect(defaults.breakMinutes == 12, "default break is 12 minutes")
expect(defaults.cyclesPerSet == 3, "default set contains three cycles")
expect(defaults.longBreakMinutes == 30, "default long break is 30 minutes")
expect(defaults.clockOffsetMinutes == 15, "default display clock is fifteen minutes ahead")
let legacySettings = try! JSONDecoder().decode(PomodoroSettings.self, from: Data("{\"workMinutes\":25,\"breakMinutes\":5,\"longBreakMinutes\":30,\"cyclesPerSet\":4,\"chimeEnabled\":false}".utf8))
expect(legacySettings.clockOffsetMinutes == 15, "older settings migrate to the preferred clock offset")
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

let exported = MarkdownExporter.render(AppData.firstRun, date: date, calendar: calendar)
expect(exported.contains("# Friday, 17 July 2026"), "Markdown export has day heading")
expect(exported.contains("- [ ] edit wireframe video…"), "Markdown export contains main thought")
expect(exported.contains("  - [ ] watch the latest render once, without touching it"), "Markdown export contains subthoughts")
expect(exported.contains("## Distractions\n0"), "Markdown export contains daily distraction count")

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

    let damagedStore = DataStore(fileURL: testDirectory.appendingPathComponent("damaged.json"))
    try Data("{still-not-json".utf8).write(to: damagedStore.fileURL, options: .atomic)
    let safeEmpty = damagedStore.load()
    expect(safeEmpty.mainTask == nil && safeEmpty.today.isEmpty, "unrecoverable data never becomes sample tasks")
    expect(FileManager.default.fileExists(atPath: damagedStore.unreadableURL.path), "unreadable source data is preserved")
    try FileManager.default.removeItem(at: testDirectory)
} catch {
    FileHandle.standardError.write(Data("FAIL: store check: \(error)\n".utf8))
    exit(1)
}

print("Sidetrack checks passed: \(checks)")
