import UIKit
import RxSwift
import RxCocoa
import RxDataSources

protocol CoachWireframeInterface: WireframeInterface {
    func navigateToExplore()
    func navigateToTipPreview(tipId: String, source: Tip.Source)
}

protocol CoachViewInterface: ViewInterface {
    func show(toast: ToastView)
}

protocol CoachPresenterInterface: PresenterInterface {
    func configure(with output: Coach.ViewOutput) -> Coach.ViewInput
}

protocol CoachInteractorInterface: InteractorInterface {
    func getTimelineDayItems() -> Single<[TimelineDayViewItem]>
    func getTimelineTips(date: Date) -> Single<APITimelineTips>
    var didCompleteTip: Infallible<APITimelineTips> { get }
    func skipTip(with ID: String) -> Single<APITip>
    func saveTip(withID id: String) -> Single<Void>
    func unsaveTip(withID id: String) -> Single<Void>
    func isTipSaved(withID id: String) -> Infallible<Bool>
    func saveCompletedDailySessionTimestamp(date: Date) -> Single<Void>
    func completedDailySessionTimestamp() -> Date?
    func unlockTip(withID tipID: String) -> Single<Void>
    var userDisplayName: Infallible<String?> { get }
    func presentMessenger()
    func dailyTipTrigger() -> Signal<Void>

    func trackScreenView()
    func trackDailyTipTap()
    func trackKeepGoingTap(count: Int, tipID: String)
    func trackCallItADayTap()
    func trackBackToTodayTap(sourceDayOffset: Int)
    func trackExploredDaysTap(dayOffset: Int)
    func trackGoOnExploreTap()
    func trackChatTap()
    func trackDailyTipCompletion()
}

enum Coach {

    struct ViewOutput {
        let backToTodayAction: Signal<Void>
        let chatAction: Signal<Void>
        let tipCompletedAnimationStarted: Signal<Void>
    }

    struct ViewInput {
        let timelineItem: Driver<TipsTimelineViewItem>
        let sectionItems: Driver<[TipsSectionType]>
        let infoOverlayItem: Driver<InfoViewItem?>
        let isBackToTodayShown: Driver<Bool>
        let shouldFadeTipsView: Driver<Void>
        let setContentViewsHidden: Driver<Bool>
        let isTipsScrollEnabled: Driver<Bool>
        let selectedDate: Driver<Date>
        let animateUnlockNextTip: Driver<TipCardViewItem>
        let animateTipCompletion: Driver<Int>
        let animateCallItADay: Driver<String?>
        let isLoaderShown: Driver<Bool>
    }

    enum CellType {
        case headline(HeadlineViewItem)
        case tip(TipCardViewItem)
        case exploreTip(TipCardViewItem)
        case getDifferentTip(DifferentTipCellItem)
        case lockedTip(TipLockedCellItem)
        case exploreNote(ExploreNoteCellItem)
        case unlockNewTip(UnlockTipViewItem)
        case headerTitle(SimpleLabelCellItem)
        case separator
    }

    struct TipsSectionType {
        var items: [Coach.CellType]
    }

}

extension Coach.TipsSectionType: SectionModelType {
    typealias Item = Coach.CellType

    init(original: Coach.TipsSectionType, items: [Item]) {
        self = original
        self.items = items
    }
}

extension Coach.CellType {

    var tipItem: TipCardViewItem? {
        switch self {
        case let .tip(item):
            return item
        default:
            return nil
        }
    }

}
