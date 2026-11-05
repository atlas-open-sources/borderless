#if os(iOS)
import Foundation
import MetaDisplayKit
import MetaConnectionPolicy
import MWDATDisplay
import UIKit

/// The only component-tree bridge. Device ownership lives in MetaConnection.
/// No SwiftUI import: DAT's Text/Button/Image types deliberately stay unambiguous.
public final class DATSceneSink: MetaDisplaySink, @unchecked Sendable {
    private let display: Display
    private let actionLock = NSLock()
    private var actions = SceneActionLease<MetaScene>()
    private let action: @MainActor @Sendable (String) -> Void
    public init(display: Display, onAction: @escaping @MainActor @Sendable (String) -> Void) {
        self.display = display
        self.action = onAction
    }
    public func invalidateActions() {
        actionLock.withLock { actions.invalidate() }
    }
    public func prepare(_ scene: MetaScene) {
        actionLock.withLock {
            actions.prepare(scene)
        }
    }
    public func show(_ scene: MetaScene) async throws {
        let token = actionLock.withLock { actions.beginSend() }
        try await display.send(Self.view(scene) { [weak self] id in
            Task { @MainActor [weak self] in
                guard let self, self.actionLock.withLock({ self.actions.accepts(token, scene: scene) }) else { return }
                self.action(id)
            }
        })
    }
    public func clear() async throws { invalidateActions(); try await display.clearDisplay() }
    public static func view(_ scene: MetaScene, action: @escaping @Sendable (String) -> Void) -> FlexBox {
        FlexBox(direction: .column, spacing: 8, alignment: .start, crossAlignment: .stretch) {
            if let picture = scene.picture, let image = UIImage(data: picture.data) {
                Image(image: image, sizePreset: .fill)
            }
            for line in scene.lines {
                Text(line.text, style: textStyle(line.role), color: line.secondary ? .secondary : .primary)
            }
            for card in scene.cards {
                FlexBox(direction: .column, spacing: MetaPanelLayout.cardSpacing,
                        alignment: .start, crossAlignment: .stretch) {
                    Text((card.focused ? "› " : "") + card.title, style: .meta,
                         color: .primary)
                    Text(card.detail, style: .meta, color: .secondary)
                }
                .padding(MetaPanelLayout.cardPadding)
                .background(.card)
                .onTap { action(card.id) }
            }
            if !scene.actions.isEmpty {
                ButtonGroup(alignment: .start) {
                    for item in scene.actions {
                        Button(label: item.label, style: item.primary ? .primary : .secondary,
                               onClick: { action(item.id) })
                    }
                }
            }
        }.padding(16)
    }
    private static func textStyle(_ role: MetaScene.TextRole) -> TextStyle {
        switch role {
        case .heading: .heading
        case .body: .body
        case .meta: .meta
        }
    }
}
#endif
