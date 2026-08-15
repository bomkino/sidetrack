import Foundation

private extension KeyedDecodingContainer {
    /// A hand-edited readable file should lose only the malformed field, not
    /// every valid sibling in the same settings or lifecycle object.
    func decodeIfValid<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        do { return try decodeIfPresent(type, forKey: key) }
        catch { return nil }
    }
}

private struct LossyValue<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

public struct Subtask: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool

    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }

    private enum CodingKeys: String, CodingKey { case id, title, isCompleted }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let title = container.decodeIfValid(String.self, forKey: .title) else {
            throw DecodingError.dataCorruptedError(
                forKey: .title,
                in: container,
                debugDescription: "A subthought needs readable text."
            )
        }
        self.init(
            id: container.decodeIfValid(UUID.self, forKey: .id) ?? UUID(),
            title: title,
            isCompleted: container.decodeIfValid(Bool.self, forKey: .isCompleted) ?? false
        )
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

    private enum CodingKeys: String, CodingKey { case id, title, isCompleted, subtasks }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let title = container.decodeIfValid(String.self, forKey: .title) else {
            throw DecodingError.dataCorruptedError(
                forKey: .title,
                in: container,
                debugDescription: "A thought needs readable text."
            )
        }
        let subtasks = container.decodeIfValid([LossyValue<Subtask>].self, forKey: .subtasks)?
            .compactMap(\.value) ?? []
        self.init(
            id: container.decodeIfValid(UUID.self, forKey: .id) ?? UUID(),
            title: title,
            isCompleted: container.decodeIfValid(Bool.self, forKey: .isCompleted) ?? false,
            subtasks: subtasks
        )
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
            workMinutes: container.decodeIfValid(Int.self, forKey: .workMinutes) ?? 50,
            breakMinutes: container.decodeIfValid(Int.self, forKey: .breakMinutes) ?? 12,
            longBreakMinutes: container.decodeIfValid(Int.self, forKey: .longBreakMinutes) ?? 30,
            cyclesPerSet: container.decodeIfValid(Int.self, forKey: .cyclesPerSet) ?? 3,
            chimeEnabled: container.decodeIfValid(Bool.self, forKey: .chimeEnabled) ?? false,
            clockOffsetMinutes: container.decodeIfValid(Int.self, forKey: .clockOffsetMinutes) ?? 15
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

/// Text alignment is independent from which edge the Today panel lives on.
/// That small distinction keeps “right” useful both spatially and typographically.
public enum ContentAlignment: String, Codable, Equatable {
    case left
    case center
    case right
}

/// Vertical pages can give the day list the first word, or let the main thought lead.
public enum PanelOrder: String, Codable, Equatable {
    case mainFirst
    case todayFirst
}

/// Where macOS should expose Sidetrack when the page is open.
/// Menu-bar-only mode removes the Dock/Cmd-Tab presence without hiding the window.
public enum PresenceMode: String, Codable, Equatable {
    case dock
    case menuBar
    case both
}

public struct DisplaySettings: Codable, Equatable {
    public var placement: DisplayPlacement
    public var orientation: DisplayOrientation
    public var panelSide: PanelSide
    public var alignment: ContentAlignment
    public var panelOrder: PanelOrder
    public var presence: PresenceMode
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
        alignment: ContentAlignment = .center,
        panelOrder: PanelOrder = .todayFirst,
        presence: PresenceMode = .both,
        oledDimEnabled: Bool = false,
        mainScale: Double = 1.15,
        timerScale: Double = 1.15,
        todayScale: Double = 1.10,
        stepsScale: Double = 1.10,
        dateScale: Double = 1.25,
        counterScale: Double = 1.10
    ) {
        self.placement = placement
        self.orientation = orientation
        self.panelSide = panelSide
        self.alignment = alignment
        self.panelOrder = panelOrder
        self.presence = presence
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
        case placement, orientation, panelSide, alignment, panelOrder, presence, oledDimEnabled
        case mainScale, timerScale, todayScale, stepsScale, dateScale, counterScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let placement = container.decodeIfValid(DisplayPlacement.self, forKey: .placement) ?? .left
        let orientation = container.decodeIfValid(DisplayOrientation.self, forKey: .orientation) ?? .vertical
        let panelSide = container.decodeIfValid(PanelSide.self, forKey: .panelSide) ?? .right
        let alignment = container.decodeIfValid(ContentAlignment.self, forKey: .alignment)
        let panelOrder = container.decodeIfValid(PanelOrder.self, forKey: .panelOrder)
        let presence = container.decodeIfValid(PresenceMode.self, forKey: .presence) ?? .both
        let oldMainScale = container.decodeIfValid(Double.self, forKey: .mainScale)
        let oldTimerScale = container.decodeIfValid(Double.self, forKey: .timerScale)
        let oldTodayScale = container.decodeIfValid(Double.self, forKey: .todayScale)
        let oldStepsScale = container.decodeIfValid(Double.self, forKey: .stepsScale)
        let oldDateScale = container.decodeIfValid(Double.self, forKey: .dateScale)
        let oldCounterScale = container.decodeIfValid(Double.self, forKey: .counterScale)
        let legacyDefaults = !container.contains(.alignment) && !container.contains(.panelOrder)

        func migrated(_ value: Double?, fallback: Double) -> Double {
            guard let value else { return fallback }
            // 1x was the old visual default. Preserve deliberate changes, but
            // give untouched controls the new, more readable baseline.
            if legacyDefaults && abs(value - 1) < 0.001 { return fallback }
            return value
        }

        self.init(
            placement: placement,
            orientation: orientation,
            panelSide: panelSide,
            alignment: alignment ?? .center,
            panelOrder: panelOrder ?? .todayFirst,
            presence: presence,
            oledDimEnabled: container.decodeIfValid(Bool.self, forKey: .oledDimEnabled) ?? false,
            mainScale: migrated(oldMainScale, fallback: 1.15),
            timerScale: migrated(oldTimerScale, fallback: 1.15),
            todayScale: migrated(oldTodayScale, fallback: 1.10),
            stepsScale: migrated(oldStepsScale, fallback: 1.10),
            dateScale: migrated(oldDateScale, fallback: 1.25),
            counterScale: migrated(oldCounterScale, fallback: 1.10)
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
    /// The expected length and exact finish of the current phase. These let
    /// Sidetrack notice a forgotten choice without changing the timer itself.
    public var phaseDurationSeconds: Int?
    public var phaseEndedAt: Date?

    public init(
        phase: TimerPhase = .work,
        status: TimerStatus = .idle,
        remainingSeconds: Int = 50 * 60,
        endsAt: Date? = nil,
        completedCyclesInSet: Int = 0,
        phaseDurationSeconds: Int? = nil,
        phaseEndedAt: Date? = nil
    ) {
        self.phase = phase
        self.status = status
        self.remainingSeconds = remainingSeconds
        self.endsAt = endsAt
        self.completedCyclesInSet = completedCyclesInSet
        self.phaseDurationSeconds = phaseDurationSeconds
        self.phaseEndedAt = phaseEndedAt
    }

    private enum CodingKeys: String, CodingKey {
        case phase, status, remainingSeconds, endsAt, completedCyclesInSet
        case phaseDurationSeconds, phaseEndedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            phase: container.decodeIfValid(TimerPhase.self, forKey: .phase) ?? .work,
            status: container.decodeIfValid(TimerStatus.self, forKey: .status) ?? .idle,
            remainingSeconds: container.decodeIfValid(Int.self, forKey: .remainingSeconds) ?? 50 * 60,
            endsAt: container.decodeIfValid(Date.self, forKey: .endsAt),
            completedCyclesInSet: container.decodeIfValid(Int.self, forKey: .completedCyclesInSet) ?? 0,
            phaseDurationSeconds: container.decodeIfValid(Int.self, forKey: .phaseDurationSeconds),
            phaseEndedAt: container.decodeIfValid(Date.self, forKey: .phaseEndedAt)
        )
    }
}

/// A boundary chosen by the person, not inferred from app activity.
/// Sidetrack keeps only the present state; it does not build an attendance log.
public enum DayStatus: String, Codable, Equatable {
    case open
    case away
    case closed
}

public struct DaySession: Codable, Equatable {
    public var status: DayStatus
    /// True only when Sidetrack itself paused a running timer for an away state.
    /// Returning still requires an explicit choice before that timer can resume.
    public var resumeTimerOnReturn: Bool
    /// Prevents a once-per-minute archive loop after a calendar boundary while
    /// the person deliberately keeps the earlier working day open.
    public var safetyArchivedDayKey: String?
    /// Marks the archived Markdown as an exact snapshot of the visible page.
    /// Page edits clear this without forgetting that the boundary was already
    /// offered and acknowledged.
    public var exactArchiveDayKey: String?

    public init(
        status: DayStatus = .open,
        resumeTimerOnReturn: Bool = false,
        safetyArchivedDayKey: String? = nil,
        exactArchiveDayKey: String? = nil
    ) {
        self.status = status
        self.resumeTimerOnReturn = resumeTimerOnReturn
        self.safetyArchivedDayKey = safetyArchivedDayKey
        self.exactArchiveDayKey = exactArchiveDayKey
    }

    private enum CodingKeys: String, CodingKey {
        case status, resumeTimerOnReturn, safetyArchivedDayKey, exactArchiveDayKey
    }

    /// Day lifecycle fields arrived after Sidetrack's first public files.
    /// Missing fields are an older page, not a damaged page; preserve the
    /// page and supply the quiet, open-day defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: container.decodeIfValid(DayStatus.self, forKey: .status) ?? .open,
            resumeTimerOnReturn: container.decodeIfValid(Bool.self, forKey: .resumeTimerOnReturn) ?? false,
            safetyArchivedDayKey: container.decodeIfValid(String.self, forKey: .safetyArchivedDayKey),
            exactArchiveDayKey: container.decodeIfValid(String.self, forKey: .exactArchiveDayKey)
        )
    }
}

public struct AppData: Codable, Equatable {
    public var mainTask: TaskItem?
    public var today: [TaskItem]
    /// A small north star that survives the midnight page turn.
    /// Sidetrack keeps it short so it stays a glance, not another task list.
    public var oneThing: String
    public var settings: PomodoroSettings
    public var display: DisplaySettings
    public var timer: FocusTimer
    public var day: DaySession
    public var didSeedFirstRun: Bool
    public var distractionsByDay: [String: Int]
    public var activeDayKey: String
    public var copyIndex: Int

    public init(
        mainTask: TaskItem? = nil,
        today: [TaskItem] = [],
        oneThing: String = "",
        settings: PomodoroSettings = PomodoroSettings(),
        display: DisplaySettings = DisplaySettings(),
        timer: FocusTimer? = nil,
        day: DaySession = DaySession(),
        didSeedFirstRun: Bool = true,
        distractionsByDay: [String: Int] = [:],
        activeDayKey: String = DistractionLog.key(),
        copyIndex: Int = 0
    ) {
        self.mainTask = mainTask
        self.today = today
        self.oneThing = String(oneThing.prefix(20))
        self.settings = settings
        self.display = display
        self.timer = timer ?? FocusTimer(
            remainingSeconds: settings.workMinutes * 60,
            phaseDurationSeconds: settings.workMinutes * 60
        )
        self.day = day
        self.didSeedFirstRun = didSeedFirstRun
        self.distractionsByDay = distractionsByDay
        self.activeDayKey = activeDayKey
        self.copyIndex = copyIndex
    }

    public static var firstRun: AppData {
        AppData()
    }

    private enum CodingKeys: String, CodingKey {
        case mainTask, today, oneThing, settings, display, timer, day, didSeedFirstRun, distractionsByDay, activeDayKey, copyIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainTask = container.decodeIfValid(TaskItem.self, forKey: .mainTask)
        today = container.decodeIfValid([LossyValue<TaskItem>].self, forKey: .today)?
            .compactMap(\.value) ?? []
        oneThing = String((container.decodeIfValid(String.self, forKey: .oneThing) ?? "").prefix(20))
        // A typo in machine-owned state must not erase readable human words.
        // Content fields above stay strict; non-content fields can safely fall
        // back and are normalized again at the store boundary.
        settings = (try? container.decode(PomodoroSettings.self, forKey: .settings)) ?? PomodoroSettings()
        display = (try? container.decode(DisplaySettings.self, forKey: .display)) ?? DisplaySettings()
        timer = (try? container.decode(FocusTimer.self, forKey: .timer))
            ?? FocusTimer(remainingSeconds: settings.workMinutes * 60)
        day = (try? container.decode(DaySession.self, forKey: .day)) ?? DaySession()
        didSeedFirstRun = (try? container.decode(Bool.self, forKey: .didSeedFirstRun)) ?? false
        if let history = try? container.nestedContainer(
            keyedBy: AnyCodingKey.self,
            forKey: .distractionsByDay
        ) {
            distractionsByDay = history.allKeys.reduce(into: [:]) { result, key in
                if let count = history.decodeIfValid(Int.self, forKey: key) {
                    result[key.stringValue] = count
                }
            }
        } else {
            distractionsByDay = [:]
        }
        activeDayKey = (try? container.decode(String.self, forKey: .activeDayKey)) ?? DistractionLog.key()
        copyIndex = (try? container.decode(Int.self, forKey: .copyIndex)) ?? 0
    }
}
