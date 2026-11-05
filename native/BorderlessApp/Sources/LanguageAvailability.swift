import SwiftUI
import BorderlessCore

/// Recognition support does not promise pairwise translation quality.
/// Source: https://dev.meta.ai/docs/speech-to-text, checked 2026-11-02.
enum LanguageAvailability {
    static let activePair = "English ↔ Spanish"
    static let codes = ConversationLanguages.names.keys.sorted {
        name($0).localizedStandardCompare(name($1)) == .orderedAscending
    }
    static let speechLanguages = codes.map { name($0) }
    static func name(_ code: String) -> String { ConversationLanguages.names[code] ?? code.uppercased() }
    static func pair(host: String, guest: String) -> String { "\(name(host)) ↔ \(name(guest))" }
    static func experimental(host: String, guest: String) -> Bool { host != "en" || guest != "es" }
}

struct LanguageAvailabilityView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hostLanguage: String
    @Binding var guestLanguage: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: $hostLanguage) {
                        ForEach(LanguageAvailability.codes.filter { $0 != guestLanguage }, id: \.self) { code in
                            Text(LanguageAvailability.name(code)).tag(code)
                        }
                    } label: { Label("Your language", systemImage: "person") }
                    Picker(selection: $guestLanguage) {
                        ForEach(LanguageAvailability.codes.filter { $0 != hostLanguage }, id: \.self) { code in
                            Text(LanguageAvailability.name(code)).tag(code)
                        }
                    } label: { Label("Guest's language", systemImage: "person.2") }
                } header: { Text("Live conversation") } footer: {
                    Text("Translation goes both ways. Only you receive reply ideas in your guest's language, with meanings in yours.")
                }
                Section {
                    if LanguageAvailability.experimental(host: hostLanguage, guest: guestLanguage) {
                        Label("This pair has not been tested", systemImage: "flask")
                        Text("You can try it now. Recognition, translation quality and glasses text may vary. Pronunciation playback is not yet available for this pair.")
                            .font(.subheadline).foregroundStyle(BorderlessTheme.muted)
                    } else {
                        Label("English–Spanish pipeline tested", systemImage: "checkmark.circle")
                    }
                    Link(destination: URL(string: "https://dev.meta.ai/docs/speech-to-text")!) {
                        Label("Meta speech language documentation", systemImage: "arrow.up.right.square")
                    }
                } header: { Text("Language availability") } footer: {
                    Text("The recorded demo always uses English and Spanish, independently of your live language choice.")
                }
            }
            .borderlessSheet()
            .navigationTitle("Languages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
