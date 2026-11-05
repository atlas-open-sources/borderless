import Testing
@testable import MetaConnectionPolicy

@Test func navigationRequiresCurrentExplicitOptInAndBandSource() {
    var policy = NavigationLease()
    #expect(policy.receive(.select, neuralBand: true, timestamp: 1, generation: 0) == nil)
    let first = policy.begin()
    #expect(policy.receive(.up, neuralBand: false, timestamp: 1, generation: first) == nil)
    #expect(policy.receive(.up, neuralBand: true, timestamp: 1, generation: first) == .up)
    #expect(policy.receive(.down, neuralBand: true, timestamp: 1, generation: first) == nil)
    policy.end()
    #expect(policy.receive(.back, neuralBand: true, timestamp: 2, generation: first) == nil)
    let second = policy.begin()
    #expect(policy.receive(.back, neuralBand: true, timestamp: 3, generation: first) == nil)
    for (index, action) in [MetaNavigation.up, .down, .left, .right, .select, .back].enumerated() {
        #expect(policy.receive(action, neuralBand: true, timestamp: Int64(index), generation: second) == action)
    }
}
