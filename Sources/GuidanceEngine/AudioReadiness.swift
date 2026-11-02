import Foundation

/// Instantaneous / short-window audio metrics (0...1 normalized peak and mean per-frame peak amplitude).
public struct AudioLevelSample: Equatable, Sendable {
    public struct Values: Sendable {
        public var peakLevel = 0.0
        public var averageLevel = 0.0
        public var externalMicIndicated = false
        public var clippingFraction: Double?
        public var channelCount: Int?
        public var sampleRate: Double?
        public var baselineLevelEstimate: Double?
        public var dropoutDetected = false
        public var timestamp = Date()

        public init() {}
    }

    /// Peak amplitude 0...1
    public var peakLevel: Double
    /// Average level 0...1 over a short window
    public var averageLevel: Double
    /// True if an external route is indicated by the capture stack (or synthetic flag in tests).
    public var externalMicIndicated: Bool
    /// Fraction of scalar PCM samples at or above the meter's digital clipping threshold.
    public var clippingFraction: Double?
    /// Channel count reported by the current audio buffer.
    public var channelCount: Int?
    /// Sample rate reported by the current audio format.
    public var sampleRate: Double?
    /// Lowest short-window average observed during the current capture run; not a calibrated noise floor.
    public var baselineLevelEstimate: Double?
    /// True when presentation timestamps reveal a discontinuity larger than the allowed buffer gap.
    public var dropoutDetected: Bool
    public var timestamp: Date

    public init(_ values: Values = Values()) {
        peakLevel = min(1, max(0, values.peakLevel))
        averageLevel = min(1, max(0, values.averageLevel))
        externalMicIndicated = values.externalMicIndicated
        clippingFraction = values.clippingFraction.map { min(1, max(0, $0)) }
        channelCount = values.channelCount.map { max(1, $0) }
        sampleRate = values.sampleRate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        baselineLevelEstimate = values.baselineLevelEstimate.map { min(1, max(0, $0)) }
        dropoutDetected = values.dropoutDetected
        timestamp = values.timestamp
    }
}

/// Coarse audio quality bucket for readiness and mid-take banners.
public enum AudioStatus: String, Equatable, Sendable {
    case silent
    case low
    case good
    case hot
    case clipping
    case dropout
}

/// User-facing audio evaluation result (German copy for Live).
public struct AudioGuidance: Equatable, Sendable {
    public var status: AudioStatus
    public var message: String
    public var actionHint: String
    public var isReady: Bool

    public init(status: AudioStatus, message: String, actionHint: String, isReady: Bool) {
        self.status = status
        self.message = message
        self.actionHint = actionHint
        self.isReady = isReady
    }
}

/// PCM sample formats commonly seen on AVCapture audio buffers.
public enum PCMSampleFormat: Equatable, Sendable {
    case int16
    /// IEEE float samples already in approximately -1...1.
    case float32
    case int32
}

/// Direct metrics from one PCM buffer. No speech, noise-source, or pedagogical inference is made.
public struct PCMLevelMetrics: Equatable, Sendable {
    public var peak: Double
    public var average: Double
    public var clippedSampleFraction: Double
    public var sampleCount: Int

    public init(peak: Double, average: Double, clippedSampleFraction: Double, sampleCount: Int) {
        self.peak = min(1, max(0, peak))
        self.average = min(1, max(0, average))
        self.clippedSampleFraction = min(1, max(0, clippedSampleFraction))
        self.sampleCount = max(0, sampleCount)
    }

    public static let empty = PCMLevelMetrics(peak: 0, average: 0, clippedSampleFraction: 0, sampleCount: 0)
}

/// Pure peak/average extraction from raw PCM bytes (no AVFoundation).
/// Correctly sizes samples by format - never treat float32 as Int16.
public enum PCMLevelMeter {
    private struct Input {
        let byteCount: Int
        let channels: Int
        let bytes: UnsafeRawPointer
    }
    /// - Parameters:
    ///   - bytes: raw interleaved PCM payload
    ///   - format: sample encoding
    ///   - channels: channel count (≥1); levels use max abs across channels per frame, then average over frames
    /// - Returns: (peak, average) each in 0...1
    public static func levels(
        bytes: UnsafeRawPointer,
        byteCount: Int,
        format: PCMSampleFormat,
        channels: Int = 1
    ) -> (peak: Double, average: Double) {
        let metrics = metrics(bytes: bytes, byteCount: byteCount, format: format, channels: channels)
        return (metrics.peak, metrics.average)
    }

    /// Extracts level and direct clipping evidence from a PCM payload.
    public static func metrics(
        bytes: UnsafeRawPointer,
        byteCount: Int,
        format: PCMSampleFormat,
        channels: Int = 1
    ) -> PCMLevelMetrics {
        let ch = max(1, channels)
        switch format {
        case .int16:
            return metrics(for: Int16.self, input: Input(byteCount: byteCount, channels: ch, bytes: bytes)) { sample in
                Double(abs(Int(sample))) / Double(Int16.max)
            }
        case .float32:
            return metrics(for: Float32.self, input: Input(byteCount: byteCount, channels: ch, bytes: bytes)) { sample in
                let magnitude = Double(abs(sample))
                return magnitude.isFinite ? min(1.0, magnitude) : 1.0
            }
        case .int32:
            return metrics(for: Int32.self, input: Input(byteCount: byteCount, channels: ch, bytes: bytes)) { sample in
                Double(abs(Int64(sample))) / Double(Int32.max)
            }
        }
    }

    /// Convenience for contiguous `[UInt8]` buffers (tests).
    public static func levels(
        data: [UInt8],
        format: PCMSampleFormat,
        channels: Int = 1
    ) -> (peak: Double, average: Double) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return (0, 0) }
            return levels(bytes: base, byteCount: raw.count, format: format, channels: channels)
        }
    }

    public static func metrics(
        data: [UInt8],
        format: PCMSampleFormat,
        channels: Int = 1
    ) -> PCMLevelMetrics {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return .empty }
            return metrics(bytes: base, byteCount: raw.count, format: format, channels: channels)
        }
    }

    private static func reduceMetrics(
        sampleCount: Int,
        channels: Int,
        sampleAt: (Int) -> Double
    ) -> PCMLevelMetrics {
        let frames = sampleCount / channels
        guard frames > 0 else { return .empty }
        var peak = 0.0
        var sum = 0.0
        var clippedSamples = 0
        for f in 0..<frames {
            var framePeak = 0.0
            for c in 0..<channels {
                let v = sampleAt(f * channels + c)
                if v >= 0.999 { clippedSamples += 1 }
                framePeak = max(framePeak, v)
            }
            peak = max(peak, framePeak)
            sum += framePeak
        }
        let measuredSamples = frames * channels
        return PCMLevelMetrics(
            peak: peak,
            average: sum / Double(frames),
            clippedSampleFraction: Double(clippedSamples) / Double(measuredSamples),
            sampleCount: measuredSamples
        )
    }

    private static func metrics<Sample>(
        for _: Sample.Type,
        input: Input,
        normalizedValue: (Sample) -> Double
    ) -> PCMLevelMetrics {
        let sampleCount = input.byteCount / MemoryLayout<Sample>.size
        guard sampleCount > 0 else { return .empty }
        return reduceMetrics(sampleCount: sampleCount, channels: input.channels) { index in
            let sample = input.bytes.loadUnaligned(
                fromByteOffset: index * MemoryLayout<Sample>.size,
                as: Sample.self
            )
            return normalizedValue(sample)
        }
    }
}

/// Pure audio readiness (Derry: audio priority). Thresholds unit-testable without AVAudio.
public struct AudioReadinessEvaluator: Sendable {
    public var silentMax: Double
    public var lowMax: Double
    public var goodMax: Double
    public var hotMax: Double

    public init(
        silentMax: Double = 0.02,
        lowMax: Double = 0.08,
        goodMax: Double = 0.55,
        hotMax: Double = 0.85
    ) {
        self.silentMax = silentMax
        self.lowMax = lowMax
        self.goodMax = goodMax
        self.hotMax = hotMax
    }

    public static let `default` = AudioReadinessEvaluator()

    /// Seconds after which a measured sample counts as stale (no new audio buffer).
    static let staleAfterSeconds: TimeInterval = 2

    public func evaluate(_ sample: AudioLevelSample, at now: Date = Date()) -> AudioGuidance {
        // A sample with channel/sample-rate data came from a real buffer; default samples have neither.
        let isMeasured = sample.channelCount != nil || sample.sampleRate != nil
        if isMeasured, now.timeIntervalSince(sample.timestamp) > Self.staleAfterSeconds {
            return AudioGuidance(status: .dropout, message: "Seit über 2 s kein neuer Audiopuffer.", actionHint: "Audioroute und Kabel prüfen; eine kurze Aufnahme abhören.", isReady: false)
        }
        if sample.dropoutDetected {
            return AudioGuidance(status: .dropout, message: "Zeitstempel-Lücke im Audiosignal erkannt.", actionHint: "Audioroute und Kabel prüfen; eine kurze Aufnahme abhören.", isReady: false)
        }
        if sample.clippingFraction.map({ $0 > 0 }) == true {
            return AudioGuidance(status: .clipping, message: "Digitale Vollaussteuerung in PCM-Samples erkannt.", actionHint: "Pegel reduzieren und eine kurze Aufnahme abhören.", isReady: false)
        }
        return levelGuidance(
            for: max(sample.peakLevel, sample.averageLevel),
            externalMicIndicated: sample.externalMicIndicated
        )
    }

    private func levelGuidance(for level: Double, externalMicIndicated: Bool) -> AudioGuidance {
        let status = levelStatus(for: level)
        if status == .silent {
            return silentGuidance(externalMicIndicated: externalMicIndicated)
        }
        return nonSilentGuidance(for: status, externalMicIndicated: externalMicIndicated)
    }

    private func nonSilentGuidance(for status: LevelStatus, externalMicIndicated: Bool) -> AudioGuidance {
        if status == .low {
            return AudioGuidance(status: .low, message: "Gemessener Audiopegel liegt unter dem konfigurierten Arbeitsbereich.", actionHint: "Route, Abstand und Gain prüfen; anschließend eine kurze Aufnahme abhören.", isReady: false)
        }
        if status == .good {
            return goodGuidance(externalMicIndicated: externalMicIndicated)
        }
        if status == .hot {
            return AudioGuidance(status: .hot, message: "Audiopegel hoch - Gefahr von Verzerrung bei Lautstärkespitzen.", actionHint: "Gain etwas reduzieren.", isReady: true)
        }
        return AudioGuidance(status: .hot, message: "Sehr hoher Audiopegel; ohne PCM-Vollaussteuerung ist digitales Clipping nicht belegt.", actionHint: "Gain reduzieren und eine kurze Aufnahme abhören.", isReady: false)
    }

    private func levelStatus(for level: Double) -> LevelStatus {
        let thresholds: [(Double, LevelStatus)] = [
            (silentMax, .silent), (lowMax, .low), (goodMax, .good), (hotMax, .hot)
        ]
        return thresholds.first(where: { level <= $0.0 })?.1 ?? .tooHot
    }

    private func silentGuidance(externalMicIndicated: Bool) -> AudioGuidance {
        let action = externalMicIndicated
            ? "Pegel am externen Mikrofon / Interface prüfen."
            : "Mikrofonroute prüfen und eine kurze Aufnahme abhören."
        return AudioGuidance(status: .silent, message: "Sehr niedriger gemessener Audiopegel.", actionHint: action, isReady: false)
    }

    private func goodGuidance(externalMicIndicated: Bool) -> AudioGuidance {
        let message = externalMicIndicated
            ? "Audiopegel im konfigurierten Arbeitsbereich."
            : "Audiopegel im konfigurierten Arbeitsbereich. Internes Mikrofon aktiv - externes Audio bleibt empfehlenswert."
        return AudioGuidance(status: .good, message: message, actionHint: "Die Verständlichkeit wird nicht gemessen; eine kurze Aufnahme abhören.", isReady: true)
    }

    private enum LevelStatus: Equatable {
        case silent
        case low
        case good
        case hot
        case tooHot
    }
}
