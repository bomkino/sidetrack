import Foundation

public enum CopyBank {
    public static let main = [
        "edit wireframe video…",
        "what deserves the whole of you?",
        "make the next clear thing.",
        "begin where the resistance is softest.",
        "what would feel quietly finished?",
        "name the one honest thing."
    ]

    private static let later = [
        "What can wait here?",
        "What should not be lost?",
        "Leave one thought here for later.",
        "What can you set down for now?"
    ]

    private static let step = [
        "What is the first small move?",
        "What would make beginning easy?",
        "Name the part your hands can do.",
        "Where does this become lighter?"
    ]

    private static let sideStep = [
        "What would make this lighter?",
        "What belongs just beneath this?",
        "Leave the first foothold here.",
        "What will help you return?"
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
