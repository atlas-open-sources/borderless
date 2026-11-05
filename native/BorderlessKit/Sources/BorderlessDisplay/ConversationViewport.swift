import Foundation
import CoreText
import BorderlessCore
import GlassesSceneKit
import GlassesTextKit
import MetaDisplayKit

/// Which manufacturer's physical row budget a page set is fitted to.
public enum GlassesDisplay: String, Sendable, CaseIterable { case meta, g2 }

/// Full-history pages fitted through the shared manufacturer layout models.
/// Meta measurements remain a simulator model, not optical hardware proof.
/// Firmware-unsupported G2 glyphs are preserved in text but cannot be made
/// visible by pagination. Callers cache pages by session revision and default
/// to the last page; browsing history must not invent reply action IDs.
public enum ConversationViewport {
    /// `display` picks the physical text budget. It defaults to the two-glasses
    /// pairing (host on Meta, guest on G2); single-glasses mode can fit the
    /// host's own view to G2.
    public static func pages(_ session: Conversation, wearer: Participant,
                             display: GlassesDisplay? = nil, guestName: String = "Sofía") -> [GlassesScene] {
        guard session.active else { return [] }
        let display = display ?? (wearer == .lin ? .g2 : .meta)
        var result: [GlassesScene] = []
        let replies = session.replies(for: wearer)
        let preferred = session.selected ?? session.focused
        let actions = replies.indices.compactMap { index -> GlassesScene.Action? in
            guard let id = session.replyActionID(at: index) else { return nil }
            return .init(id: id, label: "Reply \(index + 1)", primary: preferred == index)
        }
        for turn in session.turns.suffix(Conversation.maximumTurns) {
            let speaker = speakerName(of: turn.speaker, wearer: wearer, guestName: guestName)
            let direction = turn.direction
            let name = "\(speaker) · \(direction)"
            var content: [GlassesScene.Line] = [
                .init(turn.source, role: .secondary), .init(turn.translation)
            ]
            let currentReplies = turn.id == session.turns.last?.id ? replies : []
            for (index, reply) in currentReplies.enumerated() {
                content.append(.init("\(index + 1). \(reply.text)"))
                content.append(.init(reply.gloss, role: .secondary))
            }
            if !currentReplies.isEmpty && display == .g2 {
                // G2 renders text rows only, and its loopback has no input route:
                // reply ideas are read as rows, chosen on the phone.
                result += paginate(content, heading: name, display: display).reversed()
            } else if !currentReplies.isEmpty {
                // The question stays above two independently selectable bilingual cards.
                let cards = currentReplies.enumerated().compactMap { index, reply -> GlassesScene.Card? in
                    guard let id = session.replyActionID(at: index) else { return nil }
                    return .init(id: id, title: reply.text, detail: reply.gloss, focused: preferred == index)
                }
                let compact = GlassesScene(lines: [.init(name, role: .status),
                    .init(turn.source, role: .status), .init(turn.translation, role: .status)],
                    actions: [], cards: cards)
                let layout = MetaRender.layout(for: compact)
                if compact.lines.count <= MetaRender.maximumLines &&
                    layout.items.allSatisfy({ MetaPanelLayout.column.contains($0.frame) }) &&
                    layout.textBlocks.allSatisfy({ !$0.overflowsWidth }) {
                    result.append(compact)
                } else {
                    // Unbounded provider text cannot fit a physical panel. Preserve
                    // every character, and land on the question rather than a reply.
                    result += paginate(content, heading: name, display: display, actions: actions).reversed()
                }
            } else {
                result += paginate(content, heading: name, display: display)
            }
        }
        if let pending = session.pending {
            let hasText = !pending.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let speaker = speakerName(of: pending.speaker, wearer: wearer, guestName: guestName)
            result += paginate([.init(hasText ? pending.source : "Listening…")],
                               heading: "\(speaker) · listening", display: display)
        }
        return result
    }

    private static func speakerName(of speaker: Participant, wearer: Participant, guestName: String) -> String {
        if speaker == wearer { return "You" }
        if speaker == .lin { return guestName }
        return "Partner"
    }

    private static func paginate(_ content: [GlassesScene.Line], heading: String,
                                 display: GlassesDisplay, actions: [GlassesScene.Action] = []) -> [GlassesScene] {
        let header = GlassesScene.Line(heading, role: .heading)
        var pages: [GlassesScene] = []
        var page = GlassesScene(lines: [header], actions: actions)
        for line in content {
            for row in rows(line, display: display) {
                let item = GlassesScene.Line(row, role: line.role)
                var proposed = page
                proposed.lines.append(item)
                if !fits(proposed, display: display), page.lines.count > 1 {
                    pages.append(page)
                    page = GlassesScene(lines: [header, item], actions: actions)
                } else { page = proposed }
            }
        }
        if page.lines.count > 1 { pages.append(page) }
        return pages
    }

    /// Break at Character boundaries, including whitespace-free Chinese and
    /// long tokens. No suffix truncation or ellipsis. Explicit newlines become
    /// physical row boundaries (blank rows are not rendered by shared Meta).
    private static func rows(_ line: GlassesScene.Line, display: GlassesDisplay) -> [String] {
        var output: [String] = []
        let style = textStyle(line.role)
        let font = MetaTypeface.default.font(size: style.pointSize, bold: style.bold)
        for paragraph in line.text.components(separatedBy: .newlines) where !paragraph.isEmpty {
            let characters = Array(paragraph)
            var offset = 0
            while offset < characters.count {
                let remaining = characters.count - offset
                var low = 1
                var high = 1
                func fitsRow(_ count: Int) -> Bool {
                    let text = String(characters[offset..<(offset + count)])
                    if display == .g2 {
                        return G2FontMetrics.pixelWidth(of: text) <= G2FontMetrics.usablePixelWidth
                    }
                    let attributed = NSAttributedString(string: text, attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font
                    ])
                    let measured = CTLineCreateWithAttributedString(attributed)
                    return CTLineGetTypographicBounds(measured, nil, nil, nil) <= MetaPanelLayout.column.width
                }
                while high < remaining && fitsRow(high) {
                    low = high
                    high = min(remaining, high * 2)
                }
                while low < high {
                    let middle = (low + high + 1) / 2
                    if fitsRow(middle) { low = middle } else { high = middle - 1 }
                }
                output.append(String(characters[offset..<(offset + low)]))
                offset += low
            }
        }
        return output
    }

    private static func fits(_ scene: GlassesScene, display: GlassesDisplay) -> Bool {
        if display == .g2 {
            return scene.lines.count <= G2Render.visibleRows && scene.lines.allSatisfy {
                G2FontMetrics.pixelWidth(of: $0.text) <= G2FontMetrics.usablePixelWidth
            }
        }
        guard scene.lines.count <= MetaRender.maximumLines else { return false }
        // Rows already fit the shared font and column width. Sum the same
        // line boxes/spacing/button height as MetaPanelLayout without rebuilding
        // a full renderer tree for every candidate row in long histories.
        let count = scene.lines.count + (scene.actions.isEmpty ? 0 : 1)
        let textHeight = scene.lines.reduce(0.0) { $0 + textStyle($1.role).lineHeight }
        let buttonHeight = scene.actions.isEmpty ? 0 : MetaDisplaySpec.buttonHeight
        let spacing = MetaDisplaySpec.rootSpacing * Double(max(0, count - 1))
        return textHeight + buttonHeight + spacing <= MetaPanelLayout.column.height
    }

    private static func textStyle(_ role: GlassesScene.Role) -> MetaDisplaySpec.TextStyleSpec {
        switch role {
        case .heading: MetaDisplaySpec.heading
        case .body, .secondary: MetaDisplaySpec.body
        case .status: MetaDisplaySpec.meta
        }
    }
}
