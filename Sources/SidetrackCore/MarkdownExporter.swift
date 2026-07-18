import Foundation

public enum MarkdownExporter {
    public static func render(_ data: AppData, date: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, d MMMM yyyy"

        var lines = ["# \(formatter.string(from: date))", ""]
        lines.append("## Now")
        if let main = data.mainTask {
            append(main, to: &lines)
        } else {
            lines.append("_Nothing held here._")
        }
        lines.append("")
        lines.append("## Later, today")
        if data.today.isEmpty {
            lines.append("_Nothing else held._")
        } else {
            for task in data.today { append(task, to: &lines) }
        }
        lines.append("")
        lines.append("## Distractions")
        let count = data.distractionsByDay[DistractionLog.key(for: date, calendar: calendar), default: 0]
        lines.append("\(count)")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func append(_ task: TaskItem, to lines: inout [String]) {
        lines.append("- [\(task.isCompleted ? "x" : " ")] \(clean(task.title))")
        for subtask in task.subtasks {
            lines.append("  - [\(subtask.isCompleted ? "x" : " ")] \(clean(subtask.title))")
        }
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
    }
}
