import Foundation
import Observation
import WhittleCore

@MainActor @Observable
final class ScreenshotLibrary {
    private(set) var documents: [AnnotationDocument] = []
    var selectedID: UUID?
    var error: String?
    var onEdit: ((AnnotationDocument) -> Void)?
    let repository: DocumentRepository
    private var undoHistory: [UUID: [AnnotationDocument]] = [:]
    private var redoHistory: [UUID: [AnnotationDocument]] = [:]

    var selected: AnnotationDocument? { documents.first { $0.id == selectedID } }
    var canUndo: Bool { selectedID.map { !(undoHistory[$0] ?? []).isEmpty } ?? false }
    var canRedo: Bool { selectedID.map { !(redoHistory[$0] ?? []).isEmpty } ?? false }

    init(directory: URL) throws {
        repository = try DocumentRepository(directory: directory)
        try reload()
    }

    func reload() throws {
        documents = try repository.documents()
        if selectedID == nil || !documents.contains(where: { $0.id == selectedID }) { selectedID = documents.first?.id }
    }

    func original(_ id: UUID) -> Data? {
        do { return try repository.original(id) }
        catch { self.error = error.localizedDescription; return nil }
    }

    func receive(_ record: ScreenshotRecord) throws {
        try repository.receive(record)
        try reload()
    }

    func receive(_ document: AnnotationDocument) throws {
        if try repository.save(document) { try reload() }
    }

    func edit(_ id: UUID, _ update: (inout AnnotationDocument) -> Void) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        let previous = documents[index]
        var document = previous
        update(&document)
        guard document != previous else { return }
        document.markChanged()
        do {
            try repository.save(document)
            undoHistory[id, default: []].append(previous)
            if undoHistory[id, default: []].count > 30 { undoHistory[id]?.removeFirst() }
            redoHistory[id] = []
            documents[index] = document
            onEdit?(document)
        } catch { self.error = error.localizedDescription }
    }

    func undo() { restore(fromUndo: true) }
    func redo() { restore(fromUndo: false) }

    private func restore(fromUndo: Bool) {
        guard let id = selectedID, let index = documents.firstIndex(where: { $0.id == id }) else { return }
        var history = fromUndo ? undoHistory[id, default: []] : redoHistory[id, default: []]
        guard var document = history.popLast() else { return }
        let previous = documents[index]
        document.revision = previous.revision
        document.markChanged()
        do {
            try repository.save(document)
            if fromUndo { undoHistory[id] = history; redoHistory[id, default: []].append(previous) }
            else { redoHistory[id] = history; undoHistory[id, default: []].append(previous) }
            documents[index] = document
            onEdit?(document)
        } catch { self.error = error.localizedDescription }
    }
}

enum AppDirectories {
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    static var isTesting: Bool { isUITesting || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    static func root() throws -> URL {
        if isTesting {
            return FileManager.default.temporaryDirectory.appendingPathComponent("WhittleUITests-" + UUID().uuidString)
        }
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Whittle", isDirectory: true)
    }
}
