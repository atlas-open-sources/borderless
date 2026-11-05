import Foundation
import BorderlessRelay

/// The translation service this build is provisioned for. Never contains provider keys.
///
/// Debug prefers the attended development service, from the ignored `.budget/device-service.json` the
/// build phase copies in. Otherwise, and always in Release, the hosted relay from Info.plist
/// (`BorderlessRelayAddress`, `BorderlessRelayClientKey`, from the ignored Config/Relay.local.xcconfig).
/// The release client key ships in the app and is not a secret; the relay's limits protect the service.
enum DevelopmentServiceConfig {
    private struct Configuration: Decodable { let address: String; let token: String }
    private static let tokenLengths = 32...256

    private static let configuration: Configuration? = {
        #if DEBUG
        if let url = Bundle.main.url(forResource: "BorderlessService", withExtension: "json"),
           let bytes = try? Data(contentsOf: url),
           let value = try? JSONDecoder().decode(Configuration.self, from: bytes) {
            return validated(value)
        }
        #endif
        return hosted
    }()

    /// The hosted relay from Info.plist; empty unless Relay.local.xcconfig was written for this build.
    private static var hosted: Configuration? {
        guard let address = Bundle.main.object(forInfoDictionaryKey: "BorderlessRelayAddress") as? String,
              let token = Bundle.main.object(forInfoDictionaryKey: "BorderlessRelayClientKey") as? String
        else { return nil }
        return validated(Configuration(address: address, token: token))
    }

    private static func validated(_ value: Configuration) -> Configuration? {
        guard value.address.hasPrefix("wss://"),
              (try? RelayEndpoint(validating: value.address)) != nil,
              tokenLengths.contains(value.token.count) else { return nil }
        return value
    }

    static var address: String? { configuration?.address }
    static var token: String? { configuration?.token }
}
