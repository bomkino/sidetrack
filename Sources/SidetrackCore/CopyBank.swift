import Foundation

public enum CopyBank {
    public static let main = [
        "what are you returning to?",
        "what deserves the quiet?",
        "begin where the work still feels alive.",
        "leave one honest mark.",
        "what can become clear before you stop?",
        "make room for the thing that matters."
    ]

    private static let later = [
        "leave this here; it can wait.",
        "what wants remembering?",
        "set down what keeps circling…",
        "hold this gently for later…"
    ]

    private static let step = [
        "where can your hands begin?",
        "what is the smallest honest move?",
        "find the softest way in…",
        "what would make beginning lighter?"
    ]

    private static let sideStep = [
        "leave yourself a way back in…",
        "what belongs just beneath this?",
        "name the first foothold…",
        "what will make returning easy?"
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
