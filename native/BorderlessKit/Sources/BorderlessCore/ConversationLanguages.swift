import Foundation

/// Speech recognition catalog. Pairwise conversation quality remains experimental.
public enum ConversationLanguages {
    public static let names: [String: String] = [
        "ar": "Arabic", "bn": "Bengali", "nl": "Dutch", "en": "English",
        "fr": "French", "de": "German", "he": "Hebrew", "hi": "Hindi",
        "id": "Indonesian", "it": "Italian", "ja": "Japanese", "kn": "Kannada",
        "ko": "Korean", "ms": "Malay", "zh": "Mandarin Chinese", "mr": "Marathi",
        "pl": "Polish", "pt": "Portuguese", "es": "Spanish", "tl": "Tagalog",
        "ta": "Tamil", "te": "Telugu", "th": "Thai", "tr": "Turkish", "vi": "Vietnamese"
    ]
    public static func validPair(_ pair: [String]) -> Bool {
        pair.count == 2 && pair[0] != pair[1] && pair.allSatisfy { names[$0] != nil }
    }
}
