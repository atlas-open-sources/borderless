import SwiftUI
import BorderlessCore

/// Independent follow state for each transcript surface; user drag detaches,
/// reaching the bottom or twenty idle seconds resumes.
struct FollowHistory<Content: View>: View {
    let revision: String
    @ViewBuilder let content: () -> Content
    @State private var follow = HistoryFollow()
    @State private var interacting = false
    @State private var atBottom = true
    private let bottom = "history-bottom"
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                    Color.clear.frame(height: 1).id(bottom)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY <= 32
            } action: { _, value in
                atBottom = value
                if interacting || !follow.following {
                    follow.scroll(atBottom: value, now: now)
                }
            }
            .onScrollPhaseChange { _, phase in
                interacting = phase == .tracking || phase == .interacting || phase == .decelerating
                if interacting { follow.scroll(atBottom: atBottom, now: now) }
                else if !follow.following { follow.activity(now: now) }
            }
            .onChange(of: revision) {
                if follow.following { reader.scrollTo(bottom, anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !follow.following {
                    Button("Latest ↓") {
                        follow.resume()
                        withAnimation { reader.scrollTo(bottom, anchor: .bottom) }
                    }
                    .font(.caption.bold()).buttonStyle(.borderedProminent).padding(8)
                }
            }
            .task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) }
                    catch { return }
                    if interacting { follow.activity(now: now) }
                    else if follow.tick(now: now) {
                        withAnimation { reader.scrollTo(bottom, anchor: .bottom) }
                    }
                }
            }
        }
    }
}
