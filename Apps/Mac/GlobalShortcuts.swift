import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureRegion = Self("captureRegion", initial: .init(.w, modifiers: [.command, .shift, .option]))
    static let pasteScreenshot = Self("pasteScreenshot", initial: .init(.w, modifiers: [.command, .option]))
}
