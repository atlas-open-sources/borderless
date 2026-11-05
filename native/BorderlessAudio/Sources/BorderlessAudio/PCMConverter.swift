import AVFoundation
import Foundation

public enum AudioCaptureError: Error, Equatable, Sendable {
    case permissionRequired, alreadyCapturing, phoneMicrophoneUnavailable
    case unsupportedFormat, conversionFailed, consumerTooSlow, routeChanged, interrupted, engineFailed
}

/// A serial-use, streaming converter; does not access hardware or retain samples.
public final class PCMConverter {
    public static let sampleRate: Double = 24_000
    public static let maximumFrameBytes = 4_800
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    public init(inputFormat: AVAudioFormat) throws {
        guard (8_000...192_000).contains(inputFormat.sampleRate),
              (1...8).contains(inputFormat.channelCount),
              let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate,
                                         channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: output) else {
            throw AudioCaptureError.unsupportedFormat
        }
        self.inputFormat = inputFormat
        self.outputFormat = output
        self.converter = converter
    }

    public func convert(_ input: AVAudioPCMBuffer) throws -> [Data] {
        guard input.format == inputFormat, input.frameLength > 0, input.frameLength <= 4_096 else {
            throw AudioCaptureError.unsupportedFormat
        }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * Self.sampleRate / inputFormat.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw AudioCaptureError.conversionFailed
        }
        var supplied = false
        var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, result != .error else { throw AudioCaptureError.conversionFailed }
        guard output.frameLength > 0 else { return [] }
        guard let samples = output.int16ChannelData?[0] else { throw AudioCaptureError.conversionFailed }
        // Encode explicitly, rather than making a host-endianness assumption.
        var data = Data(capacity: Int(output.frameLength) * 2)
        for index in 0..<Int(output.frameLength) {
            var sample = samples[index].littleEndian
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }
        return stride(from: 0, to: data.count, by: Self.maximumFrameBytes).map {
            data.subdata(in: $0..<min(data.count, $0 + Self.maximumFrameBytes))
        }
    }
}
