import Foundation

public enum CopyBank {
    public static let main = [
        "edit wireframe video…",
        "what are you returning to?",
        "leave the next honest mark.",
        "begin with the part that still has a pulse.",
        "what can become clear before you stop?",
        "make one thing quieter."
    ]

    private static let later = [
        "hold something here…",
        "leave this where you can find it…",
        "what can wait without disappearing?",
        "set down what keeps circling…"
    ]

    private static let step = [
        "what is the smallest honest move?",
        "where can your hands begin?",
        "leave yourself an easy entrance.",
        "what makes this lighter?"
    ]

    private static let sideStep = [
        "leave a way back in…",
        "what belongs underneath?",
        "name the first foothold…",
        "what will help you return?"
    ]

    public static func mainPrompt(index: Int) -> String { pick(main, index) }
    public static func laterPrompt(index: Int) -> String { pick(later, index) }
    public static func stepPrompt(index: Int) -> String { pick(step, index) }
    public static func sideStepPrompt(index: Int) -> String { pick(sideStep, index) }

    public static func next(_ index: Int) -> Int {
        (index + 1) % main.count
    }

    private static func pick(_ values: [String], _ index: Int) -> String {
        values[((index % values.count) + values.count) % values.count]
    }
}
