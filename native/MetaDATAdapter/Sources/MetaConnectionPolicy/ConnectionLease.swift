/// A stopped SDK session must acknowledge termination before another may own
/// the connection. Generation tokens make queued callbacks and actions inert.
public struct ConnectionLease: Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var enabled = false
    public private(set) var awaitingStop = false
    public init() {}
    public mutating func enable() -> UInt64? {
        guard !enabled, !awaitingStop else { return nil }
        generation &+= 1
        enabled = true
        return generation
    }
    public func accepts(_ token: UInt64) -> Bool { enabled && generation == token }
    public mutating func disable(hasSession: Bool) {
        generation &+= 1
        enabled = false
        awaitingStop = awaitingStop || hasSession
    }
    public mutating func sessionStopped() { awaitingStop = false }
}
