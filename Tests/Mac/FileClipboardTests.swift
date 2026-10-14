import AppKit
import Testing
import WhittleCore

@MainActor
struct FileClipboardTests {
    @Test func feedbackCopiesAsTwoActualFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var document = AnnotationDocument(title: "Feedback", pixelWidth: 400, pixelHeight: 300)
        document.notes = [.init(anchor: .init(x: 0.5, y: 0.5), text: "Use more space here")]
        let files = try ExportedFiles(document: document, annotatedPNG: Data([1, 2, 3]), directory: directory)
        let clipboard = NSPasteboard.withUniqueName()
        defer { clipboard.releaseGlobally() }
        try FileClipboard.write(files, to: clipboard)
        let urls = clipboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(urls == files.urls)
        #expect(urls?.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(try String(contentsOf: files.notes, encoding: .utf8).contains("Use more space here"))
    }
}
