import Foundation
import Testing
@testable import WhittleCore

struct DocumentTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func editsSurviveRestartAndStaleMessages() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try DocumentRepository(directory: directory)
        var document = AnnotationDocument(title: "Settings", pixelWidth: 1200, pixelHeight: 800)
        let original = Data("original screenshot".utf8)
        try repository.receive(.init(document: document, originalPNG: original))
        let stale = document
        document.notes.append(.init(anchor: .init(x: 0.25, y: 0.5), text: "Increase the contrast"))
        document.markChanged()
        #expect(try repository.save(document))
        #expect(try !repository.save(stale))
        #expect(try !repository.receive(.init(document: stale, originalPNG: Data("wrong".utf8))))
        let restarted = try DocumentRepository(directory: directory)
        #expect(try restarted.documents() == [document])
        #expect(try restarted.original(document.id) == original)
    }

    @Test func notesRemainExactTextInExport() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var document = AnnotationDocument(title: "Checkout", pixelWidth: 2000, pixelHeight: 1000)
        document.notes = [.init(anchor: .init(x: 0.25, y: 0.75), text: "Use `gap: 12px`, not 8.\nKeep “Submit” unchanged.")]
        let files = try ExportedFiles(document: document, annotatedPNG: Data([1, 2, 3]), directory: directory)
        let markdown = try String(contentsOf: files.notes, encoding: .utf8)
        #expect(markdown.contains("at (500, 750)"))
        #expect(markdown.contains(document.notes[0].text))
        #expect(files.urls.count == 2)
        #expect(files.image.pathExtension == "png")
        #expect(files.notes.pathExtension == "md")
    }

    @Test func revisionsGetStableSeparateExportFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var document = AnnotationDocument(title: "../unsafe/name", pixelWidth: 100, pixelHeight: 100)
        let first = try ExportedFiles(document: document, annotatedPNG: Data([1]), directory: directory)
        document.markChanged()
        let second = try ExportedFiles(document: document, annotatedPNG: Data([2]), directory: directory)
        #expect(first.image != second.image)
        #expect(try Data(contentsOf: first.image) == Data([1]))
        #expect(second.image.path.hasPrefix(directory.path))
    }

    @Test func rejectsInvalidRemoteCoordinatesAndMissingOriginal() throws {
        var document = AnnotationDocument(title: "Test", pixelWidth: 100, pixelHeight: 100)
        var point = CanvasPoint(x: 0, y: 0)
        point.x = .infinity
        document.notes = [.init(anchor: point)]
        #expect(throws: WhittleError.self) { try document.validate() }
        document.notes = []
        document.revision = -1
        #expect(throws: WhittleError.self) { try document.validate() }
        document.revision = 0
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try DocumentRepository(directory: directory)
        #expect(throws: WhittleError.self) { try repository.save(document) }
    }
}
