import Foundation
import Testing
import BorderlessCore
import BorderlessG2

@Test @MainActor func guestProjectionNeverContainsPrivateReplies() {
    var conversation = Conversation()
    conversation.start(hostConsent: true, guestConsent: true)
    conversation.receive(Turn(id: "guest", speaker: .lin, source: "Hola", translation: "Hello",
        replies: [Reply(text: "PRIVATE", gloss: "SECRET")]), epoch: conversation.epoch, final: true)
    let text = G2Companion.guestText(conversation)
    #expect(text.contains("Hola"))
    #expect(!text.contains("PRIVATE"))
    #expect(!text.contains("SECRET"))
    conversation.stop()
    #expect(G2Companion.guestText(conversation).isEmpty)
}

@Test @MainActor func loopbackRoutesDeliverOnlyGuestFrame() async throws {
    let publisher = G2Companion()
    try publisher.start()
    defer { publisher.stop() }
    var conversation = Conversation()
    conversation.start(hostConsent: true, guestConsent: true)
    conversation.receive(Turn(id: "one", speaker: .alex, source: "Hello", translation: "Hola"),
                         epoch: conversation.epoch, final: true)
    publisher.publish(conversation)
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 3
    let client = URLSession(configuration: config)
    defer { client.invalidateAndCancel() }
    let (frame, response) = try await client.data(from: URL(string: "http://127.0.0.1:8767/glasses/frame")!)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(String(decoding: frame, as: UTF8.self).contains("Hola"))
    let (again, _) = try await client.data(from: URL(string: "http://127.0.0.1:8767/glasses/frame")!)
    let firstObject = try JSONSerialization.jsonObject(with: frame) as? NSDictionary
    let secondObject = try JSONSerialization.jsonObject(with: again) as? NSDictionary
    #expect(firstObject == secondObject)
    var audioRequest = URLRequest(url: URL(string: "http://127.0.0.1:8767/glasses/audio")!)
    audioRequest.httpMethod = "POST"
    let (_, rejected) = try await client.data(for: audioRequest)
    #expect((rejected as? HTTPURLResponse)?.statusCode == 404)
}

@Test func singleWearerProjectionIsTheHostViewFittedToG2() {
    var conversation = Conversation()
    conversation.start(hostConsent: true, guestConsent: true)
    conversation.receive(Turn(id: "guest", speaker: .lin, source: "Hola", translation: "Hello",
        replies: [Reply(text: "Bien", gloss: "Well")]), epoch: conversation.epoch, final: true)
    let wearer = WearerProjection(conversation, guestName: "Them").pages.flatMap(\.lines).map(\.text)
    #expect(wearer.contains("Hello"))
    #expect(wearer.contains { $0.contains("Bien") })
    #expect(wearer.contains { $0.hasPrefix("Them · ") })
    let guest = GuestProjection(conversation).pages.flatMap(\.lines).map(\.text)
    #expect(!guest.contains { $0.contains("Bien") })
    conversation.stop()
    #expect(WearerProjection(conversation).pages.isEmpty)
}
