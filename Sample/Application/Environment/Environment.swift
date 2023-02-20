import Foundation

enum Environment {
    case development
    case staging
    case preprod
    case appStore
}

extension Environment {

    static var current: Environment {
        #if APPSTORE
        return .appStore
        #elseif STAGING
        return .staging
        #elseif PREPROD
        return .preprod
        #else
        return .development
        #endif
    }

    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var isTestFlight: Bool {
        return Bundle.main.appStoreReceiptURL?.path.contains("sandboxReceipt") ?? false
    }

    static var isTesting: Bool {
        Environment.current == .development || Environment.current == .staging || Environment.current == .preprod || Environment.isDebug
    }

}
