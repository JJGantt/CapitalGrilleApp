import Foundation
import WatchKit

/// The microphone for a question, recorded the way StatusHub's watch records a command
/// (status-hub/apps/Watch/Capture.swift): the recording ends itself once he has spoken and then gone
/// quiet for `hang` seconds, and a second press locks it open so only a press ends it.
@MainActor
final class VoiceCapture: ObservableObject {
    static let shared = VoiceCapture()

    @Published private(set) var recording = false
    /// Locked open: the silence no longer ends it, only a press does.
    @Published private(set) var locked = false

    /// Seconds of trailing silence that end an unlocked recording. Shorter than the hub's (whose
    /// `watch_silence_s` is 5): a question here is short, and a pause that cuts one off is the cue to lock.
    private static let hang: TimeInterval = 4
    /// The lowest level that counts as his voice whatever the room's floor — StatusHub's
    /// `watch_speech_min` default, tuned there from real clips.
    private static let speechMin: Float = 0.02
    /// Audio nobody has spoken in, after which an unlocked recording is thrown away rather than left
    /// holding the microphone.
    private static let unspoken: TimeInterval = 15

    private let recorder = Recorder()
    /// Started, microphone not open yet. A stop in this window cancels instead of sending.
    private var arming = false
    /// The recorder is still opening, so no second start may begin even after a cancel.
    private var opening = false
    private var endpoint = Endpointer(hang: VoiceCapture.hang, minimum: VoiceCapture.speechMin)
    private var segment: TimeInterval = 0
    /// Runs when the silence ends the recording: the owner sends it as if it had been pressed.
    private var onSilence: (() -> Void)?
    /// Runs when the system takes the microphone mid-recording (Siri, a call).
    private var onTaken: (() -> Void)?

    private init() {
        recorder.onLevel = { [weak self] level, seconds in self?.heard(level, seconds) }
        recorder.onInterruption = { [weak self] began in self?.interrupted(began) }
    }

    func start(onSilence: @escaping () -> Void, onTaken: @escaping () -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) {
        guard !recording, !opening else { return }
        recording = true
        locked = false
        self.onSilence = onSilence
        self.onTaken = onTaken
        endpoint = Endpointer(hang: Self.hang, minimum: Self.speechMin)
        segment = 0
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

    func toggleLock() {
        guard recording else { return }
        locked.toggle()
    }

    private func reset() {
        recording = false
        locked = false
        onSilence = nil
        onTaken = nil
    }

    /// The system took the microphone. Words already recorded are still worth sending.
    private func interrupted(_ began: Bool) {
        guard began, recording else { return }
        if endpoint.heard, let taken = onTaken { taken() } else { cancel() }
    }

    private func heard(_ level: Float, _ seconds: TimeInterval) {
        guard recording, !arming else { return }   // nothing counts until the mic is open
        let ended = endpoint.feed(level, seconds)
        segment += seconds
        if !locked && !endpoint.heard && segment >= Self.unspoken {
            cancel()
            return
        }
        if ended && !locked { onSilence?() }
    }
}

/// When an utterance is over, decided as StatusHub's watch decides it: the room's floor is the quietest
/// buffer so far, speech is anything 2.5x above it (and above `minimum` whatever the floor), and once
/// speech has been heard, `hang` seconds below that line end it. Before any speech nothing ends.
struct Endpointer {
    /// Speech has to last this long before an utterance has begun. One buffer over the line is not
    /// speech: a lone blip followed by silence goes up as "Thank you.", which is what Whisper writes
    /// for silence.
    static let minSpeech: TimeInterval = 0.4

    let hang: TimeInterval
    let minimum: Float
    private(set) var floor: Float = .infinity
    private(set) var heard = false
    private var spoken: TimeInterval = 0
    private var quiet: TimeInterval = 0

    init(hang: TimeInterval, minimum: Float) { self.hang = hang; self.minimum = minimum }

    var threshold: Float { max(floor * 2.5, minimum) }

    /// Takes one buffer's level and length; true when that buffer ended the utterance.
    mutating func feed(_ level: Float, _ seconds: TimeInterval) -> Bool {
        floor = min(floor, level)
        if level >= threshold {
            spoken += seconds
            if spoken >= Self.minSpeech { heard = true }
            quiet = 0
            return false
        }
        quiet += seconds
        guard heard else {
            if quiet >= hang { spoken = 0 }   // a gap ends a run of speech too short to have counted
            return false
        }
        return quiet >= hang
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
