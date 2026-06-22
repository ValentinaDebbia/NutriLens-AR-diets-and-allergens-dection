import AVFoundation
import Foundation

// MARK: - Sound Manager
// genera WAV PCM in memoria e li riproduce con AVAudioPlayer

final class SoundManager {
    static let shared = SoundManager()

    private var player: AVAudioPlayer?
    private let sampleRate: Int = 44100

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - API pubblica
    // riproduce un suono diverso in base allo stato sicurezza del prodotto.
    func play(for status: Product.SafetyStatus) {
        switch status {
        case .safe:    playSafe()
        case .warning: playWarning()
        case .danger:  playDanger()
        }
    }

    // MARK: - Verde: arpeggio ascendente Do6 → Mi6 → Sol6, brillante

    private func playSafe() {
        struct Note { let freq: Double; let start: Double; let dur: Double }
        let notes = [
            Note(freq: 1046.50, start: 0.00, dur: 0.18),
            Note(freq: 1318.51, start: 0.14, dur: 0.18),
            Note(freq: 1567.98, start: 0.28, dur: 0.30),
        ]
        let total = 0.60
        let samples = makeSamples(duration: total) { t in
            var s: Double = 0
            for n in notes {
                let lt = t - n.start
                guard lt >= 0, lt < n.dur else { continue }
                let env = adsr(lt, a: 0.01, d: 0.05, s: 0.7, r: 0.08, total: n.dur)
                let f = n.freq
                s += env * (0.55 * sin(2 * .pi * f       * lt)
                          + 0.25 * sin(2 * .pi * f * 2.0 * lt)
                          + 0.12 * sin(2 * .pi * f * 3.0 * lt)
                          + 0.05 * sin(2 * .pi * f * 4.0 * lt))
            }
            return s * 0.5
        }
        playWAV(samples)
    }

    // MARK: - Giallo: singola nota Mi5, morbida e breve

    private func playWarning() {
        let freq = 659.25
        let dur  = 0.35
        let samples = makeSamples(duration: dur) { t in
            let env = adsr(t, a: 0.04, d: 0.10, s: 0.5, r: 0.15, total: dur)
            return env * (0.65 * sin(2 * .pi * freq       * t)
                        + 0.20 * sin(2 * .pi * freq * 2.0 * t)
                        + 0.08 * sin(2 * .pi * freq * 3.0 * t)) * 0.40
        }
        playWAV(samples)
    }

    // MARK: - Rosso: doppio colpo grave + dissonanza (La3 + Mib3)

    private func playDanger() {
        struct Pulse { let f1, f2, start, dur: Double }
        let pulses = [
            Pulse(f1: 220.00, f2: 155.56, start: 0.00, dur: 0.22),
            Pulse(f1: 220.00, f2: 155.56, start: 0.28, dur: 0.22),
        ]
        let total = 0.55
        let samples = makeSamples(duration: total) { t in
            var s: Double = 0
            for p in pulses {
                let lt = t - p.start
                guard lt >= 0, lt < p.dur else { continue }
                let env = adsr(lt, a: 0.005, d: 0.08, s: 0.6, r: 0.07, total: p.dur)
                let raw = env * (0.50 * sin(2 * .pi * p.f1       * lt)
                               + 0.30 * sin(2 * .pi * p.f2       * lt)
                               + 0.12 * sin(2 * .pi * p.f1 * 2.0 * lt)
                               + 0.06 * sin(2 * .pi * p.f2 * 3.0 * lt))
                s += tanh(raw * 2.5) * 0.45
            }
            return s * 0.65
        }
        playWAV(samples)
    }

    private func adsr(_ t: Double, a: Double, d: Double,
                      s: Double, r: Double, total: Double) -> Double {
        let rel = total - r
        if      t < a         { return t / a }
        else if t < a + d     { return 1.0 - (1.0 - s) * ((t - a) / d) }
        else if t < rel       { return s }
        else                  { return s * max(0, (total - t) / r) }
    }

    // MARK: - Generazione campioni

    private func makeSamples(duration: Double,
                              builder: (Double) -> Double) -> [Int16] {
        let count = Int(Double(sampleRate) * duration)
        var out   = [Int16](repeating: 0, count: count)
        for i in 0 ..< count {
            let t   = Double(i) / Double(sampleRate)
            let val = max(-1.0, min(1.0, builder(t)))
            out[i]  = Int16(val * 32767)
        }
        return out
    }

    // MARK: - Costruzione WAV e riproduzione

    private func playWAV(_ samples: [Int16]) {
        guard let data = buildWAV(samples) else { return }
        do {
            player = try AVAudioPlayer(data: data)
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("⚠️ SoundManager: \(error)")
        }
    }

    // costruisce un WAV PCM 16-bit mono in-memory.
    private func buildWAV(_ samples: [Int16]) -> Data? {
        let sr        = UInt32(sampleRate)
        let numSamp   = UInt32(samples.count)
        let dataSize  = numSamp * 2          // 16-bit = 2 byte/campione
        let fileSize  = dataSize + 36        // header RIFF = 44 byte totali

        var data = Data()
        data.reserveCapacity(Int(fileSize) + 8)

        func append(_ v: UInt32) {
            var le = v.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Array($0) })
        }
        func append(_ v: UInt16) {
            var le = v.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Array($0) })
        }

        data.append(contentsOf: "RIFF".utf8)
        append(fileSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt  chunk
        data.append(contentsOf: "fmt ".utf8)
        append(UInt32(16))   // chunk size
        append(UInt16(1))    // PCM
        append(UInt16(1))    // mono
        append(sr)           // sample rate
        append(sr * 2)       // byte rate
        append(UInt16(2))    // block align
        append(UInt16(16))   // bits per sample

        // data chunk
        data.append(contentsOf: "data".utf8)
        append(dataSize)
        for s in samples {
            var le = s.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Array($0) })
        }
        return data
    }
}
