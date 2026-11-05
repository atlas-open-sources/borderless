import XCTest
import BorderlessCore
import BorderlessDisplay
import GlassesSceneKit
import GlassesTextKit
import MetaDisplayKit

final class ConversationViewportTests: XCTestCase {
    private func conversation(_ source: String, translation: String, replies: [Reply] = []) -> Conversation {
        var session = Conversation()
        session.start(hostConsent: true, guestConsent: true)
        session.receive(Turn(id: "long", speaker: .lin, source: source, translation: translation, replies: replies),
                        epoch: session.epoch, final: true)
        return session
    }

    func testLongMultilingualTextIsPreservedAcrossFittedPages() {
        let source = String(repeating: "你好世界España", count: 90)
        let translation = String(repeating: "Translationwithoutspaces", count: 70)
        let session = conversation(source, translation: translation)
        for wearer in [Participant.alex, .lin] {
            let pages = ConversationViewport.pages(session, wearer: wearer)
            XCTAssertGreaterThan(pages.count, 1)
            let body = pages.flatMap { $0.lines.dropFirst() }
            let sourceText = body.filter { $0.role == .secondary }.map(\.text).joined()
            XCTAssertEqual(sourceText, source)
            XCTAssertEqual(body.filter { $0.role == .body }.map(\.text).joined(), translation)
            for page in pages {
                if wearer == .alex {
                    let layout = MetaRender.layout(for: page)
                    XCTAssertEqual(layout.clippedAtTop, 0)
                    XCTAssertTrue(layout.items.allSatisfy { MetaPanelLayout.column.contains($0.frame) })
                    XCTAssertTrue(layout.textBlocks.allSatisfy { !$0.overflowsWidth })
                    XCTAssertEqual(MetaRender.scene(for: page).lines.count, page.lines.count)
                } else {
                    XCTAssertEqual(G2Render.rows(for: page), page.lines.map(\.text))
                    XCTAssertLessThanOrEqual(page.lines.count, G2Render.visibleRows)
                    XCTAssertTrue(page.lines.allSatisfy { G2FontMetrics.pixelWidth(of: $0.text) <= G2FontMetrics.usablePixelWidth })
                }
            }
        }
    }

    func testQuestionAndBothBilingualRepliesStayVisibleTogether() {
        let reply1 = Reply(text: "Bien, gracias. Sí, es mi primera vez.", gloss: "Well, thanks. Yes, it's my first time.", pronunciation: "DO NOT SHOW")
        let reply2 = Reply(text: "Bien, gracias. No, ya he venido.", gloss: "Well, thanks. No, I've been before.")
        var session = conversation("Hola, ¿cómo estás? ¿Es tu primera vez en Madrid?",
                                   translation: "Hi, how are you? Is this your first time in Madrid?", replies: [reply1, reply2])
        let page = ConversationViewport.pages(session, wearer: .alex).last!
        for text in [session.turns[0].source, session.turns[0].translation, reply1.text, reply1.gloss, reply2.text, reply2.gloss] {
            XCTAssertTrue((page.lines.map(\.text) + page.cards.flatMap { [$0.title, $0.detail] }).contains { $0.contains(text) }, text)
        }
        XCTAssertFalse(page.lines.contains { $0.text.contains("DO NOT SHOW") })
        XCTAssertTrue(page.actions.isEmpty)
        XCTAssertEqual(page.cards.count, 2)
        XCTAssertTrue(page.cards[0].focused)
        let layout = MetaRender.layout(for: page)
        XCTAssertTrue(layout.items.allSatisfy { MetaPanelLayout.column.contains($0.frame) })
        XCTAssertTrue(layout.textBlocks.allSatisfy { !$0.overflowsWidth })
        let before = page.lines
        session.navigate(1, token: session.replyToken!)
        XCTAssertEqual(ConversationViewport.pages(session, wearer: .alex).last!.lines, before)
        let focusedPage = ConversationViewport.pages(session, wearer: .alex).last!
        XCTAssertFalse(focusedPage.cards[0].focused)
        XCTAssertTrue(focusedPage.cards[1].focused)
        XCTAssertEqual(focusedPage.cards.map(\.title), page.cards.map(\.title))
        let guest = ConversationViewport.pages(session, wearer: .lin)
        let guestText = guest.flatMap { $0.lines.dropFirst() }.map(\.text).joined()
        XCTAssertTrue(guestText.contains(session.turns[0].source))
        XCTAssertTrue(guestText.contains(session.turns[0].translation))
        XCTAssertTrue(guest.allSatisfy { $0.actions.isEmpty && $0.cards.isEmpty })
        XCTAssertFalse(guestText.contains(reply1.text))
    }

    func testLongRepliesPreserveTextAndLandOnQuestion() {
        let reply = Reply(text: String(repeating: "respuesta", count: 80),
                          gloss: String(repeating: "meaning", count: 80), pronunciation: "DO NOT SHOW")
        let session = conversation("Hola", translation: "Hello", replies: [reply, Reply(text: "No", gloss: "No")])
        let pages = ConversationViewport.pages(session, wearer: .alex)
        let text = pages.reversed().flatMap { $0.lines.dropFirst() }.map(\.text).joined()
        XCTAssertEqual(text, "HolaHello1. " + reply.text + reply.gloss + "2. NoNo")
        XCTAssertEqual(pages.last?.lines[1].text, "Hola")
        for page in pages {
            let layout = MetaRender.layout(for: page)
            XCTAssertEqual(layout.clippedAtTop, 0)
            XCTAssertTrue(layout.items.allSatisfy { MetaPanelLayout.column.contains($0.frame) })
            XCTAssertTrue(layout.textBlocks.allSatisfy { !$0.overflowsWidth })
            XCTAssertEqual(page.actions.count, 2)
        }
    }

    func testBlankPendingCaptureShowsListeningWithoutOldActions() {
        var session = conversation("Hola", translation: "Hello", replies: [Reply(text: "Bien", gloss: "Well")])
        session.receive(Turn(id: "pending", speaker: .alex, source: "", translation: ""),
                        epoch: session.epoch, final: false)
        for wearer in [Participant.alex, .lin] {
            let pages = ConversationViewport.pages(session, wearer: wearer)
            XCTAssertEqual(pages.last?.lines.last?.text, "Listening…")
            XCTAssertTrue(pages.allSatisfy { $0.actions.isEmpty })
        }
    }

    func testBoundedHistoryMeasurement() {
        var session = Conversation()
        session.start(hostConsent: true, guestConsent: true)
        for index in 0..<256 {
            session.receive(Turn(id: "t-\(index)", speaker: index.isMultiple(of: 2) ? .alex : .lin,
                                 source: "How are you today? I am visiting Madrid.",
                                 translation: "¿Cómo estás hoy? Estoy visitando Madrid."), epoch: session.epoch, final: true)
        }
        let start = Date()
        let host = ConversationViewport.pages(session, wearer: .alex)
        let guest = ConversationViewport.pages(session, wearer: .lin)
        print("Viewport benchmark256 short turns both devices: \(Date().timeIntervalSince(start)) seconds; \(host.count + guest.count) pages")
        XCTAssertEqual(host.count, 256)
        XCTAssertEqual(guest.count, 256)
        let long = conversation(String(repeating: "汉", count: 2000), translation: String(repeating: "W", count: 2000))
        let longStart = Date()
        let longHost = ConversationViewport.pages(long, wearer: .alex)
        let longGuest = ConversationViewport.pages(long, wearer: .lin)
        print("Viewport benchmark2000char source+translation both devices: \(Date().timeIntervalSince(longStart)) seconds; \(longHost.count + longGuest.count) pages")
        XCTAssertFalse(longHost.isEmpty)
    }

    /// Single-glasses mode: the one wearer is the host on either display.
    func testSingleWearerOnG2SeesTheirLanguageAndRepliesWithinG2Rows() {
        let session = conversation("¿Es tu primera vez en Madrid?", translation: "Is this your first time in Madrid?",
                                   replies: [Reply(text: "Sí, me encanta", gloss: "Yes, I love it"),
                                             Reply(text: "No, ya vine", gloss: "No, I came before")])
        let pages = ConversationViewport.pages(session, wearer: .alex, display: .g2, guestName: "Them")
        let text = pages.flatMap(\.lines).map(\.text).joined(separator: "\n")
        XCTAssertTrue(text.contains("Is this your first time in Madrid?"))
        XCTAssertTrue(text.contains("Them · "))
        XCTAssertTrue(text.contains("Sí, me encanta"), "The single wearer is the host and keeps reply ideas")
        XCTAssertTrue(pages.allSatisfy { $0.cards.isEmpty && $0.actions.isEmpty }, "G2 has no input route")
        for page in pages {
            XCTAssertLessThanOrEqual(page.lines.count, G2Render.visibleRows)
            XCTAssertTrue(page.lines.allSatisfy { G2FontMetrics.pixelWidth(of: $0.text) <= G2FontMetrics.usablePixelWidth })
        }
        XCTAssertTrue(pages.last?.lines.contains { $0.text.contains("Is this your first time") } == true,
                      "The default page lands on the question")
        let meta = ConversationViewport.pages(session, wearer: .alex)
        XCTAssertEqual(meta.last?.cards.count, 2, "Default host fit is unchanged: Meta cards")
        let guest = ConversationViewport.pages(session, wearer: .lin).flatMap(\.lines).map(\.text).joined()
        XCTAssertFalse(guest.contains("Sí, me encanta"))
    }
}
