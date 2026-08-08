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

/// Where Sidetrack should look for its quiet second-screen home.
/// `left`, `right`, and `above` are relative to the Mac's primary display.
public enum DisplayPlacement: String, Codable, Equatable {
    case left
    case right
    case above
    case remembered
}

/// The composition inside the chosen display. This is deliberately separate
/// from the monitor's hardware rotation: an app can choose its layout, but it
/// cannot rotate a connected monitor for the user.
public enum DisplayOrientation: String, Codable, Equatable {
    case vertical
    case horizontal
}

public enum PanelSide: String, Codable, Equatable {
    case left
    case right
}

public struct DisplaySettings: Codable, Equatable {
    public var placement: DisplayPlacement
    public var orientation: DisplayOrientation
    public var panelSide: PanelSide
    public var oledDimEnabled: Bool
    public var mainScale: Double
    public var timerScale: Double
    public var todayScale: Double
    public var stepsScale: Double
    public var dateScale: Double
    public var counterScale: Double

    public init(
        placement: DisplayPlacement = .left,
        orientation: DisplayOrientation = .vertical,
        panelSide: PanelSide = .right,
        oledDimEnabled: Bool = false,
        mainScale: Double = 1,
        timerScale: Double = 1,
        todayScale: Double = 1,
        stepsScale: Double = 1,
        dateScale: Double = 1,
        counterScale: Double = 1
    ) {
        self.placement = placement
        self.orientation = orientation
        self.panelSide = panelSide
        self.oledDimEnabled = oledDimEnabled
        self.mainScale = mainScale
        self.timerScale = timerScale
        self.todayScale = todayScale
        self.stepsScale = stepsScale
        self.dateScale = dateScale
        self.counterScale = counterScale
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case placement, orientation, panelSide, oledDimEnabled
        case mainScale, timerScale, todayScale, stepsScale, dateScale, counterScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            placement: try container.decodeIfPresent(DisplayPlacement.self, forKey: .placement) ?? .left,
            orientation: try container.decodeIfPresent(DisplayOrientation.self, forKey: .orientation) ?? .vertical,
            panelSide: try container.decodeIfPresent(PanelSide.self, forKey: .panelSide) ?? .right,
            oledDimEnabled: try container.decodeIfPresent(Bool.self, forKey: .oledDimEnabled) ?? false,
            mainScale: try container.decodeIfPresent(Double.self, forKey: .mainScale) ?? 1,
            timerScale: try container.decodeIfPresent(Double.self, forKey: .timerScale) ?? 1,
            todayScale: try container.decodeIfPresent(Double.self, forKey: .todayScale) ?? 1,
            stepsScale: try container.decodeIfPresent(Double.self, forKey: .stepsScale) ?? 1,
            dateScale: try container.decodeIfPresent(Double.self, forKey: .dateScale) ?? 1,
            counterScale: try container.decodeIfPresent(Double.self, forKey: .counterScale) ?? 1
        )
    }

    public mutating func normalize() {
        mainScale = Self.clamp(mainScale)
        timerScale = Self.clamp(timerScale)
        todayScale = Self.clamp(todayScale)
        stepsScale = Self.clamp(stepsScale)
        dateScale = Self.clamp(dateScale)
        counterScale = Self.clamp(counterScale)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.75), 1.35)
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
    public var display: DisplaySettings
    public var timer: FocusTimer
    public var didSeedFirstRun: Bool
    public var distractionsByDay: [String: Int]
    public var activeDayKey: String
    public var copyIndex: Int

    public init(
        mainTask: TaskItem? = nil,
        today: [TaskItem] = [],
        settings: PomodoroSettings = PomodoroSettings(),
        display: DisplaySettings = DisplaySettings(),
        timer: FocusTimer? = nil,
        didSeedFirstRun: Bool = true,
        distractionsByDay: [String: Int] = [:],
        activeDayKey: String = DistractionLog.key(),
        copyIndex: Int = 0
    ) {
        self.mainTask = mainTask
        self.today = today
        self.settings = settings
        self.display = display
        self.timer = timer ?? FocusTimer(remainingSeconds: settings.workMinutes * 60)
        self.didSeedFirstRun = didSeedFirstRun
        self.distractionsByDay = distractionsByDay
        self.activeDayKey = activeDayKey
        self.copyIndex = copyIndex
    }

    public static var firstRun: AppData {
        AppData()
    }

    private enum CodingKeys: String, CodingKey {
        case mainTask, today, settings, display, timer, didSeedFirstRun, distractionsByDay, activeDayKey, copyIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainTask = try container.decodeIfPresent(TaskItem.self, forKey: .mainTask)
        today = try container.decodeIfPresent([TaskItem].self, forKey: .today) ?? []
        settings = try container.decodeIfPresent(PomodoroSettings.self, forKey: .settings) ?? PomodoroSettings()
        display = try container.decodeIfPresent(DisplaySettings.self, forKey: .display) ?? DisplaySettings()
        timer = try container.decodeIfPresent(FocusTimer.self, forKey: .timer)
            ?? FocusTimer(remainingSeconds: settings.workMinutes * 60)
        didSeedFirstRun = try container.decodeIfPresent(Bool.self, forKey: .didSeedFirstRun) ?? false
        distractionsByDay = try container.decodeIfPresent([String: Int].self, forKey: .distractionsByDay) ?? [:]
        activeDayKey = try container.decodeIfPresent(String.self, forKey: .activeDayKey) ?? DistractionLog.key()
        copyIndex = try container.decodeIfPresent(Int.self, forKey: .copyIndex) ?? 0
    }
}
