import SwiftUI

/// Shared visual identity from brand/tokens.json; participant colors retain meaning.
enum BorderlessTheme {
    static let paper = Color(red: 243 / 255, green: 238 / 255, blue: 228 / 255)
    static let ink = Color(red: 26 / 255, green: 23 / 255, blue: 20 / 255)
    static let muted = Color(red: 110 / 255, green: 105 / 255, blue: 98 / 255)
    static let line = Color(red: 221 / 255, green: 214 / 255, blue: 200 / 255)
    static let host = Color(red: 36 / 255, green: 93 / 255, blue: 206 / 255)
    static let guest = Color(red: 32 / 255, green: 118 / 255, blue: 73 / 255)
    /// Raised surfaces on paper: preview cards, the bottom bar, header buttons.
    static let card = Color.white.opacity(0.7)
    static let cardRadius: CGFloat = 16
}

/// Room between one section's footer and the next header.
private let sheetSectionSpacing: CGFloat = 24

extension View {
    /// Sheets share one look: paper behind white grouped rows, host-blue accents, inline title.
    func borderlessSheet() -> some View {
        scrollContentBackground(.hidden)
            .listSectionSpacing(sheetSectionSpacing)
            .background(BorderlessTheme.paper)
            .tint(BorderlessTheme.host)
            .navigationBarTitleDisplayMode(.inline)
    }
}
