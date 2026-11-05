/// Semantic navigation independent of the experimental SDK product.
public enum MetaNavigation: Equatable, Sendable {
    case up, down, left, right, select, back
}

/// Reject stale, duplicate and non-band events across explicit opt-in sessions.
public struct NavigationLease: Sendable {
    public private(set) var generation: UInt64 = 0
    public private(set) var enabled = false
    private var lastTimestamp: Int64?
    public init() {}
    public mutating func begin() -> UInt64 {
        generation &+= 1; enabled = true; lastTimestamp = nil
        return generation
    }
    public mutating func end() {
        generation &+= 1; enabled = false; lastTimestamp = nil
    }
    public func accepts(_ generation: UInt64) -> Bool { enabled && self.generation == generation }
    public mutating func receive(_ action: MetaNavigation, neuralBand: Bool,
                                 timestamp: Int64, generation: UInt64) -> MetaNavigation? {
        guard accepts(generation), neuralBand, timestamp >= 0,
              lastTimestamp.map({ timestamp > $0 }) ?? true else { return nil }
        lastTimestamp = timestamp
        return action
    }
}
