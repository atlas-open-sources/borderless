import AVFoundation
import Foundation

/// The callback path is synchronous and bounded: no task per audio frame.
/// Only terminal failure/completion schedules owner cleanup.
final class AudioFramePipe: @unchecked Sendable {
    typealias Continuation = AsyncThrowingStream<Data, Error>.Continuation
    private let lock = NSLock()
    private var active = true
    private var bytes = 0
    private let byteLimit: Int
    private let converter: PCMConverter
    private let continuation: Continuation
    private let ended: @Sendable (AudioCaptureError?) -> Void

    init(format: AVAudioFormat, seconds: Int, continuation: Continuation,
         ended: @escaping @Sendable (AudioCaptureError?) -> Void) throws {
        converter = try PCMConverter(inputFormat: format)
        byteLimit = seconds * 48_000
        self.continuation = continuation
        self.ended = ended
    }

    func accept(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard active else { return }
            do {
                for frame in try converter.convert(buffer) {
                    let allowed = min(frame.count, byteLimit - bytes)
                    guard allowed > 0 else { finishLocked(nil); return }
                    let bounded = Data(frame.prefix(allowed))
                    switch continuation.yield(bounded) {
                    case .enqueued: bytes += bounded.count
                    case .dropped: finishLocked(.consumerTooSlow); return
                    case .terminated: finishLocked(nil); return
                    @unknown default: finishLocked(.consumerTooSlow); return
                    }
                    if bytes >= byteLimit { finishLocked(nil); return }
                }
            } catch { finishLocked(.conversionFailed) }
        }
    }

    func finish(_ error: AudioCaptureError? = nil) { lock.withLock { finishLocked(error) } }

    private func finishLocked(_ error: AudioCaptureError?) {
        guard active else { return }
        active = false
        if let error { continuation.finish(throwing: error) }
        else { continuation.finish() }
        ended(error)
    }
}
