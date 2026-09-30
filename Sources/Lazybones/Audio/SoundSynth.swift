import Foundation

/// The launcher's interface sounds.
enum UISound: CaseIterable {
    /// Focus moved: a warm, low "dum".
    case move
    /// A choice was made: a "dum-hit", the warm note plus a brighter, higher one that confirms it.
    case select
    /// Went a level deeper (opened an app or a screen): a note sliding up.
    case push
    /// Came back out a level: a note sliding down, and duller.
    case pop
}

/// Builds the interface sounds as samples, so the app ships no audio files. Pure: the same sound
/// always comes out the same, and `UISounds` only has to play it.
///
/// Each sound is made of "blips": a sine and a sub-octave under it, run through a low-pass filter
/// and shaped by a linear attack and an exponential decay. A higher cutoff lets more of the
/// sub-octave's harmonics through, for a brighter tone. Focus moves and selections are steady notes;
/// going deeper or back is a single note that glides up or down, so it can't be mistaken for a
/// selection's two notes.
enum SoundSynth {
    static let sampleRate = 44_100.0

    /// Pitches in Hz.
    enum Pitch {
        static let move = 320.0
        static let dum = 300.0
        static let hit = 490.0
        /// A push slides up a fifth; a pop slides down by about that.
        static let pushFrom = 280.0
        static let pushTo = 420.0
        static let popFrom = 380.0
        static let popTo = 250.0
    }

    /// Scales every blip's peak: audible without being insistent. The sub-octave adds about 45%, so
    /// this leaves plenty of headroom below 1.
    private static let master = 1.8
    private static let subLevel = 0.45

    private struct Blip {
        var start = 0.0
        var frequency: Double
        /// Seconds from `start` until the blip is cut off, by which point it has decayed to nothing.
        var duration: Double
        var peak: Double
        var cutoff = 750.0
        var attack = 0.025
        /// Where the pitch ends up, if it slides there over the first `glide` seconds.
        var endFrequency: Double?
        var glide = 0.0
    }

    static func samples(for sound: UISound) -> [Float] {
        switch sound {
        case .move:
            render([Blip(frequency: Pitch.move, duration: 0.16, peak: 0.022)])
        case .select:
            render([
                Blip(frequency: Pitch.dum, duration: 0.14, peak: 0.024),
                // The "hit": higher, later, softer to start and with a long tail.
                Blip(start: 0.13, frequency: Pitch.hit, duration: 0.32, peak: 0.045, cutoff: 1250, attack: 0.04),
            ])
        case .push:
            render([Blip(frequency: Pitch.pushFrom, duration: 0.3, peak: 0.032, cutoff: 850, attack: 0.04,
                         endFrequency: Pitch.pushTo, glide: 0.16)])
        case .pop:
            // A lower cutoff than the rest keeps the fall dull, where the push is bright.
            render([Blip(frequency: Pitch.popFrom, duration: 0.32, peak: 0.028, cutoff: 550, attack: 0.04,
                         endFrequency: Pitch.popTo, glide: 0.18)])
        }
    }

    // MARK: Rendering

    private static func render(_ blips: [Blip]) -> [Float] {
        let length = blips.map { $0.start + $0.duration }.max() ?? 0
        var out = [Double](repeating: 0, count: Int(length * sampleRate) + 1)
        for blip in blips { mix(blip, into: &out) }
        return out.map { Float(tanh($0)) }
    }

    private static func mix(_ blip: Blip, into out: inout [Double]) {
        let first = Int(blip.start * sampleRate)
        let count = min(Int(blip.duration * sampleRate), out.count - first)
        var filter = LowPass(cutoff: blip.cutoff, q: 0.7)
        var phase = 0.0
        let peak = blip.peak * master
        let floor = 0.0001
        for n in 0..<count {
            let t = Double(n) / sampleRate
            let envelope = t < blip.attack
                ? peak * t / blip.attack
                : peak * pow(floor / peak, (t - blip.attack) / (blip.duration - blip.attack))
            // A slide is even in musical terms, so it covers the same number of semitones per second.
            var frequency = blip.frequency
            if let end = blip.endFrequency, blip.glide > 0 {
                frequency *= pow(end / blip.frequency, min(t / blip.glide, 1))
            }
            phase += 2 * .pi * frequency / sampleRate
            let tone = sin(phase) + subLevel * sin(phase / 2)
            out[first + n] += filter.process(tone * envelope)
        }
    }

    /// A biquad low-pass, as the Web Audio spec defines it. Its Q is in decibels.
    private struct LowPass {
        private let b0, b1, b2, a1, a2: Double
        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        init(cutoff: Double, q: Double) {
            let w0 = 2 * Double.pi * cutoff / SoundSynth.sampleRate
            let alpha = sin(w0) / (2 * pow(10, q / 20))
            let c = cos(w0)
            let a0 = 1 + alpha
            b0 = (1 - c) / 2 / a0
            b1 = (1 - c) / a0
            b2 = b0
            a1 = -2 * c / a0
            a2 = (1 - alpha) / a0
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            return y
        }
    }
}
