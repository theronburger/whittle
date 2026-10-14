import SwiftUI
import WhittleCore

struct NoteEditor: View {
    let library: ScreenshotLibrary
    let documentID: UUID
    let noteID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var loaded = false
    @State private var dictation = DictationController()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Make your point.").font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        if dictation.recording { dictation.stop() }
                        else {
                            focused = false
                            let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task { await dictation.start { transcript in text = prefix.isEmpty ? transcript : prefix + " " + transcript } }
                        }
                    } label: {
                        Image(systemName: dictation.recording ? "stop.fill" : "mic.fill")
                            .font(.title3).foregroundStyle(dictation.recording ? .white : WhittleTheme.accent)
                            .frame(width: 52, height: 52)
                            .background(dictation.recording ? Color.red : WhittleTheme.accent.opacity(0.12), in: Circle())
                    }.accessibilityLabel(dictation.recording ? "Stop Dictation" : "Dictate Note").accessibilityIdentifier("dictateNote")
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty { Text("Say it or type it…").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5) }
                    TextEditor(text: $text).font(.body).focused($focused).scrollContentBackground(.hidden)
                        .accessibilityIdentifier("noteTextEditor")
                }
                if dictation.recording { Label("Listening…", systemImage: "waveform").font(.callout).foregroundStyle(.red) }
                if let error = dictation.error { Text(error).font(.caption).foregroundStyle(.red) }
                Text("Your words stay editable and travel with the annotated image.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Feedback Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Delete", role: .destructive) {
                        dictation.stop()
                        library.edit(documentID) { $0.notes.removeAll { $0.id == noteID } }
                        dismiss()
                    }.accessibilityIdentifier("deleteNote")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dictation.stop(); dismiss() }.bold().accessibilityIdentifier("finishNote") }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            text = library.documents.first(where: { $0.id == documentID })?.notes.first(where: { $0.id == noteID })?.text ?? ""
            loaded = true
        }
        .onChange(of: text) { _, value in
            guard loaded else { return }
            library.edit(documentID) { document in
                if let index = document.notes.firstIndex(where: { $0.id == noteID }) { document.notes[index].text = value }
            }
        }
        .onDisappear { dictation.stop() }
        .onChange(of: focused) { _, focused in if focused { dictation.stop() } }
    }
}
