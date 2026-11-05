import AVFoundation
import Foundation
import Testing
@testable import BorderlessAudio

private func buffer(frames: AVAudioFrameCount = 4_096) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                               channels: 2, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for channel in 0..<2 {
        for index in 0..<Int(frames) { buffer.floatChannelData![channel][index] = 0.25 }
    }
    return buffer
}

@Test func syntheticStereoConversionIsMonoPCM24k() throws {
    let input = buffer()
    let converter = try PCMConverter(inputFormat: input.format)
    let frames = try converter.convert(input)
    #expect(!frames.isEmpty)
    #expect(frames.allSatisfy { !$0.isEmpty && $0.count <= 4_800 && $0.count % 2 == 0 })
    let bytes = frames.reduce(Data(), +)
    // 48k stereo -> 24k mono; allow the converter's finite initial filter delay.
    #expect(bytes.count >= 3_900 && bytes.count <= 4_160)
    let values = stride(from: 0, to: bytes.count, by: 2).map {
        Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)
    }
    #expect(values.contains { abs(Int($0) - 8_192) < 100 })
}

@Test func slowConsumerFailsRatherThanDropsSilently() async throws {
    let input = buffer()
    let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(8))
    let pipe = try AudioFramePipe(format: input.format, seconds: 60,
                                  continuation: pair.continuation, ended: { _ in })
    for _ in 0..<12 { pipe.accept(input) }
    var received = 0
    do {
        for try await _ in pair.stream { received += 1 }
        Issue.record("Expected overflow failure")
    } catch { #expect(error as? AudioCaptureError == .consumerTooSlow) }
    #expect(received == 8)
}

@Test func stopEndsStreamAndRejectsSubsequentBuffers() async throws {
    let input = buffer()
    let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(8))
    let pipe = try AudioFramePipe(format: input.format, seconds: 60,
                                  continuation: pair.continuation, ended: { _ in })
    pipe.finish()
    pipe.accept(input)
    var count = 0
    for try await _ in pair.stream { count += 1 }
    #expect(count == 0)
}

@Test func durationBudgetClipsPreciselyAndFinishes() async throws {
    let input = buffer()
    // Unbounded only in this deterministic synthetic fixture so the duration
    // policy can be exercised independently of the production queue limit.
    let pair = AsyncThrowingStream<Data, Error>.makeStream()
    let pipe = try AudioFramePipe(format: input.format, seconds: 1,
                                  continuation: pair.continuation, ended: { _ in })
    for _ in 0..<20 { pipe.accept(input) }
    var total = 0
    for try await frame in pair.stream {
        #expect(frame.count <= 4_800 && frame.count % 2 == 0)
        total += frame.count
    }
    #expect(total == 48_000)
}
