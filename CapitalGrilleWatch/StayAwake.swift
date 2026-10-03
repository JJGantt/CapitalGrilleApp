import AVFoundation

/// **Keeps the app running, wrist down, until the answer is in.** A watch app keeps running in the
/// background only while it plays or records audio. Once a voice prompt's recording ends, the app still
/// has to transcribe it and wait on the model, and with the wrist down watchOS suspends it in the middle
/// of that: the answer's tap never comes, and the screen still says it is thinking when he looks. So
/// while the chat is thinking this plays SILENCE (mixed with others, so it interrupts nothing he is
/// listening to), and stops the moment it is not.
///
/// It does not make a dimmed screen redraw faster (watchOS caps that at about once a second); it keeps
/// the app working so the answer lands, and the wrist is tapped, on time.
@MainActor
final class StayAwake {
    static let shared = StayAwake()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var wired = false
    private var holding = false
    /// The most it holds for in one go, his number: past this an answer that has not come is not worth
    /// the battery to wait on awake, and the app goes back to being suspended as usual.
    private static let longest: TimeInterval = 60
    /// Counts each hold, so the cut-off for an earlier one cannot end a later one.
    private var hold = 0
    /// The minute ran out on this wait: nothing restarts the hold until the chat stops thinking.
    private var spent = false

    /// Told when the minute runs out with the chat still thinking, so the log shows the app was let go.
    var onExpired: (() -> Void)?

    private init() {}

    /// Holds while `on`, lets go when not. Called whenever the chat's thinking state changes.
    func set(_ on: Bool) {
        if !on { spent = false; stop() } else if !spent { start() }
    }

    private func start() {
        if holding && engine.isRunning { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if !wired {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: Self.silence.format)
                wired = true
            }
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(Self.silence, at: nil, options: .loops)
            player.play()
            if !holding {
                hold += 1
                let this = hold
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.longest))
                    guard let self, self.holding, self.hold == this else { return }
                    self.spent = true
                    self.stop()
                    self.onExpired?()
                }
            }
            holding = true
        } catch {
            VoiceLog.record("voice_stay_awake_failed", id: UUID(), sessionId: "",
                            error: String(describing: error), ends: true)
        }
    }

    private func stop() {
        guard holding else { return }
        holding = false
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A second of silence, looped.
    private static let silence: AVAudioPCMBuffer = {
        let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22050)!
        buffer.frameLength = buffer.frameCapacity   // zero-filled: silence
        return buffer
    }()
}
