import AVFoundation

/// Plays the launcher's interface sounds (see `SoundSynth`) through the Mac's current output.
///
/// The audio engine is built when the first sound is due and then left running. A TV or receiver
/// on HDMI can take a moment to wake for new audio, and would swallow the start of a sound short
/// enough to be over by then.
@MainActor
final class UISounds {
    var isEnabled: Bool {
        didSet {
            if isEnabled, !oldValue { prepare() }
        }
    }

    /// Stands in for the audio engine, for tests.
    private let sink: ((UISound) -> Void)?
    private var output: Output?

    init(isEnabled: Bool = true, sink: ((UISound) -> Void)? = nil) {
        self.isEnabled = isEnabled
        self.sink = sink
    }

    func play(_ sound: UISound) {
        guard isEnabled else { return }
        if let sink { sink(sound) } else { engine().play(sound) }
    }

    /// Starts the audio engine ahead of the first sound, so that one isn't late.
    func prepare() {
        guard isEnabled, sink == nil else { return }
        _ = engine()
    }

    private func engine() -> Output {
        if let output { return output }
        let output = Output()
        self.output = output
        return output
    }

    /// The audio engine and the voices it plays on.
    private final class Output {
        private let engine = AVAudioEngine()
        private let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1)!
        /// Consecutive sounds take turns, so one starting doesn't cut the tail off the last.
        private var voices: [AVAudioPlayerNode] = []
        private var next = 0
        private var buffers: [UISound: AVAudioPCMBuffer] = [:]
        private var configurationChange: NSObjectProtocol?

        init() {
            for sound in UISound.allCases { buffers[sound] = buffer(for: sound) }
            for _ in 0..<6 {
                let voice = AVAudioPlayerNode()
                engine.attach(voice)
                engine.connect(voice, to: engine.mainMixerNode, format: format)
                voices.append(voice)
            }
            // Switching the Mac's output (Control Center does) stops the engine; bring it back.
            configurationChange = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.start() }
            }
            start()
        }

        deinit {
            if let configurationChange { NotificationCenter.default.removeObserver(configurationChange) }
        }

        func play(_ sound: UISound) {
            guard let buffer = buffers[sound] else { return }
            if !engine.isRunning { start() }
            guard engine.isRunning else { return }
            let voice = voices[next]
            next = (next + 1) % voices.count
            // A stopped engine leaves its voices stopped.
            if !voice.isPlaying { voice.play() }
            voice.scheduleBuffer(buffer)
        }

        private func start() {
            guard !engine.isRunning else { return }
            do {
                try engine.start()
            } catch {
                NSLog("Lazybones: could not start interface sounds (\(error))")
            }
        }

        private func buffer(for sound: UISound) -> AVAudioPCMBuffer? {
            let samples = SoundSynth.samples(for: sound)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return nil }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            for (i, sample) in samples.enumerated() { channel[i] = sample }
            return buffer
        }
    }
}
