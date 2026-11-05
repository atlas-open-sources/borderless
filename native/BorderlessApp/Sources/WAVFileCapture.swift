import Foundation
import BorderlessAudio

#if DEBUG
/// Debug-only stand-in for the phone microphone: streams a bundled 24 kHz mono PCM16 WAV as one capture,
/// paced in real time like the microphone. Device runs feed recorded speech this way, so nothing is ever
/// spoken out loud or captured from the room. Selected with `--capture-wav=<resource name>`.
@MainActor
final class WAVFileCapture: CaptureSource {
    private static let frameBytes = 4_800
    private static let frameDuration = Duration.milliseconds(100)

    private(set) var state: PhoneMicrophone.State = .idle
    private let url: URL
    private var feeder: Task<Void, Never>?

    init?(resource: String) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav") else { return nil }
        self.url = url
    }

    /// The launch argument `--capture-wav=<name>` picks the bundled file.
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> WAVFileCapture? {
        let prefix = "--capture-wav="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return WAVFileCapture(resource: String(argument.dropFirst(prefix.count)))
    }

    func requestPermission() async -> Bool { true }

    func start(maximumSeconds: Int) throws -> AsyncThrowingStream<Data, Error> {
        guard feeder == nil else { throw AudioCaptureError.alreadyCapturing }
        guard let pcm = Self.pcmSamples(in: try Data(contentsOf: url)) else { throw AudioCaptureError.unsupportedFormat }
        let limit = min(pcm.count, maximumSeconds * 24_000 * 2)
        let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(8))
        state = .capturing
        feeder = Task { [weak self] in
            var offset = pcm.startIndex
            let end = pcm.startIndex + limit
            while offset < end, !Task.isCancelled {
                let next = min(offset + Self.frameBytes, end)
                var frame = Data(pcm[offset..<next])
                if !frame.count.isMultiple(of: 2) { frame.removeLast() }
                if !frame.isEmpty { pair.continuation.yield(frame) }
                offset = next
                try? await Task.sleep(for: Self.frameDuration)
            }
            pair.continuation.finish()
            self?.finished()
        }
        pair.continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { @MainActor [weak self] in self?.stop() }
        }
        return pair.stream
    }

    /// The `data` chunk of a RIFF/WAVE file (other chunks such as LIST are skipped).
    static func pcmSamples(in file: Data) -> Data? {
        let bytes = [UInt8](file)
        guard bytes.count > 12, bytes[0..<4] == Array("RIFF".utf8)[...], bytes[8..<12] == Array("WAVE".utf8)[...] else { return nil }
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
            let size = bytes[offset + 4..<offset + 8].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            let body = offset + 8
            if id == "data" { return Data(bytes[body..<min(body + size, bytes.count)]) }
            offset = body + size + (size & 1)
        }
        return nil
    }

    func stop() {
        feeder?.cancel()
        feeder = nil
        state = .idle
    }

    private func finished() {
        feeder = nil
        state = .idle
    }
}
#endif
