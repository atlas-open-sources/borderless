import Testing
import MetaConnectionPolicy

@Test func stoppingRequiresAcknowledgment() {
    var lease = ConnectionLease()
    let first = lease.enable()!
    #expect(lease.accepts(first))
    lease.disable(hasSession: true)
    #expect(!lease.accepts(first))
    let premature = lease.enable()
    #expect(premature == nil)
    // A second stop must not accidentally release the first one's ownership.
    lease.disable(hasSession: false)
    #expect(lease.awaitingStop)
    lease.sessionStopped()
    let next = lease.enable()!
    #expect(next != first)
    #expect(lease.accepts(next))
    #expect(!lease.accepts(first))
}

@Test func noImplicitActivationOrDuplicateOwner() {
    var lease = ConnectionLease()
    #expect(!lease.enabled)
    #expect(!lease.accepts(0))
    let token = lease.enable()!
    let duplicate = lease.enable()
    #expect(duplicate == nil)
    lease.disable(hasSession: false)
    #expect(!lease.accepts(token))
    #expect(!lease.awaitingStop)
    let restarted = lease.enable()
    #expect(restarted != nil)
}

@Test func duplicateSceneKeepsButtonsAndLateSendCannotReviveOldScene() {
    var lease = SceneActionLease<String>()
    lease.prepare("first")
    let first = lease.beginSend()
    lease.prepare("first")
    #expect(lease.accepts(first, scene: "first"))
    lease.prepare("second")
    #expect(!lease.accepts(first, scene: "first"))
    let lateOld = lease.beginSend()
    #expect(!lease.accepts(lateOld, scene: "first"))
    let second = lease.beginSend()
    #expect(lease.accepts(second, scene: "second"))
    lease.invalidate()
    #expect(!lease.accepts(second, scene: "second"))
}
