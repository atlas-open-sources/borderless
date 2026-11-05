import Foundation
import BorderlessCore
import BorderlessDisplay
import EvenCompanionKit
import GlassesSceneKit
import Swifter

/// Constructed only from the guest projection; safe to precompute off the UI thread.
public struct GuestProjection: Sendable {
    public let pages: [GlassesScene]
    public init(_ conversation: Conversation) {
        pages = ConversationViewport.pages(conversation, wearer: .lin)
    }
}

/// Single-glasses mode: the one G2 wearer is the host, so their own reply
/// ideas are included by design. Never publish this in two-glasses mode.
public struct WearerProjection: Sendable {
    public let pages: [GlassesScene]
    public init(_ conversation: Conversation, guestName: String = "Sofía") {
        pages = ConversationViewport.pages(conversation, wearer: .alex, display: .g2, guestName: guestName)
    }
}

/// One explicitly enabled, foreground loopback publisher. No microphone route.
@MainActor public final class G2Companion {
    public static let port: UInt16 = 8767
    public private(set) var enabled = false
    private var server: HttpServer?
    private var routes: CompanionRoutes?
    private var frames: GlassesFrameStore?
    private let layout = GlassesLayoutFactory.textPage(id: "borderless-guest-v1", regions: [
        .init(id: 1, name: "conversation", x: 0, y: 0, w: 576, h: 288)
    ], menu: [])
    public init() {}

    public func start() throws {
        guard !enabled else { return }
        let frames = GlassesFrameStore()
        let routes = CompanionRoutes(identity: .init(appName: "Borderless", version: "0.1.0",
            build: "1", capabilities: [], wantsGlasses: { true }),
            frames: frames, events: GlassesEventStore(), metrics: nil)
        let server = HttpServer()
        // Only read-only display routes. No audio/control/privacy input accepted.
        for path in ["/glasses/hello", "/glasses/frame"] {
            server[path] = Self.handler(routes)
        }

        server.listenAddressIPv4 = "127.0.0.1"
        try server.start(Self.port, forceIPv4: true, priority: .userInitiated)
        self.frames = frames
        self.routes = routes
        self.server = server
        enabled = true
    }

    private nonisolated static func handler(_ routes: CompanionRoutes) -> (HttpRequest) -> HttpResponse {
        { request in
            guard request.method == "GET" || request.method == "OPTIONS" else { return .forbidden }
            let answer = routes.handle(.init(method: request.method, path: request.path,
                query: request.queryParams.map { (name: $0.0, value: $0.1) }))
            guard let answer else { return .notFound }
            return .raw(answer.status, "", answer.headers, { writer in try writer.write(answer.body) })
        }
    }

    public func publish(_ conversation: Conversation, page: Int? = nil) {
        guard enabled else { return }
        publish(GuestProjection(conversation), page: page)
    }

    public func publish(_ projection: GuestProjection, page: Int? = nil) {
        publish(pages: projection.pages, page: page)
    }

    public func publish(_ projection: WearerProjection, page: Int? = nil) {
        publish(pages: projection.pages, page: page)
    }

    private func publish(pages: [GlassesScene], page: Int?) {
        guard enabled, let frames else { return }
        let content: String
        if pages.isEmpty { content = "" }
        else {
            let index = min(max(0, page ?? pages.count - 1), pages.count - 1)
            content = G2Render.rows(for: pages[index]).joined(separator: "\n")
        }
        let frame = GlassesFrame(seq: 0, layout: layout,
            ops: [.text(id: 1, content: content, brightness: nil)])
        frames.set(frame: frame, layout: layout)
    }

    public func stop() {
        // Drop stored text and stop serving it; a remote display may retain its
        // last frame until the plugin disconnect UI runs. Do not claim erasure.
        server?.stop()
        server = nil; routes = nil; frames = nil
        enabled = false
    }

    public static func guestText(_ conversation: Conversation, page: Int? = nil) -> String {
        let pages = ConversationViewport.pages(conversation, wearer: .lin)
        guard !pages.isEmpty else { return "" }
        let scene = pages[min(max(0, page ?? pages.count - 1), pages.count - 1)]
        return G2Render.rows(for: scene).joined(separator: "\n")
    }

}
