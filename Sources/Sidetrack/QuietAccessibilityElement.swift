import AppKit

/// A stable accessibility object for controls drawn directly into Sidetrack's
/// canvas. Keeping these objects alive across minute redraws preserves
/// VoiceOver focus while the clock and timer quietly update.
final class QuietAccessibilityElement: NSAccessibilityElement {
    var onPress: (() -> Bool)?

    override func accessibilityPerformPress() -> Bool {
        onPress?() ?? false
    }
}
