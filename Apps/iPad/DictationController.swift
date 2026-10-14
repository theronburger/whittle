import AVFoundation
import Observation
import Speech

@MainActor @Observable
final class DictationController {
    private(set) var recording = false
    var error: String?
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var starting = false
    private var sessionID = UUID()

    func start(onText: @escaping (String) -> Void) async {
        guard !recording, !starting else { stop(); return }
        starting = true
        let sessionID = UUID()
        self.sessionID = sessionID
        defer { if self.sessionID == sessionID { starting = false } }
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard self.sessionID == sessionID else { return }
        guard speechStatus == .authorized else { error = "Allow Speech Recognition for Whittle in iPad Settings to dictate notes."; return }
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard self.sessionID == sessionID else { return }
        guard microphoneAllowed else { error = "Allow Microphone access for Whittle in iPad Settings."; return }
        let recognizer = SFSpeechRecognizer(locale: .current)
        guard let recognizer, recognizer.isAvailable else { error = "Dictation is unavailable right now. Try again in a moment."; return }
        self.recognizer = recognizer
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            hasTap = true
            engine.prepare()
            try engine.start()
            recording = true
            error = nil
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                Task { @MainActor in
                    guard self?.sessionID == sessionID else { return }
                    if let result { onText(result.bestTranscription.formattedString) }
                    if result?.isFinal == true || failure != nil {
                        if let failure, self?.recording == true { self?.error = failure.localizedDescription }
                        self?.stop()
                    }
                }
            }
        } catch { self.error = error.localizedDescription; stop() }
    }

    func stop() {
        sessionID = UUID()
        starting = false
        recording = false
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
