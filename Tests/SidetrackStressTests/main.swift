import Foundation
import SidetrackCore

private var checks = 0
private var failures: [String] = []

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures.append(message) }
}

struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func int(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    mutating func bool() -> Bool { next() & 1 == 0 }
}

private let textSamples = [
    "make one honest move",
    "quiet work, then tea",
    "नमस्ते — begin gently",
    "目の前のこと",
    "emoji stays human 🫶🏽",
    "a title with [brackets] and *stars*",
    "line one\nline two",
    String(repeating: "long thought ", count: 80)
]

private func randomTask(_ random: inout SeededRandom) -> TaskItem {
    let stepCount = random.int(12)
    return TaskItem(
        title: textSamples[random.int(textSamples.count)],
        isCompleted: random.bool(),
        subtasks: (0..<stepCount).map { index in
            Subtask(title: "\(textSamples[random.int(textSamples.count)]) \(index)", isCompleted: random.bool())
        }
    )
}

private func randomData(_ random: inout SeededRandom, dayKey: String) -> AppData {
    let settings = PomodoroSettings(
        workMinutes: random.int(180) + 1,
        breakMinutes: random.int(60) + 1,
        longBreakMinutes: random.int(180) + 1,
        cyclesPerSet: random.int(12) + 1,
        chimeEnabled: random.bool(),
        clockOffsetMinutes: random.int(361) - 180
    )
    return AppData(
        mainTask: random.bool() ? randomTask(&random) : nil,
        today: (0..<random.int(20)).map { _ in randomTask(&random) },
        oneThing: String(textSamples[random.int(textSamples.count)].prefix(20)),
        settings: settings,
        display: DisplaySettings(
            placement: [.left, .right, .above, .remembered][random.int(4)],
            orientation: random.bool() ? .vertical : .horizontal,
            panelSide: random.bool() ? .left : .right,
            alignment: [.left, .center, .right][random.int(3)],
            panelOrder: random.bool() ? .mainFirst : .todayFirst,
            presence: [.dock, .menuBar, .both][random.int(3)],
            oledDimEnabled: random.bool(),
            mainScale: Double(random.int(61) + 75) / 100,
            timerScale: Double(random.int(61) + 75) / 100,
            todayScale: Double(random.int(61) + 75) / 100,
            stepsScale: Double(random.int(61) + 75) / 100,
            dateScale: Double(random.int(61) + 75) / 100,
            counterScale: Double(random.int(61) + 75) / 100
        ),
        distractionsByDay: [dayKey: random.int(10_000)],
        activeDayKey: dayKey,
        copyIndex: random.int(CopyBank.main.count)
    )
}

private func assertTimerInvariants(_ data: AppData, seed: Int, step: Int) {
    let timer = data.timer
    let context = "seed \(seed), step \(step), \(timer.phase.rawValue)/\(timer.status.rawValue)"
    check(timer.remainingSeconds >= 0, "negative remaining time: \(context)")
    check(timer.completedCyclesInSet >= 0, "negative cycle count: \(context)")
    check(timer.completedCyclesInSet < data.settings.cyclesPerSet, "cycle count escaped its set: \(context)")
    check((timer.phaseDurationSeconds ?? 1) > 0, "non-positive phase duration: \(context)")

    if timer.status == .running {
        check(timer.endsAt != nil, "running timer lost its deadline: \(context)")
        check(timer.remainingSeconds > 0, "running timer retained zero: \(context)")
        check(timer.phaseEndedAt == nil, "running timer retained an ended timestamp: \(context)")
    } else {
        check(timer.endsAt == nil, "stopped timer retained a deadline: \(context)")
    }

    if timer.status == .awaitingWorkChoice {
        check(timer.phase == .work, "work question belongs to a rest phase: \(context)")
        check(timer.remainingSeconds == 0, "work question retained time: \(context)")
        check(timer.phaseEndedAt != nil, "work question lost its finish time: \(context)")
    }
    if timer.status == .awaitingBreakChoice {
        check(timer.phase != .work, "break question belongs to work: \(context)")
        check(timer.remainingSeconds == 0, "break question retained time: \(context)")
        check(timer.phaseEndedAt != nil, "break question lost its finish time: \(context)")
    }

    check(data.oneThing.count <= 20, "north star exceeded twenty characters: \(context)")
    switch data.day.status {
    case .open:
        check(!data.day.resumeTimerOnReturn, "open day retained away-only resume ownership: \(context)")
    case .away:
        if data.day.resumeTimerOnReturn {
            check(timer.status == .paused, "away resume ownership exists without a paused timer: \(context)")
        }
    case .closed:
        check(timer.status != .running, "closed day kept a timer running: \(context)")
        check(!data.day.resumeTimerOnReturn, "closed day retained resume ownership: \(context)")
    }
}

// Public copy rotation must be total over every Int, including values that can
// arrive from a hand-edited readable JSON file.
for index in [Int.min, Int.min + 1, -1, 0, 1, Int.max - 1, Int.max] {
    let next = CopyBank.next(index)
    check((0..<CopyBank.main.count).contains(next), "copy rotation escaped its bank for \(index)")
    check(!CopyBank.mainPrompt(index: index).isEmpty, "copy lookup failed for \(index)")
}

// Counter history is a bounded query. Invalid negative counts must not turn a
// display helper into a process-level trap.
check(DistractionLog.recentDays(from: [:], count: -1).isEmpty, "negative history length was not safely empty")

// Thousands of unseen action sequences exercise the state machine without
// assuming a preferred route through it.
for seed in 1...128 {
    var random = SeededRandom(seed: UInt64(seed) &* 0xD1342543DE82EF95)
    var now = Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(seed * 10_000))
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var data = randomData(&random, dayKey: DistractionLog.key(for: now, calendar: calendar))
    TimerEngine.reset(&data.timer, settings: data.settings)

    for step in 0..<2_000 {
        switch random.int(13) {
        case 0:
            if data.day.status == .open { TimerEngine.toggle(&data.timer, settings: data.settings, now: now) }
        case 1:
            now = now.addingTimeInterval(TimeInterval(random.int(20_000)))
            _ = TimerEngine.refresh(&data.timer, now: now)
        case 2:
            if data.day.status == .open {
                if random.bool() {
                    TimerEngine.takeBreak(&data.timer, settings: data.settings, now: now)
                } else {
                    TimerEngine.keepWorking(&data.timer, now: now)
                }
            }
        case 3:
            if data.day.status == .open {
                TimerEngine.startAgain(&data.timer, settings: data.settings, now: now)
            }
        case 4:
            DayEngine.stepAway(&data, now: now)
        case 5:
            DayEngine.returnToDay(&data, resumeTimer: random.bool(), now: now, calendar: calendar)
        case 6:
            DayEngine.close(&data, now: now)
        case 7:
            if data.day.status == .open { TimerEngine.reset(&data.timer, settings: data.settings) }
        case 8:
            let previous = data
            if random.bool() { data.mainTask = randomTask(&random) }
            else { data.today.append(randomTask(&random)) }
            DayEngine.invalidateSafetyArchiveIfPageChanged(&data, comparedTo: previous)
        case 9:
            data.day.safetyArchivedDayKey = data.activeDayKey
            data.day.exactArchiveDayKey = data.activeDayKey
        case 10:
            let dayOffset = random.int(4)
            let day = calendar.date(byAdding: .day, value: dayOffset, to: now)!
            DayEngine.beginFreshDay(
                &data,
                dayKey: DistractionLog.key(for: day, calendar: calendar),
                resetDistractionCount: random.bool()
            )
        case 11:
            TimerEngine.ensurePhaseMetadata(&data.timer, settings: data.settings)
        default:
            let before = data.timer
            var wrong = data.timer
            if before.status != .awaitingWorkChoice {
                TimerEngine.keepWorking(&wrong, now: now)
                check(wrong == before, "wrong-state Keep working mutated timer at seed \(seed), step \(step)")
            }
        }
        _ = TimerEngine.refresh(&data.timer, now: now)
        assertTimerInvariants(data, seed: seed, step: step)
    }
}

// Time language is tested exhaustively across the full day, not with a few
// phrases chosen to match its current branches.
for identifier in ["UTC", "Asia/Kolkata", "America/New_York", "Europe/London", "Australia/Lord_Howe"] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: identifier)!
    let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
    for minute in 0..<1_440 {
        let date = calendar.date(byAdding: .minute, value: minute, to: day)!
        let phrase = TimeLanguage.clockPhrase(date, calendar: calendar)
        check(!phrase.isEmpty && !phrase.contains(":"), "clock precision leaked in \(identifier) at minute \(minute)")
        let key = DistractionLog.key(for: date, calendar: calendar)
        let decoded = DistractionLog.date(forKey: key, calendar: calendar)
        check(decoded == calendar.startOfDay(for: date), "day key failed round-trip in \(identifier): \(key)")
    }
}

for seconds in stride(from: -3_600, through: 12 * 60 * 60, by: 17) {
    let phrase = TimeLanguage.timer(seconds: seconds)
    check(!phrase.contains(":"), "timer exposed clock precision at \(seconds) seconds")
    check(!phrase.lowercased().contains("second"), "timer exposed seconds at \(seconds) seconds")
}

for index in 0..<100_000 {
    let date = Date(timeIntervalSinceReferenceDate: TimeInterval(index * 997))
    let shift = BurnInShift.offset(at: date)
    check(abs(shift.x) <= 2.2 && abs(shift.y) <= 1.8, "burn-in shift escaped its invisible envelope")
}

// Readable JSON is a user-facing format, so syntactically valid but
// semantically impossible state must degrade to a safe page instead of
// creating an immortal timer, negative counts, or losing the user's thought.
let malformedRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build/stress-malformed/\(UUID().uuidString)", isDirectory: true)
let malformedStore = DataStore(fileURL: malformedRoot.appendingPathComponent("sidetrack.json"))
do {
    try FileManager.default.createDirectory(at: malformedRoot, withIntermediateDirectories: true)
    let impossible: [String: Any] = [
        "mainTask": [
            "id": UUID().uuidString,
            "title": "This thought must survive repair",
            "isCompleted": false,
            "subtasks": []
        ],
        "today": [],
        "oneThing": "$10k",
        "settings": [
            "workMinutes": 9_999,
            "breakMinutes": -8,
            "longBreakMinutes": 99_999,
            "cyclesPerSet": 0,
            "chimeEnabled": false,
            "clockOffsetMinutes": 99_999
        ],
        "display": [
            "placement": "left",
            "orientation": "vertical",
            "panelSide": "right",
            "alignment": "center",
            "panelOrder": "todayFirst",
            "presence": "both",
            "oledDimEnabled": false,
            "mainScale": 100,
            "timerScale": -100,
            "todayScale": 100,
            "stepsScale": -100,
            "dateScale": 100,
            "counterScale": -100
        ],
        "timer": [
            "phase": "work",
            "status": "running",
            "remainingSeconds": -90,
            "completedCyclesInSet": Int.max,
            "phaseDurationSeconds": -1
        ],
        "day": [
            "status": "closed",
            "resumeTimerOnReturn": true,
            "safetyArchivedDayKey": "not-a-day",
            "exactArchiveDayKey": "not-a-day"
        ],
        "didSeedFirstRun": true,
        "distractionsByDay": ["not-a-day": -42],
        "activeDayKey": "not-a-day",
        "copyIndex": Int.max
    ]
    let impossibleData = try JSONSerialization.data(withJSONObject: impossible, options: [.prettyPrinted])
    try impossibleData.write(to: malformedStore.fileURL, options: .atomic)
    var repaired = malformedStore.load()
    check(repaired.mainTask?.title == "This thought must survive repair", "semantic repair discarded the user's main thought")
    check(repaired.timer.remainingSeconds >= 0, "semantic repair retained negative time")
    check(repaired.timer.status != .running || repaired.timer.endsAt != nil, "semantic repair retained a running timer without a deadline")
    check(repaired.timer.completedCyclesInSet >= 0 && repaired.timer.completedCyclesInSet < repaired.settings.cyclesPerSet, "semantic repair retained an impossible cycle count")
    check(repaired.timer.phaseDurationSeconds == repaired.settings.workMinutes * 60,
          "semantic repair did not replace an invalid phase duration with the configured rhythm")
    check(!repaired.day.resumeTimerOnReturn, "semantic repair left a closed day owning a resume")
    check(repaired.day.status != .closed || repaired.timer.status != .running, "semantic repair left a closed day running")
    check(DistractionLog.date(forKey: repaired.activeDayKey) != nil, "semantic repair retained an unusable active day key")
    check(repaired.distractionsByDay.values.allSatisfy { $0 >= 0 }, "semantic repair retained a negative distraction count")
    DayEngine.beginFreshDay(&repaired, dayKey: DistractionLog.key())
    check(repaired.copyIndex >= 0 && repaired.copyIndex < CopyBank.main.count, "fresh day did not normalize the copy bank index")

    var missingField = impossible
    missingField["timer"] = [
        "phase": "work",
        "status": "paused",
        "remainingSeconds": 60,
        "completedCyclesInSet": 0
    ]
    missingField["day"] = ["status": "away"]
    let missingFieldData = try JSONSerialization.data(withJSONObject: missingField, options: [.prettyPrinted])
    try missingFieldData.write(to: malformedStore.fileURL, options: .atomic)
    let tolerant = malformedStore.load()
    check(tolerant.mainTask?.title == "This thought must survive repair", "missing new lifecycle fields blanked otherwise readable user data")
    check(tolerant.day.status == .away, "partial lifecycle state did not preserve its known status")

    var brokenNonContent = impossible
    brokenNonContent["settings"] = "tea, perhaps"
    brokenNonContent["display"] = 14
    brokenNonContent["timer"] = ["phase": "impossible", "status": false]
    brokenNonContent["day"] = ["status": "between worlds"]
    brokenNonContent["distractionsByDay"] = ["today": "many"]
    brokenNonContent["copyIndex"] = "last one"
    let brokenNonContentData = try JSONSerialization.data(withJSONObject: brokenNonContent, options: [.prettyPrinted])
    try? FileManager.default.removeItem(at: malformedStore.backupURL)
    try brokenNonContentData.write(to: malformedStore.fileURL, options: .atomic)
    let salvaged = malformedStore.load()
    check(salvaged.mainTask?.title == "This thought must survive repair",
          "one malformed non-content field blanked otherwise readable human text")

    var olderEmptyPage = impossible
    olderEmptyPage.removeValue(forKey: "didSeedFirstRun")
    olderEmptyPage["mainTask"] = NSNull()
    olderEmptyPage["today"] = []
    olderEmptyPage["oneThing"] = "$10k"
    olderEmptyPage["distractionsByDay"] = [DistractionLog.key(): 7]
    olderEmptyPage["settings"] = [
        "workMinutes": 75,
        "breakMinutes": 15,
        "longBreakMinutes": 35,
        "cyclesPerSet": 3,
        "chimeEnabled": false,
        "clockOffsetMinutes": 15
    ]
    let olderEmptyData = try JSONSerialization.data(withJSONObject: olderEmptyPage, options: [.prettyPrinted])
    try olderEmptyData.write(to: malformedStore.fileURL, options: .atomic)
    let migratedEmpty = malformedStore.load()
    check(migratedEmpty.oneThing == "$10k", "missing migration flag erased an otherwise valid north star")
    check(migratedEmpty.settings.workMinutes == 75, "missing migration flag reset valid preferences")
    check(migratedEmpty.distractionsByDay[DistractionLog.key()] == 7,
          "missing migration flag erased valid distraction history")
} catch {
    failures.append("malformed-state stress threw: \(error)")
}
try? FileManager.default.removeItem(at: malformedRoot)

// Persistence stress uses random human content, repeated archives, damaged
// primaries, and a pre-save corruption. It checks the files themselves.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build/stress-output/\(UUID().uuidString)", isDirectory: true)
let store = DataStore(fileURL: root.appendingPathComponent("sidetrack.json"))
var persistenceRandom = SeededRandom(seed: 0xC0FFEE)
var previous: AppData?

do {
    for index in 0..<120 {
        let dayKey = String(format: "2026-09-%02d", (index % 28) + 1)
        let value = randomData(&persistenceRandom, dayKey: dayKey)
        try store.save(value)
        let loaded = store.load()
        check(loaded == value, "random JSON round-trip changed record \(index)")
        if let previous, let backupData = try? Data(contentsOf: store.backupURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            check((try? decoder.decode(AppData.self, from: backupData)) == previous, "backup did not retain prior readable record \(index)")
        }
        previous = value
    }

    // A running timer is valid even though its cached remaining count becomes
    // stale between writes. Saving the next change must still create a usable
    // backup of that running page.
    var running = randomData(&persistenceRandom, dayKey: DistractionLog.key())
    TimerEngine.toggle(&running.timer, settings: running.settings, now: Date())
    running.mainTask = TaskItem(title: "running page should remain recoverable")
    try store.save(running)
    var following = running
    following.oneThing = "next"
    try store.save(following)
    if let backupData = try? Data(contentsOf: store.backupURL) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try? decoder.decode(AppData.self, from: backupData)
        check(backup?.mainTask?.title == "running page should remain recoverable",
              "a valid running page was rejected as a backup because time advanced")
        check(backup?.timer.status == .running && backup?.timer.endsAt != nil,
              "running timer backup lost its recoverable deadline")
    } else {
        check(false, "saving after a running page produced no backup")
    }

    let goodBackup = store.load()
    let unreadable = Data("{\"unfinished\":".utf8)
    try unreadable.write(to: store.fileURL, options: .atomic)
    let recovered = store.load()
    check(recovered != AppData.firstRun, "readable backup was ignored after primary corruption")
    check((try? Data(contentsOf: store.unreadableURL)) == unreadable, "corrupt primary was discarded during backup recovery")

    // A corrupted primary must never replace the last readable backup merely
    // because a later in-memory save succeeds.
    let readableBackupBefore = try Data(contentsOf: store.backupURL)
    try Data("not-json-anymore".utf8).write(to: store.fileURL, options: .atomic)
    let newValue = randomData(&persistenceRandom, dayKey: "2026-10-01")
    try store.save(newValue)
    let readableBackupAfter = try Data(contentsOf: store.backupURL)
    check(readableBackupAfter == readableBackupBefore, "save replaced a readable backup with corrupt primary bytes")
    try Data("broken-again".utf8).write(to: store.fileURL, options: .atomic)
    check(store.load() != AppData.firstRun, "second corruption lost every readable recovery point")

    var archiveNames = Set<String>()
    for _ in 0..<80 {
        let url = try store.archive(goodBackup, for: Date(timeIntervalSince1970: 1_700_000_000))
        archiveNames.insert(url.lastPathComponent)
    }
    check(archiveNames.count == 80, "collision-safe archives overwrote one another")
} catch {
    failures.append("persistence stress threw: \(error)")
}

try? FileManager.default.removeItem(at: root)

if !failures.isEmpty {
    for failure in failures.prefix(40) {
        FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
    }
    if failures.count > 40 {
        FileHandle.standardError.write(Data("FAIL: \(failures.count - 40) more failures omitted\n".utf8))
    }
    exit(1)
}

print("Sidetrack stress checks passed: \(checks) assertions across 256,000 randomized actions")
