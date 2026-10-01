import XCTest
@testable import Lazybones

final class SoundSynthTests: XCTestCase {
    /// How much of `frequency` the samples hold (Goertzel), as an amplitude.
    private func level(of frequency: Double, in samples: ArraySlice<Float>) -> Double {
        let w = 2 * Double.pi * frequency / SoundSynth.sampleRate
        var s1 = 0.0, s2 = 0.0
        for x in samples {
            let s = Double(x) + 2 * cos(w) * s1 - s2
            s2 = s1
            s1 = s
        }
        let power = s1 * s1 + s2 * s2 - 2 * cos(w) * s1 * s2
        return 2 * power.squareRoot() / Double(samples.count)
    }

    func testSoundsAreSoftAndEndInSilence() {
        for sound in UISound.allCases {
            let samples = SoundSynth.samples(for: sound)
            XCTAssertFalse(samples.isEmpty)
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) < 0.3 }, "\(sound) is soft")
            XCTAssertEqual(samples.first!, 0, accuracy: 0.001, "\(sound) starts at zero, so it can't click")
            XCTAssertEqual(samples.last!, 0, accuracy: 0.001, "\(sound) ends at zero")
        }
    }

    private func window(_ samples: [Float], _ from: Double, _ to: Double) -> ArraySlice<Float> {
        samples[Int(from * SoundSynth.sampleRate)..<Int(to * SoundSynth.sampleRate)]
    }

    func testMoveIsShortAndLow() {
        let move = SoundSynth.samples(for: .move)
        XCTAssertLessThan(Double(move.count) / SoundSynth.sampleRate, 0.3)
        let low = level(of: SoundSynth.Pitch.move, in: move[...])
        let high = level(of: SoundSynth.Pitch.hit, in: move[...])
        XCTAssertGreaterThan(low, high * 3)
    }

    func testSelectIsADumThenAHigherHit() {
        let move = SoundSynth.samples(for: .move)
        let select = SoundSynth.samples(for: .select)
        XCTAssertGreaterThan(select.count, move.count)
        let dum = window(select, 0.02, 0.12)
        XCTAssertGreaterThan(level(of: SoundSynth.Pitch.dum, in: dum), level(of: SoundSynth.Pitch.hit, in: dum) * 3)
        // By 200 ms the "dum" is gone and only the higher note is left.
        let tail = window(select, 0.2, 0.4)
        XCTAssertGreaterThan(level(of: SoundSynth.Pitch.hit, in: tail), 0.005)
        XCTAssertGreaterThan(level(of: SoundSynth.Pitch.hit, in: tail), level(of: SoundSynth.Pitch.dum, in: tail) * 5)
    }

    func testPushSlidesUpAndPopSlidesDown() {
        typealias P = SoundSynth.Pitch
        // Before the slide has got far, the note is near where it began; after it, where it ended.
        let push = SoundSynth.samples(for: .push)
        let pushStart = window(push, 0.03, 0.07), pushEnd = window(push, 0.2, 0.3)
        XCTAssertGreaterThan(level(of: P.pushFrom, in: pushStart), level(of: P.pushTo, in: pushStart))
        XCTAssertGreaterThan(level(of: P.pushTo, in: pushEnd), level(of: P.pushFrom, in: pushEnd) * 3)
        let pop = SoundSynth.samples(for: .pop)
        let popStart = window(pop, 0.03, 0.07), popEnd = window(pop, 0.22, 0.32)
        XCTAssertGreaterThan(level(of: P.popFrom, in: popStart), level(of: P.popTo, in: popStart))
        XCTAssertGreaterThan(level(of: P.popTo, in: popEnd), level(of: P.popFrom, in: popEnd) * 3)
        XCTAssertGreaterThan(P.pushTo, P.pushFrom)
        XCTAssertLessThan(P.popTo, P.popFrom)
    }

}

@MainActor
final class UISoundsTests: XCTestCase {
    func testDisabledSoundsDontPlay() {
        var played: [UISound] = []
        let sounds = UISounds(isEnabled: false) { played.append($0) }
        sounds.play(.move)
        sounds.isEnabled = true
        sounds.play(.select)
        XCTAssertEqual(played, [.select])
    }
}
