/// A callback belongs to the displayed scene only while it is still desired.
/// Duplicate publishes preserve buttons even when the scheduler deduplicates.
public struct SceneActionLease<Scene: Equatable & Sendable>: Sendable {
    private var desired: Scene?
    private var generation: UInt64 = 0
    public init() {}
    public mutating func prepare(_ scene: Scene) {
        if desired != scene { generation &+= 1; desired = scene }
    }
    public mutating func beginSend() -> UInt64 {
        generation &+= 1
        return generation
    }
    public mutating func invalidate() { generation &+= 1; desired = nil }
    public func accepts(_ token: UInt64, scene: Scene) -> Bool {
        generation == token && desired == scene
    }
}
