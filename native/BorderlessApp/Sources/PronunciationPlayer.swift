import AVFoundation
import Foundation
import Observation

@MainActor
protocol PronunciationPlaying: AnyObject {
    var status: String { get }
    func speak(_ text: String, language: String)
    func stop()
}

/// Local speech only, gated to the user's currently selected personal output.
/// Called only outside capture; owns playback activation until stop or completion.
@MainActor @Observable
final class PronunciationPlayer: NSObject, PronunciationPlaying, AVSpeechSynthesizerDelegate {
    private(set) var status = "Connect headphones or Bluetooth audio to hear a reply privately."
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private var sessionActive = false

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        for name in [AVAudioSession.routeChangeNotification, AVAudioSession.interruptionNotification,
                     AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                let categoryChange = notification.name == AVAudioSession.routeChangeNotification &&
                    (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.categoryChange.rawValue
                Task { @MainActor [weak self] in
                    guard let self, self.sessionActive else { return }
                    // Our own playback category transition is rechecked synchronously below.
                    if categoryChange && Self.personalOutputsOnly(AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)) { return }
                    self.stop()
                    self.status = "Audio changed. Select the reply again when your headphones are ready."
                }
            })
        }
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        synthesizer.stopSpeaking(at: .immediate)
        if sessionActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    static func personalOutputsOnly(_ outputs: [AVAudioSession.Port]) -> Bool {
        let allowed: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        return !outputs.isEmpty && outputs.allSatisfy { allowed.contains($0) }
    }

    func speak(_ text: String, language: String) {
        stop()
        guard Self.personalOutputsOnly(AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)) else {
            status = "Connect headphones or Bluetooth audio first. The phone speaker is not used."
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let voice = AVSpeechSynthesisVoice(language: language) else {
            status = "A local Spanish voice is unavailable."
            return
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            try audioSession.setActive(true)
            sessionActive = true
            guard Self.personalOutputsOnly(audioSession.currentRoute.outputs.map(\.portType)) else {
                stop()
                status = "Personal audio output changed. Reconnect headphones before trying again."
                return
            }
        } catch {
            stop()
            status = "Personal audio output could not start."
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        currentUtterance = utterance
        status = "Playing Spanish pronunciation through your personal audio output."
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        if sessionActive {
            sessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        status = "Pronunciation stopped."
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let completedID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, let current = self.currentUtterance, ObjectIdentifier(current) == completedID else { return }
            self.stop()
            self.status = "Ready. Select a reply to hear its Spanish pronunciation."
        }
    }
}

/// Speaks one transcript line aloud for the listener, through the current route
/// (normally the phone speaker: the listener is not wearing headphones).
@MainActor
protocol TranslationSpeaking: AnyObject {
    var speakingID: String? { get }
    var status: String? { get }
    func speak(_ text: String, language: String, id: String)
    func stop()
}

/// Local voices only; no network or paid API. Stops on any route change,
/// interruption or media reset. The caller keeps it apart from capture.
@MainActor @Observable
final class TranslationSpeaker: NSObject, TranslationSpeaking, AVSpeechSynthesizerDelegate {
    private(set) var speakingID: String?
    private(set) var status: String?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private var sessionActive = false

    /// Regional defaults for the catalog's bare language codes.
    static let preferredLocales = [
        "ar": "ar-SA", "en": "en-US", "es": "es-ES", "fr": "fr-FR", "de": "de-DE", "he": "he-IL",
        "hi": "hi-IN", "id": "id-ID", "it": "it-IT", "ja": "ja-JP", "ko": "ko-KR", "ms": "ms-MY",
        "nl": "nl-NL", "pl": "pl-PL", "pt": "pt-BR", "th": "th-TH", "tr": "tr-TR", "vi": "vi-VN",
        "zh": "zh-CN"
    ]

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        for name in [AVAudioSession.routeChangeNotification, AVAudioSession.interruptionNotification,
                     AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
                // Our own category activation reports a category change; anything else stops playback.
                let categoryChange = notification.name == AVAudioSession.routeChangeNotification &&
                    (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.categoryChange.rawValue
                Task { @MainActor [weak self] in
                    guard let self, self.sessionActive, !categoryChange else { return }
                    self.stop()
                    self.status = "Audio changed. Tap Play again when ready."
                }
            })
        }
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        synthesizer.stopSpeaking(at: .immediate)
        if sessionActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        if let locale = preferredLocales[language], let voice = AVSpeechSynthesisVoice(language: locale) { return voice }
        return AVSpeechSynthesisVoice(language: language)
    }

    func speak(_ text: String, language: String, id: String) {
        stop()
        guard let voice = Self.voice(for: language) else {
            status = "No \(LanguageAvailability.name(language)) voice is installed on this phone."
            return
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
            sessionActive = true
        } catch {
            stop()
            status = "Audio output could not start."
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        currentUtterance = utterance
        speakingID = id
        status = nil
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil
        speakingID = nil
        synthesizer.stopSpeaking(at: .immediate)
        if sessionActive {
            sessionActive = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let completedID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, let current = self.currentUtterance, ObjectIdentifier(current) == completedID else { return }
            self.stop()
        }
    }
}

/// UI tests and screenshot runs: the same Play/Stop states, with no synthesizer and no sound.
@MainActor @Observable
final class SilentTranslationSpeaker: TranslationSpeaking {
    private(set) var speakingID: String?
    private(set) var status: String?
    @ObservationIgnored private var finish: Task<Void, Never>?
    private let duration: Duration

    init(duration: Duration = .seconds(8)) { self.duration = duration }

    func speak(_ text: String, language: String, id: String) {
        stop()
        speakingID = id
        finish = Task { [weak self, duration] in
            do { try await Task.sleep(for: duration) } catch { return }
            self?.speakingID = nil
        }
    }

    func stop() {
        finish?.cancel()
        finish = nil
        speakingID = nil
    }
}
