import Foundation
import WatchKit

/// The microphone for a question. A press starts it and a press ends it; nothing ends it on its own
/// except the system taking the microphone away.
@MainActor
final class VoiceCapture: ObservableObject {
    static let shared = VoiceCapture()

    @Published private(set) var recording = false

    private let recorder = Recorder()
    /// Started, microphone not open yet. A stop in this window cancels instead of sending.
    private var arming = false
    /// The recorder is still opening, so no second start may begin even after a cancel.
    private var opening = false
    /// Runs when the system takes the microphone mid-recording (Siri, a call).
    private var onTaken: (() -> Void)?

    private init() {
        recorder.onInterruption = { [weak self] began in
            guard began, let self, self.recording else { return }
            self.onTaken?()
        }
    }

    func start(onTaken: @escaping () -> Void, onFailure: @escaping @MainActor (Error) -> Void) {
        guard !recording, !opening else { return }
        recording = true
        self.onTaken = onTaken
        arming = true
        opening = true
        Task {
            defer { opening = false }
            do {
                try await recorder.start()
            } catch {
                arming = false
                reset()
                onFailure(error)
                return
            }
            guard arming else { recorder.cancel(); return }   // stopped while the microphone opened
            arming = false
            // Told the moment the microphone is actually live: words before this are not recorded.
            WKInterfaceDevice.current().play(.directionUp)
            recorder.cue()
        }
    }

    /// Ends the recording and hands back the clip; nil when the microphone never opened.
    func stop() -> Recorder.Clip? {
        guard recording else { return nil }
        reset()
        if arming { arming = false; return nil }
        return recorder.stop()
    }

    /// Ends the recording and throws it away.
    func cancel() {
        guard recording else { return }
        reset()
        if arming { arming = false; return }
        recorder.cancel()
    }

    private func reset() {
        recording = false
        onTaken = nil
    }
}

/// Turns a clip into words through the hub's owner-only route (`/api/cg/transcribe` in status-hub), the
/// same Groq Whisper as every other voice input. The hub knows the owner by this device's Anthropic key.
enum Transcriber {
    enum Failure: LocalizedError {
        case noKey
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .noKey: return "No API key"
            case .http(let code): return "Transcription failed (\(code))"
            }
        }
    }

    private static let url = URL(string: "https://jared-status-hub.fly.dev/api/cg/transcribe")!

    static func transcribe(_ clip: Recorder.Clip) async throws -> String {
        guard let key = APIKeyStore.current else { throw Failure.noKey }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 30
        r.setValue(key, forHTTPHeaderField: "X-Owner-Key")
        r.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await URLSession.shared.upload(for: r, fromFile: clip.url)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.http(code) }
        struct Body: Decodable { let transcript: String }
        return try JSONDecoder().decode(Body.self, from: data).transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The voice path's steps, written to `app_logs` under the same `interaction_id` as the question they
/// became, so a failed question shows every step from the press to the answer in one place. Kinds:
/// `voice_mic_failed`, `voice_cancelled`, `voice_recorded` (latency = how long it recorded, output = the clip size),
/// `voice_transcribed` (latency = the hub round trip, output = the words), `voice_transcribe_failed`,
/// `voice_empty` (the hub heard no words). A step that ends the path flushes; otherwise `ChatEngine`
/// flushes the whole interaction when it answers.
enum VoiceLog {
    static func record(_ kind: String, id: UUID, sessionId: String, output: String? = nil,
                       error: String? = nil, latencyMs: Int? = nil, ends: Bool = false) {
        Task {
            await AppLogger.shared.record(.init(
                timestamp: Date(), interactionId: id, sessionId: sessionId, backend: "watch:voice",
                kind: kind, toolName: nil, input: nil, output: output, error: error,
                latencyMs: latencyMs, tokensIn: nil, tokensOut: nil, userInput: nil, finalAnswer: nil))
            if ends { await AppLogger.shared.flush(id) }
        }
    }
}
