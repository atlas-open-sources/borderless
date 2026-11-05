#if os(iOS)
import Foundation
import Observation
import MetaConnectionPolicy
import MetaDisplayKit
import MWDATCore
import MWDATDisplay
#if BORDERLESS_EXPERIMENTAL_INPUTS
import MWDATInputs
#endif

public typealias MetaNavigation = MetaConnectionPolicy.MetaNavigation

/// One explicit owner of one display-capable DAT session. Initializing does
/// not configure DAT, register, connect, activate Bluetooth or request input.
@MainActor @Observable
public final class MetaConnection {
    public enum Status: Equatable, Sendable {
        case off, registrationRequired, waitingForDevice, connecting, connected, stopping
        case failed(String)
    }
    public private(set) var status: Status = .off
    public enum NavigationStatus: Equatable, Sendable {
        case unavailable, off, activating, active, failed(String)
    }
    public var onNavigation: (@MainActor (MetaNavigation) -> Void)?
    #if BORDERLESS_EXPERIMENTAL_INPUTS
    public private(set) var navigationStatus: NavigationStatus = .off
    @ObservationIgnored private var inputs: Inputs?
    @ObservationIgnored private var inputTask: Task<Void, Never>?
    @ObservationIgnored private var inputDeadline: Task<Void, Never>?
    @ObservationIgnored private var inputStateToken: (any AnyListenerToken)?
    @ObservationIgnored private var inputErrorToken: (any AnyListenerToken)?
    @ObservationIgnored private var navigationLease = NavigationLease()
    #else
    public private(set) var navigationStatus: NavigationStatus = .unavailable
    #endif
    public var onAction: (@MainActor (String) -> Void)?
    public let driver = MetaDisplayDriver()
    public var enabled: Bool { lease.enabled }

    @ObservationIgnored private var lease = ConnectionLease()
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var session: DeviceSession?
    @ObservationIgnored private var display: Display?
    @ObservationIgnored private var displayToken: (any AnyListenerToken)?
    @ObservationIgnored private var selector: AutoDeviceSelector?
    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var deviceTask: Task<Void, Never>?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var errorTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?
    @ObservationIgnored private var registrationRequest: Task<Void, Never>?
    @ObservationIgnored private var latestScene: MetaScene?
    @ObservationIgnored private var sink: DATSceneSink?
    private let connectionTimeout: Duration = .seconds(20)

    public init() {}

    deinit {
        #if BORDERLESS_EXPERIMENTAL_INPUTS
        inputTask?.cancel(); inputDeadline?.cancel()
        if let token = inputStateToken { Task { await token.cancel() } }
        if let token = inputErrorToken { Task { await token.cancel() } }
        #endif
        registrationTask?.cancel(); registrationRequest?.cancel()
        deviceTask?.cancel(); stateTask?.cancel(); errorTask?.cancel(); deadlineTask?.cancel()
        display?.stop(); session?.stop()
        if let token = displayToken { Task { await token.cancel() } }
    }

    /// Explicit Connect. Unregistered apps report registrationRequired; they
    /// do not hand off to Meta AI until register() is separately requested.
    public func enable() {
        guard let generation = lease.enable() else { return }
        do {
            if !configured { try Wearables.configure(); configured = true }
        } catch {
            switch error {
            case .alreadyConfigured:
                configured = true
            case .missingAppVersion:
                fail("This build is missing its app version. Install the updated Borderless build.")
            case .missingBuildNumber:
                fail("This build is missing its build number. Install the updated Borderless build.")
            case .missingAppName:
                fail("This build is missing its app name. Install the updated Borderless build.")
            case .missingBundleIdentifier, .missingInfoDictionary:
                fail("This build is missing its app identity. Install the updated Borderless build.")
            case .configurationError:
                fail("Meta setup could not be loaded. Check this build’s callback and Developer Mode configuration.")
            default:
                fail("Meta could not start. Disconnect, then try connecting again.")
            }
            if !configured { return }
        }
        let wearables = Wearables.shared
        let stream = wearables.registrationStateStream()
        registrationTask = Task { [weak self] in
            for await state in stream {
                guard let self, !Task.isCancelled, self.lease.accepts(generation) else { return }
                self.registration(state, generation: generation)
            }
        }
        registration(wearables.registrationState, generation: generation)
    }

    /// Explicit user-requested SDK registration, not called by init or submit.
    public func register() {
        if !enabled { enable() }
        guard enabled, configured, registrationRequest == nil else { return }
        let generation = lease.generation
        registrationRequest = Task { [weak self] in
            do { try await Wearables.shared.startRegistration() }
            catch {
                guard let self, self.lease.accepts(generation) else { return }
                self.fail("Meta registration did not finish.")
            }
            if let self, self.lease.accepts(generation) { self.registrationRequest = nil }
        }
    }

    public func handle(url: URL) async -> Bool {
        guard configured, enabled else { return false }
        let generation = lease.generation
        do {
            let handled = try await Wearables.shared.handleUrl(url)
            guard lease.accepts(generation) else { return false }
            return handled
        } catch {
            if lease.accepts(generation) { fail("Meta callback could not be handled.") }
            return false
        }
    }

    /// Stops display before session. A missing stop acknowledgment prevents
    /// overlapping reconnects; there is deliberately no automatic retry loop.
    public func disable() {
        setNavigationEnabled(false)
        let hadSession = session != nil
        lease.disable(hasSession: hadSession)
        sink?.invalidateActions()
        latestScene = nil
        driver.attach(nil)
        sink = nil
        registrationTask?.cancel(); registrationTask = nil
        registrationRequest?.cancel(); registrationRequest = nil
        deviceTask?.cancel(); deviceTask = nil
        deadlineTask?.cancel(); deadlineTask = nil
        errorTask?.cancel(); errorTask = nil
        if let token = displayToken { Task { await token.cancel() } }
        displayToken = nil
        display?.stop(); display = nil
        selector = nil
        if let session {
            status = .stopping
            session.stop()
            // Keep stateTask until .stopped; another session cannot start yet.
        } else {
            stateTask?.cancel(); stateTask = nil
            status = .off
        }
    }

    /// Separate opt-in. Stable builds report unavailable without loading Inputs.
    /// Enabling never creates a session or registers the app.
    public func setNavigationEnabled(_ enabled: Bool) {
        #if BORDERLESS_EXPERIMENTAL_INPUTS
        if !enabled {
            navigationLease.end()
            inputTask?.cancel(); inputTask = nil
            inputDeadline?.cancel(); inputDeadline = nil
            if let token = inputStateToken { Task { await token.cancel() } }
            if let token = inputErrorToken { Task { await token.cancel() } }
            inputStateToken = nil; inputErrorToken = nil
            if inputs != nil {
                do { try session?.removeInputs() }
                catch {
                    // Keep the capability sentinel until its session stops.
                    navigationStatus = .failed("Band input cleanup failed. Disconnect the Meta session before retrying.")
                    return
                }
            }
            inputs = nil
            navigationStatus = .off
            return
        }
        guard inputs == nil else { return }
        guard status == .connected, let session else {
            navigationStatus = .failed("Connect the Meta display before enabling band navigation.")
            return
        }
        let generation = navigationLease.begin()
        let connectionGeneration = lease.generation
        navigationStatus = .activating
        do {
            guard let inputs = try session.addInputs(configuration: InputsConfiguration(sources: [.neuralBand], consumeBack: true)) else {
                navigationFailed("Neural band input capability is unavailable.")
                return
            }
            self.inputs = inputs
            inputStateToken = inputs.statePublisher.listen { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.inputs === inputs, self.navigationLease.accepts(generation),
                          self.lease.accepts(connectionGeneration) else { return }
                    if state == .active {
                        self.navigationStatus = .active
                        self.inputDeadline?.cancel(); self.inputDeadline = nil
                    } else if state == .deactivating || (state == .inactive && self.navigationStatus == .active) {
                        self.navigationFailed("Band navigation ended. Enable it again to retry.")
                    }
                }
            }
            inputErrorToken = inputs.errorPublisher.listen { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.inputs === inputs, self.navigationLease.accepts(generation),
                          self.lease.accepts(connectionGeneration) else { return }
                    self.navigationFailed("Band navigation failed. Check permission and connection.")
                }
            }
            if inputs.state == .active { navigationStatus = .active }
            inputTask = Task { [weak self] in
                for await event in inputs.events {
                    guard let self, !Task.isCancelled, self.inputs === inputs,
                          self.lease.accepts(connectionGeneration), self.navigationLease.accepts(generation) else { return }
                    guard self.navigationStatus == .active, let mapped = Self.navigation(event),
                          let action = self.navigationLease.receive(mapped, neuralBand: event.source == .neuralBand,
                              timestamp: event.timestampMs, generation: generation) else { continue }
                    self.onNavigation?(action)
                }
                if let self, !Task.isCancelled, self.navigationLease.accepts(generation) {
                    self.navigationFailed("Band navigation stream ended.")
                }
            }
            if navigationStatus != .active {
                inputDeadline = Task { [weak self, connectionTimeout] in
                    do { try await Task.sleep(for: connectionTimeout) } catch { return }
                    guard let self, self.navigationLease.accepts(generation) else { return }
                    self.navigationFailed("Band navigation did not activate within 20 seconds.")
                }
            }
        } catch { navigationFailed("Band navigation capability could not be opened.") }
        #else
        navigationStatus = .unavailable
        #endif
    }

    #if BORDERLESS_EXPERIMENTAL_INPUTS
    private func navigationFailed(_ message: String) {
        setNavigationEnabled(false)
        if inputs == nil { navigationStatus = .failed(message) }
    }

    private static func navigation(_ event: InputEvent) -> MetaNavigation? {
        switch event {
        case .nav(let direction, _, _):
            switch direction {
            case .up: .up
            case .down: .down
            case .left: .left
            case .right: .right
            }
        case .select: .select
        case .back: .back
        default: nil
        }
    }
    #endif

    /// Scene publication alone never enables the device.
    public func submit(_ scene: MetaScene) {
        latestScene = scene
        sink?.prepare(scene)
        driver.submit(scene)
    }

    private func registration(_ state: RegistrationState, generation: UInt64) {
        guard lease.accepts(generation) else { return }
        guard state == .registered else {
            if session != nil { fail("Meta registration is no longer active.") }
            else { status = .registrationRequired }
            return
        }
        guard session == nil, deviceTask == nil else { return }
        let selector = AutoDeviceSelector(wearables: Wearables.shared, filter: { $0.supportsDisplay() })
        self.selector = selector
        status = .waitingForDevice
        let stream = selector.activeDeviceStream()
        deviceTask = Task { [weak self] in
            for await device in stream {
                guard let self, !Task.isCancelled, self.lease.accepts(generation) else { return }
                guard device != nil else { continue }
                self.connect(selector, generation: generation)
                return
            }
        }
        deadlineTask = Task { [weak self, connectionTimeout] in
            do { try await Task.sleep(for: connectionTimeout) } catch { return }
            guard let self, self.lease.accepts(generation), self.status != .connected else { return }
            self.fail("No ready Meta display within 20 seconds. Connect again to retry.")
        }
    }

    private func connect(_ selector: AutoDeviceSelector, generation: UInt64) {
        guard lease.accepts(generation), session == nil else { return }
        do {
            let session = try Wearables.shared.createSession(deviceSelector: selector)
            self.session = session
            status = .connecting
            let states = session.stateStream()
            let errors = session.errorStream()
            stateTask = Task { [weak self] in
                for await state in states {
                    guard let self, !Task.isCancelled, self.session === session else { return }
                    if state == .stopped {
                        #if BORDERLESS_EXPERIMENTAL_INPUTS
                        self.inputs = nil
                        #endif
                        self.session = nil
                        self.lease.sessionStopped()
                        if self.enabled { self.fail("Meta session ended. Connect again to retry.") }
                        else if self.status == .stopping { self.status = .off }
                        return
                    }
                    guard self.lease.accepts(generation) else { continue }
                    if state == .started { self.attachDisplay(session, generation: generation) }
                    else if state == .stopping { self.disable() }
                }
            }
            errorTask = Task { [weak self] in
                for await _ in errors {
                    guard let self, !Task.isCancelled, self.session === session,
                          self.lease.accepts(generation) else { return }
                    self.fail("Meta device session failed. Check the Meta AI app and reconnect.")
                    return
                }
            }
            try session.start()
        } catch {
            fail("A Meta display session could not be started.")
        }
    }

    private func attachDisplay(_ session: DeviceSession, generation: UInt64) {
        guard display == nil, lease.accepts(generation) else { return }
        do {
            let display = try session.addDisplay()
            self.display = display
            displayToken = display.statePublisher.listen { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.display === display, self.lease.accepts(generation) else { return }
                    if state == .started {
                        self.deadlineTask?.cancel(); self.deadlineTask = nil
                        let sink = DATSceneSink(display: display) { [weak self] action in
                            guard let self, self.display === display,
                                  self.lease.accepts(generation) else { return }
                            self.onAction?(action)
                        }
                        self.sink = sink
                        self.driver.attach(sink)
                        self.status = .connected
                        if let scene = self.latestScene { sink.prepare(scene); self.driver.submit(scene) }
                    } else if state == .stopped || state == .stopping {
                        self.fail("Meta display stopped. Connect again to retry.")
                    }
                }
            }
            display.start()
        } catch { fail("Meta display capability could not be opened.") }
    }

    private func fail(_ message: String) {
        disable()
        status = .failed(message)
    }
}
#endif
