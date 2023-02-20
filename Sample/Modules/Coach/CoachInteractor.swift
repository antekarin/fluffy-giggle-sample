import Foundation
import RxSwift
import RxCocoa
import SwiftDate

final class CoachInteractor {
    private let timelineService: TimelineServiceable
    private let tipService: TipsServiceable
    private let userDefaultsService: UserDefaultsStorageServiceable
    private let userService: UserServiceable
    private let chatService: ChatServiceable
    private let analyticsService: AnalyticsServiceable
    private let router: AppRouteable

    init(
        timelineService: TimelineServiceable = TimelineService.instance,
        tipService: TipsServiceable = TipsService.instance,
        userDefaultsService: UserDefaultsStorageServiceable = UserDefaultsStorageService.instance,
        userService: UserServiceable = UserService.instance,
        chatService: ChatServiceable = ChatService.instance,
        analyticsService: AnalyticsServiceable = AnalyticsService.instance,
        sharedTipStorageService: SharedTipStorageServiceable = SharedTipStorageService.instance,
        router: AppRouteable
    ) {
        self.timelineService = timelineService
        self.tipService = tipService
        self.userDefaultsService = userDefaultsService
        self.userService = userService
        self.chatService = chatService
        self.analyticsService = analyticsService
        self.router = router
    }
}

// MARK: - Extensions
extension CoachInteractor: CoachInteractorInterface {
    func getTimelineDayItems() -> Single<[TimelineDayViewItem]> {
        timelineService.getTimelineDays()
            .map { $0.map { TimelineDayViewItem(date: $0.date, isSelected: false, isCompleted: $0.tipsCompleted > 0, isBeforeSignup: $0.beforeSignup) }
            }
    }

    func getTimelineTips(date: Date) -> Single<APITimelineTips> {
        return timelineService
            .getTimelineTips(date: date)
    }

    func skipTip(with ID: String) -> Single<APITip> {
        return tipService.skipTip(withID: ID)
    }

    func saveTip(withID id: String) -> Single<Void> {
        analyticsService.logEvent(AnalyticsTipPreviewEvent.savedTip(tipId: id, source: .coach))
        return tipService.saveTip(withID: id)
    }

    func unsaveTip(withID id: String) -> Single<Void> {
        analyticsService.logEvent(AnalyticsTipPreviewEvent.unsavedTip(tipId: id, source: .coach))
        return tipService.unsaveTip(withID: id)
    }

    func isTipSaved(withID id: String) -> Infallible<Bool> {
        tipService.isTipSaved(withID: id)
    }

    func saveCompletedDailySessionTimestamp(date: Date) -> Single<Void> {
        let timestamp = date.timeIntervalSince1970
        userDefaultsService.save(value: timestamp, for: .dailySessionCompletedTimestamp)
        return Single.just(())
    }

    func completedDailySessionTimestamp() -> Date? {
        let timestamp: TimeInterval? = userDefaultsService.value(forKey: .dailySessionCompletedTimestamp)
        if let timestamp = timestamp {
            return Date(timeIntervalSince1970: timestamp)
        } else {
            return nil
        }
    }

    var didCompleteTip: Infallible<APITimelineTips> {
        tipService.didCompleteTip

    }

    func unlockTip(withID tipID: String, date: Date, isDailyTip: Bool) -> Single<APITimelineTips> {
        timelineService.unlockTip(withID: tipID, date: date, isDailyTip: isDailyTip)
    }

    func unlockTip(withID tipID: String) -> Single<Void> {
        tipService.unlockTip(withID: tipID)
    }

    var userDisplayName: Infallible<String?> {
        userService
            .userDisplayName
            .distinctUntilChanged()
            .asInfallible(onErrorFallbackTo: .empty())
    }

    func presentMessenger() {
        chatService.presentMessenger()
    }

    func trackScreenView() {
        analyticsService.logScreen(AnalyticsScreen.coach)
    }

    func trackDailyTipTap() {
        analyticsService.logEvent(AnalyticsCoachTabEvent.tappedDailyTip)
    }

    func trackKeepGoingTap(count: Int, tipID: String) {
        analyticsService.logEvent(AnalyticsCoachTabEvent.tappedKeepGoing(count: count, tipID: tipID))
    }

    func trackCallItADayTap() {
        analyticsService.logEvent(AnalyticsCoachTabEvent.tappedCallItADay)
    }

    func trackBackToTodayTap(sourceDayOffset: Int) {
        analyticsService.logEvent(AnalyticsCoachTabEvent.tappedBackToToday(sourceDayOffset: sourceDayOffset))
    }

    func trackExploredDaysTap(dayOffset: Int) {
        analyticsService.logEvent(AnalyticsCoachTabEvent.exploredDays(dayOffset: dayOffset))
    }

    func trackGoOnExploreTap() {
        analyticsService.logEvent(AnalyticsCoachTabEvent.tappedGoOnExplore)
    }

    func trackChatTap() {
        analyticsService.logEvent(AnalyticsCoachTabEvent.tappedChat)
    }

    func trackDailyTipCompletion() {
        analyticsService.logEvent(AnalyticsCoachTabEvent.dailyTipCompletion)
    }

    func dailyTipTrigger() -> Signal<Void> {
        router.route
            .filter { $0 == .dailyTip }
            .mapToVoid()
    }
}
