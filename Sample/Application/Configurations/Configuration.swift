import Foundation

enum Configuration {
    
    enum Error: Swift.Error {
        case missingKey
        case invalidValue
    }

    static func value<T>(for key: String) throws -> T where T: LosslessStringConvertible {
        guard let object = Bundle.main.object(forInfoDictionaryKey: key) else {
            throw Error.missingKey
        }

        switch object {
        case let value as T:
            return value
        case let string as String:
            guard let value = T(string) else { fallthrough }
            return value
        default:
            throw Error.invalidValue
        }
    }
    
}

extension Configuration {
    
    static var googleServiceInfoPlistName: String {
        return "https://" + (try! Configuration.value(for: "GOOGLE_SERVICE_INFO_PLIST_NAME"))
    }

    static var apiBaseURL: String {
        return "https://" + (try! Configuration.value(for: "API_BASE_URL"))
    }

    // TODO: Should be removed as soon as API provides full sharing url in required models
    static var tipSharingURL: String {
        return "https://" + (try! Configuration.value(for: "TIP_SHARING_URL"))
    }
    
    static var termsURL: String {
        return "https://" + (try! Configuration.value(for: "TERMS_URL"))
    }
    
    static var privacyURL: String {
        return "https://" + (try! Configuration.value(for: "PRIVACY_URL"))
    }

    static var brazeApiKey: String {
        return try! Configuration.value(for: "BRAZE_API_KEY")
    }

    static var segmentWriteKey: String {
        try! Configuration.value(for: "SEGMENT_WRITE_KEY")
    }

    static var sentryDsn: String {
        return "https://" + (try! Configuration.value(for: "SENTRY_DSN"))
    }
}
