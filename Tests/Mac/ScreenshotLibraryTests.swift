import Foundation
import Testing
import WhittleCore

@MainActor
struct ScreenshotLibraryTests {
    @Test func newCapturesKeepTheActiveDraftAndStaleUpdatesCannotReplaceIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try ScreenshotLibrary(directory: directory)
        let first = AnnotationDocument(title: "First", pixelWidth: 400, pixelHeight: 300, capturedAt: Date(timeIntervalSince1970: 0))
        try library.receive(.init(document: first, originalPNG: Data([1])))
        library.edit(first.id) { $0.notes.append(.init(anchor: .init(x: 0.5, y: 0.5), text: "Keep this draft")) }

        let second = AnnotationDocument(title: "Second", pixelWidth: 400, pixelHeight: 300, capturedAt: Date(timeIntervalSince1970: 1))
        try library.receive(.init(document: second, originalPNG: Data([2])))
        try library.receive(.init(document: first, originalPNG: Data([3])))

        #expect(library.documents.map(\.id) == [second.id, first.id])
        #expect(library.selectedID == first.id)
        #expect(library.selected?.notes.first?.text == "Keep this draft")
        #expect(try library.repository.original(first.id) == Data([1]))
    }
}
