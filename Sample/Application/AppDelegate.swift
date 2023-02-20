import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    // MARK: - Public properties -

    var mainWindow: UIWindow { window }

    // MARK: - Private properties -

    private lazy var window = createWindow()
    private let deepLinkHandlers = DeepLinkHandlers.handlers
    
    // MARK: - Public functions -

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Dependencies
        initializeDependencies()

        // Window
        window.makeKeyAndVisible()

        log.info("App did finish launching...")
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        deepLinkHandlers.handle(app, open: url, options: options)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        deepLinkHandlers.handle(application, continue: userActivity, restorationHandler: restorationHandler)
    }

}

// MARK: - Dependencies -

private extension AppDelegate {

    func initializeDependencies() {
        let initializers: [Initializable] = [
            InstallationInitializer(),
            FirebaseInitializer(),
            SegmentInitializer(),
            PushNotificationServiceInitializer(),
            BrazeInitializer(),
            AnalyticsCollectorInitializer(),
            TweaksInitializer(),
            LoggerInitializer(),
            LoggieInitializer(),
            AppearanceInitializer(),
            ChatServiceInitializer(),
            AudioSessionInitializer(),
            UserServiceInitializer(),
            UserAnalyticsInitializer(),
            PushNotificationAnalyticsServiceInitializer(),
            ReachabilityServiceInitializer(),
            AppLifecycleServiceInitializer(),
        ]

        initializers.forEach { $0.initialize() }
    }

}

// MARK: - Window and initial view controller -

private extension AppDelegate {

    func createWindow() -> Window {
        let window = Window(frame: UIScreen.main.bounds)
        window.tintColor = .sampleCodeGreen2
        window.backgroundColor = .sampleCodeBlack

        window.rootViewController = createInitialViewController()

        return window
    }

    func createInitialViewController() -> UIViewController {
        return Self.wireframe().viewController
    }

    static func wireframe() -> BaseWireframe {
        if AuthenticationService.instance.isUserCurrentlyLoggedIn {
            if OnboardingService.instance.isOnboardingFinished {
                return TabBarWireframe()
            } else {
                return OnboardingIntroWireframe()
            }
        } else if WelcomeVideoService.instance.shouldShowVideo {
            return WelcomeVideoWireframe()
        } else {
            return LoginWireframe()
        }
    }
}
