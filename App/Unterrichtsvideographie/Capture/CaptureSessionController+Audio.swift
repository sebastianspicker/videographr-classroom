import AVFoundation
import Foundation
import GuidanceEngine
import QuartzCore
import SessionCore

extension CaptureSessionController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output is AVCaptureAudioDataOutput {
            processAudio(sampleBuffer)
            return
        }
        guard let generation = videoGeneration,
              let analysis = sampler.analyze(from: sampleBuffer)
        else { return }
        emitRuntime(.frame(generation, analysis))
    }

    private func processAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let context = audioContext(for: sampleBuffer),
              let metrics = audioMetrics(from: sampleBuffer, asbd: context.asbd, format: context.format)
        else { return }
        minimumObservedAudioAverage = min(minimumObservedAudioAverage ?? metrics.average, metrics.average)
        let dropoutDetected = updateAudioTiming(for: sampleBuffer, sampleRate: context.asbd.mSampleRate)
        let sample = makeAudioSample { values in
                values.peakLevel = metrics.peak
                values.averageLevel = metrics.average
                values.externalMicIndicated = audioUsesExternalMicrophone
                values.clippingFraction = metrics.clippingFraction
                values.channelCount = Int(context.asbd.mChannelsPerFrame)
                values.sampleRate = context.asbd.mSampleRate
                values.baselineLevelEstimate = minimumObservedAudioAverage
                values.dropoutDetected = dropoutDetected
            }
        accumulateAudio(sample, generation: context.generation)
        scheduleAudioDeliveryIfNeeded()
    }

    private func audioContext(
        for sampleBuffer: CMSampleBuffer
    ) -> (generation: Int, asbd: AudioStreamBasicDescription, format: PCMSampleFormat)? {
        guard let generation = audioGeneration,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = pcmSampleFormat(for: asbdPointer.pointee)
        else { return nil }
        return (generation, asbdPointer.pointee, format)
    }

    private func pcmSampleFormat(for asbd: AudioStreamBasicDescription) -> PCMSampleFormat? {
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        switch (asbd.mBitsPerChannel, isFloat) {
        case (16, false): return .int16
        case (32, true): return .float32
        case (32, false): return .int32
        default: return nil
        }
    }

    private func audioMetrics(
        from sampleBuffer: CMSampleBuffer,
        asbd: AudioStreamBasicDescription,
        format: PCMSampleFormat
    ) -> (peak: Double, average: Double, clippingFraction: Double?)? {
        var requiredSize = 0
        var blockBuffer: CMBlockBuffer?
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: reusableAudioBufferList.pointer,
            bufferListSize: reusableAudioBufferList.byteCount,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        if status == kCMSampleBufferError_ArrayTooSmall,
           requiredSize > reusableAudioBufferList.byteCount {
            reusableAudioBufferList.ensureCapacity(byteCount: requiredSize)
            blockBuffer = nil
            status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                bufferListSizeNeededOut: &requiredSize,
                bufferListOut: reusableAudioBufferList.pointer,
                bufferListSize: reusableAudioBufferList.byteCount,
                blockBufferAllocator: nil,
                blockBufferMemoryAllocator: nil,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }
        guard status == noErr else { return nil }
        return withExtendedLifetime(blockBuffer) {
            measuredAudioMetrics(from: reusableAudioBufferList.pointer, asbd: asbd, format: format)
        }
    }

    private func measuredAudioMetrics(
        from list: UnsafeMutablePointer<AudioBufferList>,
        asbd: AudioStreamBasicDescription,
        format: PCMSampleFormat
    ) -> (peak: Double, average: Double, clippingFraction: Double?) {
        var peak = 0.0
        var average = 0.0
        var clippedSamples = 0.0
        var measuredSamples = 0
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for buffer in buffers where buffer.mDataByteSize > 0 {
            guard let data = buffer.mData else { continue }
            let channels = max(1, Int(buffer.mNumberChannels == 0 ? asbd.mChannelsPerFrame : buffer.mNumberChannels))
            let metrics = PCMLevelMeter.metrics(
                bytes: data,
                byteCount: Int(buffer.mDataByteSize),
                format: format,
                channels: channels
            )
            peak = max(peak, metrics.peak)
            average = max(average, metrics.average)
            clippedSamples += metrics.clippedSampleFraction * Double(metrics.sampleCount)
            measuredSamples += metrics.sampleCount
        }
        return (
            peak,
            average,
            measuredSamples > 0 ? clippedSamples / Double(measuredSamples) : nil
        )
    }

    private func updateAudioTiming(for sampleBuffer: CMSampleBuffer, sampleRate: Float64) -> Bool {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let sampleDurationSeconds = sampleRate > 0
            ? Double(CMSampleBufferGetNumSamples(sampleBuffer)) / sampleRate
            : 0
        let duration = CMTime(seconds: sampleDurationSeconds, preferredTimescale: 1_000_000)
        let dropoutDetected = audioDropoutDetected(
            at: presentationTime,
            sampleDurationSeconds: sampleDurationSeconds
        )
        if presentationTime.isValid, duration.isValid {
            expectedNextAudioPresentationTime = CMTimeAdd(presentationTime, duration)
        }
        return dropoutDetected
    }

    private func audioDropoutDetected(at presentationTime: CMTime, sampleDurationSeconds: Double) -> Bool {
        guard presentationTime.isValid,
              let expected = expectedNextAudioPresentationTime,
              expected.isValid
        else { return false }
        let gap = CMTimeGetSeconds(CMTimeSubtract(presentationTime, expected))
        return gap.isFinite && gap > max(0.1, sampleDurationSeconds * 3)
    }

    private func accumulateAudio(_ sample: AudioLevelSample, generation: Int) {
        guard let previous = latestAudio, previous.generation == generation else {
            latestAudio = (generation, sample)
            return
        }
        latestAudio = (generation, mergedAudioSample(previous.sample, sample))
    }

    private func scheduleAudioDeliveryIfNeeded() {
        guard !audioDeliveryScheduled else { return }
        audioDeliveryScheduled = true
        let now = CACurrentMediaTime()
        let delay = max(0, lastAudioDeliveryTime + minimumAudioDeliveryInterval - now)
        audioQueue.asyncAfter(deadline: .now() + delay, execute: DispatchWorkItem { [weak self] in
            self?.deliverLatestAudio()
        })
    }

    private func deliverLatestAudio() {
        audioDeliveryScheduled = false
        guard let latest = latestAudio else { return }
        latestAudio = nil
        lastAudioDeliveryTime = CACurrentMediaTime()
        emitRuntime(.audio(latest.generation, latest.sample))
    }
}

func mergedAudioSample(_ previous: AudioLevelSample, _ latest: AudioLevelSample) -> AudioLevelSample {
    makeAudioSample { values in
        values.peakLevel = max(previous.peakLevel, latest.peakLevel)
        values.averageLevel = latest.averageLevel
        values.externalMicIndicated = latest.externalMicIndicated
        values.clippingFraction = maxOptional(previous.clippingFraction, latest.clippingFraction)
        values.channelCount = latest.channelCount
        values.sampleRate = latest.sampleRate
        values.baselineLevelEstimate = minOptional(
            previous.baselineLevelEstimate,
            latest.baselineLevelEstimate
        )
        values.dropoutDetected = previous.dropoutDetected || latest.dropoutDetected
        values.timestamp = latest.timestamp
    }
}

private func maxOptional(_ lhs: Double?, _ rhs: Double?) -> Double? {
    switch (lhs, rhs) {
    case let (left?, right?): return max(left, right)
    case let (left?, nil): return left
    case let (nil, right?): return right
    case (nil, nil): return nil
    }
}

private func minOptional(_ lhs: Double?, _ rhs: Double?) -> Double? {
    switch (lhs, rhs) {
    case let (left?, right?): return min(left, right)
    case let (left?, nil): return left
    case let (nil, right?): return right
    case (nil, nil): return nil
    }
}

final class ReusableAudioBufferList {
    private(set) var byteCount: Int
    private var storage: UnsafeMutableRawPointer

    var pointer: UnsafeMutablePointer<AudioBufferList> {
        storage.assumingMemoryBound(to: AudioBufferList.self)
    }

    init(maximumBuffers: Int) {
        byteCount = Self.requiredByteCount(maximumBuffers: maximumBuffers)
        storage = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        storage.bindMemory(to: AudioBufferList.self, capacity: 1)
    }

    static func requiredByteCount(maximumBuffers: Int) -> Int {
        let count = max(1, maximumBuffers)
        return MemoryLayout<AudioBufferList>.size
            + (count - 1) * MemoryLayout<AudioBuffer>.stride
    }

    func ensureCapacity(byteCount requiredByteCount: Int) {
        guard requiredByteCount > byteCount else { return }
        let replacement = UnsafeMutableRawPointer.allocate(
            byteCount: requiredByteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        replacement.bindMemory(to: AudioBufferList.self, capacity: 1)
        storage.deallocate()
        storage = replacement
        byteCount = requiredByteCount
    }

    deinit {
        storage.deallocate()
    }
}

func makeAudioSample(_ configure: (inout AudioLevelSample.Values) -> Void) -> AudioLevelSample {
    var values = AudioLevelSample.Values()
    configure(&values)
    return AudioLevelSample(values)
}
