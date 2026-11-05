import Foundation
import BorderlessAudio
import BorderlessRelay

/// App-owned orchestration seams. Defaults are real adapters; tests supply only
/// generated PCM and in-memory relay events without permission or network work.
@MainActor
protocol CaptureSource: AnyObject {
    var state: PhoneMicrophone.State { get }
    func requestPermission() async -> Bool
    func start(maximumSeconds: Int) throws -> AsyncThrowingStream<Data, Error>
    func stop()
}

extension PhoneMicrophone: CaptureSource {}

protocol LiveRelay: Sendable {
    func connect(localToken: String, participant: RelayAudience, consent: Bool, context: [RelayContextTurn], languagePair: [String]) async throws
    func sendPCM(_ bytes: Data) async throws
    func finishInput() async throws
    func next() async throws -> RelayEvent
    func stop() async
}

extension RelayClient: LiveRelay {}
