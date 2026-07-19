import Foundation

public struct Subtask: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool

    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

public struct TaskItem: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    public var subtasks: [Subtask]

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        subtasks: [Subtask] = []
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.subtasks = subtasks
    }
}

public struct PomodoroSettings: Codable, Equatable {
    public var workMinutes: Int
    public var breakMinutes: Int
    public var longBreakMinutes: Int
    public var cyclesPerSet: Int
    public var chimeEnabled: Bool
    public var clockOffsetMinutes: Int

    public init(
        workMinutes: Int = 50,
        breakMinutes: Int = 12,
        longBreakMinutes: Int = 30,
        cyclesPerSet: Int = 3,
        chimeEnabled: Bool = false,
        clockOffsetMinutes: Int = 15
    ) {
        self.workMinutes = workMinutes
        self.breakMinutes = breakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.cyclesPerSet = cyclesPerSet
        self.chimeEnabled = chimeEnabled
        self.clockOffsetMinutes = clockOffsetMinutes
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case workMinutes, breakMinutes, longBreakMinutes, cyclesPerSet, chimeEnabled, clockOffsetMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            workMinutes: try container.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 50,
            breakMinutes: try container.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 12,
            longBreakMinutes: try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 30,
            cyclesPerSet: try container.decodeIfPresent(Int.self, forKey: .cyclesPerSet) ?? 3,
            chimeEnabled: try container.decodeIfPresent(Bool.self, forKey: .chimeEnabled) ?? false,
            clockOffsetMinutes: try container.decodeIfPresent(Int.self, forKey: .clockOffsetMinutes) ?? 15
        )
    }

    public mutating func normalize() {
        workMinutes = min(max(workMinutes, 1), 180)
        breakMinutes = min(max(breakMinutes, 1), 60)
        longBreakMinutes = min(max(longBreakMinutes, 1), 180)
        cyclesPerSet = min(max(cyclesPerSet, 1), 12)
        clockOffsetMinutes = min(max(clockOffsetMinutes, -180), 180)
    }
}

public enum TimerPhase: String, Codable, Equatable {
    case work
    case shortBreak
    case longBreak
}

public enum TimerStatus: String, Codable, Equatable {
    case idle
    case running
    case paused
    case awaitingWorkChoice
    case awaitingBreakChoice
}

public struct FocusTimer: Codable, Equatable {
    public var phase: TimerPhase
    public var status: TimerStatus
    public var remainingSeconds: Int
    public var endsAt: Date?
    public var completedCyclesInSet: Int

    public init(
        phase: TimerPhase = .work,
        status: TimerStatus = .idle,
        remainingSeconds: Int = 50 * 60,
        endsAt: Date? = nil,
        completedCyclesInSet: Int = 0
    ) {
        self.phase = phase
        self.status = status
        self.remainingSeconds = remainingSeconds
        self.endsAt = endsAt
        self.completedCyclesInSet = completedCyclesInSet
    }
}

public struct AppData: Codable, Equatable {
    public var mainTask: TaskItem?
    public var today: [TaskItem]
    public var settings: PomodoroSettings
    public var timer: FocusTimer
    public var didSeedFirstRun: Bool
    public var distractionsByDay: [String: Int]
    public var activeDayKey: String
    public var copyIndex: Int

    public init(
        mainTask: TaskItem? = nil,
        today: [TaskItem] = [],
        settings: PomodoroSettings = PomodoroSettings(),
        timer: FocusTimer? = nil,
        didSeedFirstRun: Bool = true,
        distractionsByDay: [String: Int] = [:],
        activeDayKey: String = DistractionLog.key(),
        copyIndex: Int = 0
    ) {
        self.mainTask = mainTask
        self.today = today
        self.settings = settings
        self.timer = timer ?? FocusTimer(remainingSeconds: settings.workMinutes * 60)
        self.didSeedFirstRun = didSeedFirstRun
        self.distractionsByDay = distractionsByDay
        self.activeDayKey = activeDayKey
        self.copyIndex = copyIndex
    }

    public static var firstRun: AppData {
        AppData(
            mainTask: TaskItem(
                title: "edit wireframe video…",
                subtasks: [
                    Subtask(title: "watch once without touching the timeline"),
                    Subtask(title: "notice where the feeling slips away"),
                    Subtask(title: "make one quiet pass")
                ]
            ),
            today: [
                TaskItem(
                    title: "listen once with eyes closed",
                    subtasks: [Subtask(title: "leave a note where the rhythm breaks")]
                ),
                TaskItem(title: "write tomorrow’s first move"),
                TaskItem(title: "leave one clean thing for morning")
            ]
        )
    }

    private enum CodingKeys: String, CodingKey {
        case mainTask, today, settings, timer, didSeedFirstRun, distractionsByDay, activeDayKey, copyIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainTask = try container.decodeIfPresent(TaskItem.self, forKey: .mainTask)
        today = try container.decodeIfPresent([TaskItem].self, forKey: .today) ?? []
        settings = try container.decodeIfPresent(PomodoroSettings.self, forKey: .settings) ?? PomodoroSettings()
        timer = try container.decodeIfPresent(FocusTimer.self, forKey: .timer)
            ?? FocusTimer(remainingSeconds: settings.workMinutes * 60)
        didSeedFirstRun = try container.decodeIfPresent(Bool.self, forKey: .didSeedFirstRun) ?? false
        distractionsByDay = try container.decodeIfPresent([String: Int].self, forKey: .distractionsByDay) ?? [:]
        activeDayKey = try container.decodeIfPresent(String.self, forKey: .activeDayKey) ?? DistractionLog.key()
        copyIndex = try container.decodeIfPresent(Int.self, forKey: .copyIndex) ?? 0
    }
}
