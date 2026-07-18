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

    public init(
        workMinutes: Int = 50,
        breakMinutes: Int = 12,
        longBreakMinutes: Int = 30,
        cyclesPerSet: Int = 3,
        chimeEnabled: Bool = false
    ) {
        self.workMinutes = workMinutes
        self.breakMinutes = breakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.cyclesPerSet = cyclesPerSet
        self.chimeEnabled = chimeEnabled
        normalize()
    }

    public mutating func normalize() {
        workMinutes = min(max(workMinutes, 1), 180)
        breakMinutes = min(max(breakMinutes, 1), 60)
        longBreakMinutes = min(max(longBreakMinutes, 1), 180)
        cyclesPerSet = min(max(cyclesPerSet, 1), 12)
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

    public init(
        mainTask: TaskItem? = nil,
        today: [TaskItem] = [],
        settings: PomodoroSettings = PomodoroSettings(),
        timer: FocusTimer? = nil,
        didSeedFirstRun: Bool = true,
        distractionsByDay: [String: Int] = [:]
    ) {
        self.mainTask = mainTask
        self.today = today
        self.settings = settings
        self.timer = timer ?? FocusTimer(remainingSeconds: settings.workMinutes * 60)
        self.didSeedFirstRun = didSeedFirstRun
        self.distractionsByDay = distractionsByDay
    }

    public static var firstRun: AppData {
        AppData(
            mainTask: TaskItem(
                title: "edit wireframe video…",
                subtasks: [
                    Subtask(title: "watch the latest render once, without touching it"),
                    Subtask(title: "write down where attention wanders"),
                    Subtask(title: "make one clean pass")
                ]
            ),
            today: [
                TaskItem(
                    title: "listen once with eyes closed",
                    subtasks: [Subtask(title: "notice where the rhythm slips")]
                ),
                TaskItem(title: "write the next move down"),
                TaskItem(title: "leave one clear note for tomorrow")
            ]
        )
    }

    private enum CodingKeys: String, CodingKey {
        case mainTask, today, settings, timer, didSeedFirstRun, distractionsByDay
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
    }
}
