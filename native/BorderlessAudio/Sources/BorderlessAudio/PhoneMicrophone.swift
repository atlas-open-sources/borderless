#if os(iOS)
import AVFoundation
import Foundation
import Observation

/// Foreground phone-microphone capture only. No init-time permission or capture,
/// file recording, playback, network client, Bluetooth route or background mode.
@MainActor @Observable
public final class PhoneMicrophone {
    public enum State: Equatable, Sendable { case idle, capturing, failed(AudioCaptureError) }
    public private(set) var state: State = .idle
    public private(set) var permissionGranted = false
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var pipe: AudioFramePipe?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private var tapInstalled = false

    public init() {}

    isolated deinit { stop() }

    /// Call only from the user's explicit microphone/permission action.
    @discardableResult public func requestPermission() async -> Bool {
        permissionGranted = await AVAudioApplication.requestRecordPermission()
        return permissionGranted
    }

    /// Returns a stream with eight buffered frames maximum. Overflow terminates
    /// capture visibly instead of dropping speech. Consume in a structured task
    /// and call stop() in its cancellation handler/defer.
    public func start(maximumSeconds: Int = 60) throws -> AsyncThrowingStream<Data, Error> {
        guard permissionGranted else { throw AudioCaptureError.permissionRequired }
        guard engine == nil else { throw AudioCaptureError.alreadyCapturing }
        guard (1...60).contains(maximumSeconds) else { throw AudioCaptureError.unsupportedFormat }
        generation &+= 1
        let epoch = generation
        let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(8))
        pair.continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == epoch else { return }
                self.stop()
            }
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setPreferredSampleRate(24_000)
            try session.setActive(true)
            sessionActive = true
            guard let phone = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
                throw AudioCaptureError.phoneMicrophoneUnavailable
            }
            try session.setPreferredInput(phone)
            guard session.currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) else {
                throw AudioCaptureError.phoneMicrophoneUnavailable
            }
            let engine = AVAudioEngine()
            self.engine = engine
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            let pipe = try AudioFramePipe(format: format, seconds: maximumSeconds,
                                         continuation: pair.continuation) { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == epoch else { return }
                    self.stop(error: error)
                }
            }
            self.pipe = pipe
            node.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in pipe.accept(buffer) }
            tapInstalled = true
            try engine.start()
            state = .capturing
            observe(AVAudioSession.routeChangeNotification, error: .routeChanged, epoch: epoch)
            observe(AVAudioSession.interruptionNotification, error: .interrupted, epoch: epoch)
            observe(AVAudioSession.mediaServicesWereResetNotification, error: .engineFailed, epoch: epoch)
            timer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(maximumSeconds)) } catch { return }
                guard let self, self.generation == epoch else { return }
                self.stop()
            }
            return pair.stream
        } catch {
            let failure = error as? AudioCaptureError ?? .engineFailed
            stop(error: failure)
            pair.continuation.finish(throwing: failure)
            throw failure
        }
    }

    public func stop() { stop(error: nil) }

    private func stop(error: AudioCaptureError?) {
        generation &+= 1
        timer?.cancel(); timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        if let engine {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        }
        tapInstalled = false
        engine = nil
        pipe?.finish(error); pipe = nil
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
        if let error { state = .failed(error) } else { state = .idle }
    }

    private func observe(_ name: Notification.Name, error: AudioCaptureError, epoch: UInt64) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == epoch else { return }
                self.stop(error: error)
            }
        })
    }
}
#endif
