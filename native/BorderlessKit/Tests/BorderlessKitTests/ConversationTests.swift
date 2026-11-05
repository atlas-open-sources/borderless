import Foundation
import Testing
import BorderlessCore
import BorderlessDisplay
import GlassesSceneKit

private func fixture() throws -> [Turn] {
    struct Fixture: Decodable { let turns: [Turn] }
    let url = try #require(Bundle.module.url(forResource: "spanish", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).turns
}
private func ready() -> Conversation {
    var session = Conversation()
    session.start(hostConsent: true, guestConsent: true)
    return session
}
@Test func consentAndEpoch() throws {
    var session = Conversation()
    let result18 = !session.start(hostConsent: true, guestConsent: false)
    #expect(result18)
    session.start(hostConsent: true, guestConsent: true)
    let epoch = session.epoch
    let result21 = session.receive(try fixture()[0], epoch: epoch, final: true)
    #expect(result21)
    session.withdrawConsent()
    #expect(session.turns.isEmpty)
    let result24 = !session.receive(try fixture()[0], epoch: epoch, final: true)
    #expect(result24)
    #expect(ConversationScene.make(session, for: .alex).isEmpty)
}
@Test func goldenDialogueBothManufacturers() throws {
    var session = ready()
    for turn in try fixture() {
        let result30 = session.receive(turn, epoch: session.epoch, final: true)
        #expect(result30)
        let host = ConversationScene.make(session, for: .alex)
        let guest = ConversationScene.make(session, for: .lin)
        #expect(guest.actions.isEmpty)
        #expect(host.cards.count == (turn.speaker == .lin ? 2 : 0))
        #expect(host.lines.contains { $0.text == (turn.speaker == .alex ? turn.source : turn.translation) })
        #expect(guest.lines.contains { $0.text == (turn.speaker == .lin ? turn.source : turn.translation) })
        #expect(!G2Render.rows(for: guest).isEmpty)
        #expect(G2Render.rows(for: guest).count <= G2Render.visibleRows)
        #expect(MetaRender.scene(for: host).cards.count == host.cards.count)
        #expect(ConversationScene.make(session, for: .lin, connected: false).isEmpty)
    }
    #expect(session.turns.count == 5)
}
@Test func privateSelectionAndInvalidation() throws {
    let turns = try fixture()
    var session = ready()
    session.receive(turns[0], epoch: session.epoch, final: true)
    let token = try #require(session.replyToken)
    session.navigate(1, token: token)
    session.navigate(1, token: token)
    #expect(session.focused == 1)
    let result52 = session.confirm(token: token)
    #expect(result52)
    #expect(session.turns.count == 1)
    #expect(session.replies(for: .lin).isEmpty)
    let dismissed = session.dismissSelection(token: token)
    #expect(dismissed && session.selected == nil && session.focused == 1)
    session.receive(turns[1], epoch: session.epoch, final: false)
    let staleDismissed = session.dismissSelection(token: token)
    #expect(!staleDismissed)
    let result56 = !session.confirm(token: token)
    #expect(result56)
    #expect(session.selected == nil)
    #expect(ConversationScene.make(session, for: .alex).actions.isEmpty)
}
@Test func correctionDropsDependentContext() throws {
    let turns = try fixture()
    var session = ready()
    for turn in turns { session.receive(turn, epoch: session.epoch, final: true) }
    let result64 = !session.receive(turns[0], epoch: session.epoch, final: true)
    #expect(result64)
    var corrected = turns[0]; corrected.revision = 2
    let result66 = session.receive(corrected, epoch: session.epoch, final: true)
    #expect(result66)
    #expect(session.turns.count == 1)
    #expect(session.turns[0].version == 2)
}
@Test func historyHasNoStaleActions() throws {
    let turns = try fixture()
    var session = ready()
    for turn in turns { session.receive(turn, epoch: session.epoch, final: true) }
    let scene = ConversationScene.make(session, for: .alex, through: turns[0].id)
    #expect(scene.actions.isEmpty)
    #expect(scene.lines.contains { $0.text == turns[0].translation })
    #expect(!scene.lines.contains { $0.text == turns[4].translation })
    #expect(ConversationScene.make(session, for: .alex, through: "unknown").isEmpty)
}
@Test func timedFollowAndIndependentViews() {
    var host = HistoryFollow(), guest = HistoryFollow()
    host.scroll(atBottom: false, now: 0)
    let result83 = !host.tick(now: 19.9)
    #expect(result83)
    host.activity(now: 19)
    let result85 = !host.tick(now: 20)
    #expect(result85)
    let result86 = host.tick(now: 39)
    #expect(result86)
    host.scroll(atBottom: false, now: 40)
    guest.scroll(atBottom: true, now: 40)
    #expect(!host.following && guest.following)
    host.scroll(atBottom: true, now: 41)
    #expect(host.following && host.resumeAt == nil)
}
@Test func boundedHistoryAndGuestPrivacy() {
    var session = ready()
    let invalid = Turn(id: "invalid", speaker: .alex, source: "hello", translation: "hola",
                       replies: [Reply(text: "leak", gloss: "leak")])
    let accepted = session.receive(invalid, epoch: session.epoch, final: true)
    #expect(!accepted)
    for index in 0..<300 {
        let turn = Turn(id: "turn-\(index)", speaker: .alex, source: "hello", translation: "hola")
        session.receive(turn, epoch: session.epoch, final: true)
    }
    #expect(session.turns.count == Conversation.maximumTurns)
    #expect(session.turns.first?.id == "turn-44")
    #expect(session.turns.last?.id == "turn-299")
}

@Test func identicalNewTurnRejectsOldDisplayAction() throws {
    var session = ready()
    let replies = [Reply(text: "Bien", gloss: "Well")]
    session.receive(Turn(id: "one", speaker: .lin, source: "Hola", translation: "Hello", replies: replies),
                    epoch: session.epoch, final: true)
    let old = try #require(session.replyActionID(at: 0))
    #expect(session.replyIndex(for: old) == 0)
    session.receive(Turn(id: "two", speaker: .lin, source: "Hola", translation: "Hello", replies: replies),
                    epoch: session.epoch, final: true)
    #expect(session.replyIndex(for: old) == nil)
    #expect(session.replyActionID(at: 0) != old)
}

@Test func pendingRevisionsNeverMoveBackward() {
    var session = ready()
    let newer = Turn(id: "speech", speaker: .lin, source: "Hola amiga", translation: "Hello friend", revision: 2)
    let older = Turn(id: "speech", speaker: .lin, source: "Hola", translation: "Hello", revision: 1)
    session.receive(newer, epoch: session.epoch, final: false)
    let generation = session.actionRevision
    let stalePartial = session.receive(older, epoch: session.epoch, final: false)
    let duplicatePartial = session.receive(newer, epoch: session.epoch, final: false)
    let staleFinal = session.receive(older, epoch: session.epoch, final: true)
    #expect(!stalePartial && !duplicatePartial && !staleFinal)
    #expect(session.pending?.source == newer.source)
    #expect(session.turns.isEmpty)
    #expect(session.actionRevision == generation)
    let completed = session.receive(newer, epoch: session.epoch, final: true)
    #expect(completed)
    #expect(session.pending == nil)
    #expect(session.turns.last?.version == 2)
}

@Test func olderTranslationKeepsNewerProvisionalSpeech() {
    var session = ready()
    let pending = Turn(id: "new", speaker: .lin, source: "Nueva frase", translation: "", revision: 2)
    session.receive(pending, epoch: session.epoch, final: false)
    session.receive(Turn(id: "old", speaker: .lin, source: "Hola", translation: "Hello",
                         replies: [Reply(text: "Bien", gloss: "Well")]), epoch: session.epoch, final: true)
    #expect(session.pending?.id == "new")
    #expect(session.replyToken == nil)
    let accepted = session.receive(Turn(id: "new", speaker: .lin, source: "Nueva frase",
                                       translation: "New phrase", revision: 2), epoch: session.epoch, final: true)
    #expect(accepted && session.pending == nil && session.turns.count == 2)
}

@Test func silenceClearsPlaceholderButNeverDropsUnfinalizedSpeech() {
    var session = ready()
    session.receive(Turn(id: "capture", speaker: .lin, source: "", translation: ""),
                    epoch: session.epoch, final: false)
    let silent = session.completeInput(epoch: session.epoch)
    #expect(silent && session.pending == nil && session.turns.isEmpty)
    session.receive(Turn(id: "speech", speaker: .lin, source: "Hola", translation: ""),
                    epoch: session.epoch, final: false)
    let unfinished = session.completeInput(epoch: session.epoch)
    #expect(!unfinished && session.pending?.source == "Hola")
}
