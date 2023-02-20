import Foundation
import Kingfisher
import RxSwift
import RxCocoa
import SwiftDate
import Alamofire

final class CoachPresenter {

    // MARK: - Private properties -

    private unowned let view: CoachViewInterface
    private let interactor: CoachInteractorInterface
    private let wireframe: CoachWireframeInterface

    private let sectionItems = BehaviorRelay<[Coach.CellType]>(value: [])
    private let timelineViewItem = BehaviorRelay<TipsTimelineViewItem>(value: TipsTimelineViewItem.emptyItem)

    private let localReloadTrigger = PublishRelay<Void>()
    private let refetchTipsTrigger = PublishSubject<Void>()

    private let errorOverlay = PublishSubject<InfoViewItem?>()
    private let areContentViewsHidden = PublishSubject<Bool>()
    private let shouldFadeTipsView = PublishSubject<Void>()
    private let currentTipItem = BehaviorRelay<TipCardViewItem?>(value: nil)

    private let todayTimelineTips = BehaviorRelay<APITimelineTips?>(value: nil)

    private var unlockedTipIDs = [String]()
    private let animateUnlockNextTip = PublishRelay<TipCardViewItem>()
    private let animateCallItADay = PublishRelay<String?>()
    private let scheduleAnimateTipCompletion = PublishRelay<Int>()

    private let isLoaderShown = BehaviorRelay<Bool>(value: true)

    private let disposeBag = DisposeBag()

    // MARK: - Lifecycle -

    init(view: CoachViewInterface, interactor: CoachInteractorInterface, wireframe: CoachWireframeInterface) {
        self.view = view
        self.interactor = interactor
        self.wireframe = wireframe
    }

}

// MARK: - Extensions -

extension CoachPresenter: CoachPresenterInterface {

    func configure(with output: Coach.ViewOutput) -> Coach.ViewInput {
        view
            .didAppearWithAppDidBecomeActive
            .emit(onNext: { [interactor] in
                interactor.trackScreenView()
            })
            .disposed(by: disposeBag)

        refetchTipsTrigger
            .startWith(())
            .flatMap { [weak self] _ -> Single<[TimelineDayViewItem]> in
                guard let self = self else {
                    return Single.just([])
                }
                return self.interactor.getTimelineDayItems()
            }
            .map { TipsTimelineViewItem(last8DayItems: $0) ?? TipsTimelineViewItem.emptyItem }
            .asDriver(onErrorJustReturn: TipsTimelineViewItem.emptyItem)
            .drive(timelineViewItem)
            .disposed(by: disposeBag)

        let selectedDate = timelineViewItem
            .flatMap { $0.selectedDate }
            .scan(Date(), accumulator: { oldValue, newValue in
                if APIShortDateFormatter.instance.string(for: oldValue) == APIShortDateFormatter.instance.string(for: newValue) {
                    return oldValue
                }
                return newValue
            })
            .distinctUntilChanged()
            .asDriverOnErrorComplete()

        selectedDate
            .do { [unowned interactor] date in
                let dayOffset = date.weekday - TipsTimelineViewItem.today.weekday
                interactor.trackExploredDaysTap(dayOffset: dayOffset)
            }
            .drive()
            .disposed(by: disposeBag)

        let reloadTips = refetchTipsTrigger
            .mapTo(TipsTimelineViewItem.today)
            .asDriver(onErrorJustReturn: TipsTimelineViewItem.today)
            .throttle(.milliseconds(100))

        configureTipsDisplay(selectedDate: selectedDate, reloadTips: reloadTips)

        let isTipsScrollEnabled = selectedDate
            .map { !$0.isSameDayAsTomorrow }
            .asDriver(onErrorJustReturn: true)

        let isBackToTodayShown = selectedDate
            .map { $0.isSameDayAsTomorrow || $0.isBefore(date: TipsTimelineViewItem.today, granularity: .day) }
            .distinctUntilChanged()

        let showFutureDayOverlay = selectedDate
            .map { ($0.isInFuture && !$0.isSameDayAsTomorrow && !$0.isSameDayAsToday) ? InfoViewItem.futureDate(date: $0) : nil}
            .asDriver(onErrorJustReturn: nil)

        let showLandBeforeSampleCodeOverlay = timelineViewItem
            .flatMap { $0.selectedDayViewItem }
            .map { item -> InfoViewItem? in
                if let item = item, !item.date.value.isSameDayAsToday {
                    return item.isBeforeSampleCode.value ? InfoViewItem.preSampleCodeDayItem(date: item.date.value) : nil
                } else {
                    return nil
                }
            }
            .asDriver(onErrorJustReturn: nil)

        let infoOverlayItem = Driver.combineLatest(showLandBeforeSampleCodeOverlay, showFutureDayOverlay, errorOverlay.asDriver(onErrorJustReturn: nil)) { beforeSampleCode, futureDay, error -> InfoViewItem? in
            return [beforeSampleCode, futureDay, error].compactMap { $0 }.first
        }
        .startWith(nil)

        let tableViewItems = sectionItems
            .map { [Coach.TipsSectionType(items: $0)] }
            .asDriver(onErrorJustReturn: [])

        currentTipItem
            .compactMap { $0 }
            .filter { !$0.isLoading.value }
            .flatMap { $0.reloadTrigger }
            .withLatestFrom(currentTipItem)
            .compactMap { $0 }
            .flatMap { [unowned self] item -> Driver<APITip> in
                item.isLoading.accept(true)
                return self.interactor
                    .skipTip(with: item.id.value)
                    .asDriver(onErrorDriveWith: Driver<APITip>.never())
            }
            .withLatestFrom(currentTipItem) { apiTip, currentTipItem in
                if let backgroundImageURL = apiTip.tipBackgroundImageURL {
                    let imageResource = ImageResource(downloadURL: backgroundImageURL)
                    KingfisherManager.shared.retrieveImage(with: imageResource) { result in
                        switch result {
                        case let .success(imageResult):
                            currentTipItem?.isLoading.accept(false)
                            currentTipItem?.backgroundImage.accept(imageResult.image)
                            currentTipItem?.updateWith(tip: apiTip)
                        case .failure:
                            currentTipItem?.isLoading.accept(false)
                            currentTipItem?.updateWith(tip: apiTip)
                        }
                    }
                } else {
                    currentTipItem?.isLoading.accept(false)
                    currentTipItem?.updateWith(tip: apiTip)
                }
            }
            .subscribe()
            .disposed(by: disposeBag)

        let backToTodayAction = Signal.merge([infoOverlayItem
                                                .compactMap()
                                                .flatMapLatest { $0.buttonAction.asSignalOnErrorComplete()
                                                },
                                              output.backToTodayAction])

        backToTodayAction
            .withLatestFrom(timelineViewItem.asSignalOnErrorComplete())
            .map { $0.selectedDate.value }
            .emit { [unowned interactor] date in
                let sourceDayOffset = date.weekday - TipsTimelineViewItem.today.weekday
                interactor.trackBackToTodayTap(sourceDayOffset:  sourceDayOffset)
            }
            .disposed(by: disposeBag)

        backToTodayAction
            .withLatestFrom(timelineViewItem.asSignalOnErrorComplete())
            .emit(onNext: { item in
                item.selectedDate.accept(TipsTimelineViewItem.today)
            })
            .disposed(by: disposeBag)

        output.tipCompletedAnimationStarted
            .mapToVoid()
            .emit(to: localReloadTrigger)
            .disposed(by: disposeBag)

        localReloadTrigger
            .withLatestFrom(todayTimelineTips)
            .compactMap { $0 }
            .flatMap({ tips -> Driver<[Coach.CellType]> in
                return Driver.just(())
                    .withLatestFrom(selectedDate)
                    .filter { $0.isSameDayAsToday }
                    .flatMap { [weak self] selectedDate -> Driver<[Coach.CellType]> in
                        guard let self = self else { return Driver.just([]) }
                        return self.configureCells(tips: tips, selectedDate: selectedDate)
                }
            })
            .asDriverOnErrorComplete()
            .drive(sectionItems)
            .disposed(by: disposeBag)

        configureTipCompletion()

        output.chatAction
            .do(onNext: { [unowned interactor] _ in
                interactor.trackChatTap()
            })
            .emit(onNext: { [unowned interactor] in
                interactor.presentMessenger()
            })
            .disposed(by: disposeBag)

        // App route handling
        handleDailyTip(trigger: interactor.dailyTipTrigger())

        return Coach.ViewInput(timelineItem: timelineViewItem.asDriver(),
                               sectionItems: tableViewItems,
                               infoOverlayItem: infoOverlayItem,
                               isBackToTodayShown: isBackToTodayShown,
                               shouldFadeTipsView: shouldFadeTipsView.asDriverOnErrorComplete(),
                               setContentViewsHidden: areContentViewsHidden.asDriverOnErrorComplete(),
                               isTipsScrollEnabled: isTipsScrollEnabled,
                               selectedDate: selectedDate,
                               animateUnlockNextTip: animateUnlockNextTip.asDriverOnErrorComplete(),
                               animateTipCompletion: scheduleAnimateTipCompletion.asDriverOnErrorComplete(),
                               animateCallItADay: animateCallItADay.asDriverOnErrorComplete(), isLoaderShown: isLoaderShown.asDriverOnErrorComplete().startWith(true))
    }

    func configureTipsDisplay(selectedDate: Driver<Date>, reloadTips: Driver<Date>) {
        Driver<Date>.merge([selectedDate,
                            reloadTips])
            .filter { [unowned self] date in
                if let preSampleCodeDate = self.timelineViewItem.value.preSampleCodeDate.value, date < preSampleCodeDate {
                    return false
                } else {
                    return true
                }
            }
            .flatMap { [unowned self] date -> Driver<[Coach.CellType]> in
                let dataLoading = Observable.just([])
                    .concat(loadTips(date).asObservable())
                    .asDriver(onErrorJustReturn: [])
                return dataLoading
            }
            .do(onNext: { [unowned self] _ in
                self.errorOverlay.onNext(nil)
            })
            .drive(sectionItems)
            .disposed(by: disposeBag)
    }

    private func configureTipCompletion() {
        typealias TipsUpdateInfo = (newTips: APITimelineTips, shouldAnimate: Bool)
        interactor
            .didCompleteTip
            .asDriver()
            .withLatestFrom(todayTimelineTips.asDriver(), resultSelector: { (newTips: $0, currentTips: $1) })
            .map({ combinedTips -> TipsUpdateInfo in
                let currentDailyTipFlowTips = [combinedTips.currentTips?.dailyTip].compactMap { $0 } + (combinedTips.currentTips?.extraTips ?? [])
                let newDailyTipFlowTips = [combinedTips.newTips.dailyTip] + combinedTips.newTips.extraTips.dropLast()
                guard currentDailyTipFlowTips.count == newDailyTipFlowTips.count else {
                    return TipsUpdateInfo(newTips: combinedTips.newTips, shouldAnimate: false)
                }
                if currentDailyTipFlowTips.last?.isCompleted == false
                    && newDailyTipFlowTips.last?.isCompleted == true {
                    return TipsUpdateInfo(newTips: combinedTips.newTips, shouldAnimate: true)
                } else {
                    return TipsUpdateInfo(newTips: combinedTips.newTips, shouldAnimate: false)
                }
            })
            .do { [unowned self] tipsUpdateInfo in
                self.todayTimelineTips.accept(tipsUpdateInfo.newTips)
                self.interactor.trackDailyTipCompletion()
            }
            .flatMap { [unowned self] tipsUpdateInfo in
                return self.configureCells(tips: tipsUpdateInfo.newTips, selectedDate: TipsTimelineViewItem.today).map { cellItems in
                    guard tipsUpdateInfo.shouldAnimate else {
                        return cellItems
                    }
                    if let lastCompletedCell = cellItems
                        .filter({ type in
                            switch type {
                            case .tip:
                                return true
                            default:
                                return false
                            }
                        })
                        .filter({ $0.tipItem?.isCompleted.value == true })
                        .last {
                            let lastCompletedTipItem = lastCompletedCell.tipItem
                            lastCompletedTipItem?.style.accept(.expanded)
                            lastCompletedTipItem?.isCompleted.accept(false)
                            self.timelineViewItem.value.selectedDayViewItem.value?.isCompleted.accept(true)
                            self.scheduleAnimateTipCompletion.accept(cellItems.firstIndex(where: { $0.tipItem?.id.value == lastCompletedTipItem?.id.value }) ?? Int.min )
                        }
                    return cellItems
                }
            }
            .drive(sectionItems)
            .disposed(by: disposeBag)
    }

    func loadTips(_ date: Date) -> Driver<[Coach.CellType]> {
        return Driver.just(date)
            .flatMap { [unowned self] date -> Driver<[Coach.CellType]> in
                if date <= Date.dateAtTheEndOfToday {
                    return Observable<Date>.just(date)
                        .do(onNext: { [weak self] _ in
                            self?.areContentViewsHidden.onNext(true)
                            if !isLoaderShown.value {
                                self?.view.showLoading()
                            }
                        })
                        .flatMap { [weak self] date -> Observable<APITimelineTips> in
                            guard let self = self else { return Observable.empty() }
                            return self.interactor
                                .getTimelineTips(date: date)
                                .asObservable()
                                .do { timelineTips in
                                    if date.isSameDayAs(Date()) {
                                        todayTimelineTips.accept(timelineTips)
                                    }
                                }
                        }
                        .do(onNext: { [weak self] _ in
                            self?.areContentViewsHidden.onNext(false)
                            self?.isLoaderShown.accept(false)
                            self?.shouldFadeTipsView.onNext(())
                        })
                        .handleHideLoading(with: view)
                        .retry(when: { error in
                            return error.flatMap { [weak self] error -> Observable<Void> in
                                guard let self = self else { return Observable.empty() }
                                if let error = error as? NetworkError {
                                    switch error {
                                    case let .general(afError):
                                        if afError.responseCode == 404 {
                                            let item = InfoViewItem.pastDateNoActivity(date: date)
                                            self.errorOverlay.onNext(item)
                                            return Observable.empty()
                                        }
                                    default:
                                        break
                                    }
                                }
                                let item = InfoViewItem.somethingWentWrongTryAgainItem
                                self.errorOverlay.onNext(item)
                                self.isLoaderShown.accept(false)
                                return item.buttonAction.asObservable()
                            }
                        })
                        .asDriverOnErrorComplete()
                        .flatMap { [weak self] tips -> Driver<[Coach.CellType]> in
                            guard let self = self else { return Driver.empty() }
                            return self.configureCells(tips: tips, selectedDate: date)
                        }
                } else if date.isSameDayAsTomorrow {
                    return Driver<[Coach.CellType]>
                        .just(self.generateTomorrowSectionItems(date: date))
                } else {
                    return Driver<[Coach.CellType]>
                        .just([])
                }
            }
    }

    private func saveTip(withId id: String) -> Single<Void> {
        interactor
            .saveTip(withID: id)
            .handleLoading(with: self.view)
    }

    private func unsaveTip(withId id: String) -> Single<Void> {
        interactor
            .unsaveTip(withID: id)
            .handleLoading(with: self.view)
    }
}

// MARK: - Helpers -

extension CoachPresenter {

    func reloadData() {
        refetchTipsTrigger.onNext(())
    }

    func configureCells(tips: APITimelineTips, selectedDate: Date) -> Driver<[Coach.CellType]> {
        interactor
            .userDisplayName
            .withUnretained(self)
            .map { weakSelf, userDisplayName in
                let completedSessionDate = weakSelf.interactor.completedDailySessionTimestamp()
                return weakSelf.configureViewCellTypes(
                    timelineTips: tips,
                    selectedDate: selectedDate,
                    isDailySessionClosed: completedSessionDate?.isSameDayAs(selectedDate) ?? false,
                    userDisplayName: userDisplayName
                )
            }
            .asDriver()
    }

}

// MARK: - Display logic -

extension CoachPresenter {

    func createTodayHeadlineItem(userDisplayName: String?, isSessionOpen: Bool) -> HeadlineViewItem {
        let emojis: [String] = ["🌞", "💫", "📚️", "✨", "💪", "🌟", "🚀", "❤️", "🙌", "💡"]
        let date = Date()
        let emoji = emojis[abs(date.hashValue % emojis.count)]
        let timeIndex: Int = {
            if date.hour < 3 {
                return 2
            } else if date.hour < 12 {
                return 0
            } else if date.hour < 18 {
                return 1
            } else {
                return 2
            }
        }()

        let sessionClosedOptions = userDisplayName.isBlank ? L10n.headlineAwesomeAnon : L10n.headlineAwesome(userDisplayName!)
        var headlineMessage: String
        if let userFirstName = userDisplayName {
            let options = [L10n.headlineMorningEmoji(userFirstName, emoji),
                           L10n.headlineHowdyEmoji(userFirstName, emoji),
                           L10n.headlineHeyEmoji(userFirstName, emoji)]
            headlineMessage = isSessionOpen ? options[timeIndex] : sessionClosedOptions
        } else {
            let options = [L10n.headlineMorningAnon,
                           L10n.headlineHowdyAnon,
                           L10n.headlineHiThereAnon]
            headlineMessage = options[timeIndex]
        }
        let dateString = WeekDayMonthDayLongDateFormatter.instance.string(for: date)
        return HeadlineViewItem(smallTitleString: dateString, mainTitleString: headlineMessage)
    }

    func generateTomorrowSectionItems(date: Date) -> [Coach.CellType] {
        let dateString = WeekDayMonthDayLongDateFormatter.instance.string(for: date)
        let headlineViewItem = HeadlineViewItem(smallTitleString: dateString, mainTitleString: L10n.nextDayLargeTitle)
        let lockedTip = TipLockedCellItem.brown
        let lockedTip2 = TipLockedCellItem.blue
        let lockedTip3 = TipLockedCellItem.green
        return [Coach.CellType.headline(headlineViewItem),
                Coach.CellType.lockedTip(lockedTip),
                Coach.CellType.separator,
                Coach.CellType.lockedTip(lockedTip2),
                Coach.CellType.separator,
                Coach.CellType.lockedTip(lockedTip3)]
    }

    func generateLockedSectionItems(completedTipsCount: Int) -> [Coach.CellType] {
        if completedTipsCount > 0 {
            return [Coach.CellType.separator,
                    Coach.CellType.lockedTip(TipLockedCellItem.blue)]
        } else {
            let lockedTip1 = TipLockedCellItem.blue
            let lockedTip2 = TipLockedCellItem.green
            return [Coach.CellType.separator,
                    Coach.CellType.lockedTip(lockedTip1),
                    Coach.CellType.separator,
                    Coach.CellType.lockedTip(lockedTip2)]
        }
    }

    func generateSavedForTomorrowItems() -> [Coach.CellType] {
        return [Coach.CellType.headerTitle(SimpleLabelCellItem(title: L10n.savedForTomorrow)),
                Coach.CellType.lockedTip(.green),
                Coach.CellType.lockedTip(.yellow)]
    }

}

// MARK: - Configure items -

extension CoachPresenter {

    func configureTapForTipItems(_ allTipItems: [TipCardViewItem]) {
        allTipItems.forEach { item in
            item.tapAction
                .withLatestFrom(todayTimelineTips) { id, todayTimelineTips -> (String, Tip.Source) in
                    let isDailyTip = todayTimelineTips?.dailyTip.id == id || todayTimelineTips?.extraTips.contains(where: { $0.id == id }) ?? false
                    let source: Tip.Source = isDailyTip ? .dailyTip : .other
                    return (id, source)
                }
                .subscribe(onNext: { [weak self] (id, source) in
                    guard let self = self else { return }
                    self.wireframe.navigateToTipPreview(tipId: id, source: source)
                })
                .disposed(by: disposeBag)

            item.tapAction
                .withLatestFrom(todayTimelineTips) { [unowned interactor] id, todayTimelineTips in
                    if todayTimelineTips?.dailyTip.id == id {
                        interactor.trackDailyTipTap()
                    }
                }
                .subscribe()
                .disposed(by: disposeBag)
        }
    }

    func configureTodayCellTypes(timelineTips: APITimelineTips, isDailySessionClosed: Bool, userDisplayName: String?) -> [Coach.CellType] {
        let completedItems = completedTipsItems(timelineTips: timelineTips)
        let completedTipsCount = completedItems.count
        let completedTips = completedItems.map { Coach.CellType.tip($0) }
        let dailyTipItem = dailyTip(timelineTips: timelineTips)
        let nextTips = nextTips(timelineTips: timelineTips)

        var allTipItems = completedItems + [dailyTipItem] + nextTips

        let headlineItem = createTodayHeadlineItem(userDisplayName: userDisplayName, isSessionOpen: !isDailySessionClosed)
        let headlineCell = Coach.CellType.headline(headlineItem)
        var allCells: [Coach.CellType] = [headlineCell]

        currentTipItem.accept(nil)
        let isDailySessionRunning = !isDailySessionClosed
        if isDailySessionRunning {
            let completedTipsWithSeparators = Array(completedTips.map { [$0] }.joined(separator: [Coach.CellType.separator]))
            allCells.append(contentsOf: completedTipsWithSeparators)

            if let currentTip = currentTip(timelineTips: timelineTips, completedTipsCount: completedTipsCount) {
                if completedTipsCount > 0 { allCells.append(Coach.CellType.separator) }
                currentTipItem.accept(currentTip)
                allTipItems.append(currentTip)
                allCells.append(Coach.CellType.tip(currentTip))
                allCells.append(Coach.CellType.getDifferentTip(DifferentTipCellItem(referencingTipItem: currentTip)))
            } else if let nextTip = nextTips.first, let unlockNewTipItem = createUnlockNewTipItem(completedTipsCount: completedTipsCount, lockedTipViewItem: nextTip) {
                allCells.append(Coach.CellType.separator)
                allCells.append(Coach.CellType.unlockNewTip(unlockNewTipItem))
            }
            allCells.append(contentsOf: generateLockedSectionItems(completedTipsCount: completedTipsCount))
        } else {
            allCells.append(contentsOf: completedTips)
            allCells.append(contentsOf: generateSavedForTomorrowItems())
            allCells.append(Coach.CellType.exploreNote(createExploreItem()))
        }

        let exploreTipItems = exploreTips(timelineTips: timelineTips)
        let exploreTips = exploreTipItems.map { Coach.CellType.exploreTip($0) }
        if !exploreTips.isEmpty {
            allCells.append(Coach.CellType.headerTitle(SimpleLabelCellItem(title: L10n.tipsYouFoundInExplore)))
            allCells.append(contentsOf: exploreTips)
        }

        configureTapForTipItems(allTipItems + exploreTipItems)
        return allCells
    }

    func configurePreviousDayCellTypes(timelineTips: APITimelineTips, selectedDate: Date) -> [Coach.CellType] {
        let smallTitle = WeekDayMonthDayLongDateFormatter.instance.string(for: selectedDate)
        let allTips = [timelineTips.dailyTip] + timelineTips.extraTips
        let largeTitle = allTips.filter { $0.isCompleted }.isEmpty ?  L10n.youWereLearningBeyondSampleCodeThisDay : L10n.diveIntoTipsYouLearnedAlready
        let headlineItem = HeadlineViewItem(smallTitleString: smallTitle, mainTitleString: largeTitle)
        let headlineCell = Coach.CellType.headline(headlineItem)

        var allCells = [headlineCell]
        let completedTipItems = completedTipsItems(timelineTips: timelineTips)
        let completedTips = completedTipItems.map { Coach.CellType.tip($0) }
        allCells.append(contentsOf: completedTips)

        let exploreTips = exploreTips(timelineTips: timelineTips).map { Coach.CellType.exploreTip($0) }
        if !exploreTips.isEmpty {
            allCells.append(Coach.CellType.headerTitle(SimpleLabelCellItem(title: L10n.tipsYouFoundInExplore)))
            allCells.append(contentsOf: exploreTips)
        }
        configureTapForTipItems(completedTipItems)
        return allCells
    }

    func configureViewCellTypes(
        timelineTips: APITimelineTips,
        selectedDate: Date,
        isDailySessionClosed: Bool,
        userDisplayName: String?
    ) -> [Coach.CellType] {
        if selectedDate.isSameDayAsToday {
            return configureTodayCellTypes(timelineTips: timelineTips, isDailySessionClosed: isDailySessionClosed, userDisplayName: userDisplayName)
        } else {
            return configurePreviousDayCellTypes(timelineTips: timelineTips, selectedDate: selectedDate)
        }
    }

    func completedTipsItems(timelineTips: APITimelineTips) -> [TipCardViewItem] {
        let possibleTips = [timelineTips.dailyTip] + timelineTips.extraTips
        let completedTips = possibleTips.filter { $0.isCompleted }
        return completedTips.map {
            self.setupTipSaving(
                item: TipCardViewItem(apiTip: $0, style: .compact)
            )
        }
    }

    func dailyTip(timelineTips: APITimelineTips) -> TipCardViewItem {
        setupTipSaving(
            item: TipCardViewItem(
                apiTip: timelineTips.dailyTip,
                style: timelineTips.dailyTip.isCompleted ? .compact : .expanded
            )
        )
    }

    func currentTip(timelineTips: APITimelineTips, completedTipsCount: Int) -> TipCardViewItem? {
        let isSessionInLockedState = { () -> Bool in
            if completedTipsCount == 2 || completedTipsCount == 5 {
                if let lastExtraTip = timelineTips.extraTips.last {
                    return !(unlockedTipIDs.contains(lastExtraTip.id))
                }
            }
            return false
        }()

        if let currentTip = !timelineTips.dailyTip.isCompleted ? timelineTips.dailyTip : timelineTips.extraTips.first(where: { !$0.isCompleted && !isSessionInLockedState }) {
            return self.setupTipSaving(
                item: TipCardViewItem(apiTip: currentTip, style: .expanded)
            )
        } else {
            return nil
        }
    }

    func nextTips(timelineTips: APITimelineTips) -> [TipCardViewItem] {
        let completedTips = timelineTips.extraTips.filter { !$0.isCompleted && $0.isLocked == true }
        return completedTips.map {
            self.setupTipSaving(
                item: TipCardViewItem(apiTip: $0, style: .expanded)
            )
        }
    }

    func exploreTips(timelineTips: APITimelineTips) -> [TipCardViewItem] {
        timelineTips.tipsFromExplore.map {
            self.setupTipSaving(
                item: TipCardViewItem(apiTip: $0, style: .compact)
            )
        }
    }

    func createExploreItem() -> ExploreNoteCellItem {
        let exploreItem = ExploreNoteCellItem()

        exploreItem.closeAction
            .withLatestFrom(sectionItems)
            .map { cellTypes -> [Coach.CellType] in
                cellTypes.filter { cellType in
                    switch cellType {
                    case .exploreNote:
                        return false
                    default:
                        return true
                    }
                }
            }
            .bind(to: sectionItems)
            .disposed(by: exploreItem.disposeBag)

        exploreItem.goToExploreAction
            .do(onNext: { [unowned interactor] _ in
                interactor.trackGoOnExploreTap()
            })
            .subscribe(onNext: { [unowned self] in
                self.wireframe.navigateToExplore()
            })
            .disposed(by: exploreItem.disposeBag)

        return exploreItem
    }

    func createUnlockNewTipItem(completedTipsCount: Int, lockedTipViewItem: TipCardViewItem) -> UnlockTipViewItem? {
        let item: UnlockTipViewItem
        switch completedTipsCount {
        case 2:
            item = UnlockTipViewItem.afterTwoTips(lockedTipViewItem: lockedTipViewItem)
        case 5:
            item = UnlockTipViewItem.afterFiveTips(lockedTipViewItem: lockedTipViewItem)
        default:
            return nil
        }

        item.closeAction
            .flatMap { _ in
                return self.interactor.saveCompletedDailySessionTimestamp(date: Date())
            }
            .mapTo(lockedTipViewItem)
            .withLatestFrom(todayTimelineTips)
            .bind(to: todayTimelineTips)
            .disposed(by: item.disposeBag)

        item.closeAction
            .delay(.milliseconds(500), scheduler: MainScheduler.instance)
            .bind(to: localReloadTrigger)
            .disposed(by: disposeBag)

        item.closeAction
            .withLatestFrom(interactor.userDisplayName)
            .bind(to: animateCallItADay)
            .disposed(by: item.disposeBag)

        item.closeAction
            .subscribe { [unowned interactor] _ in
                interactor.trackCallItADayTap()
            }
            .disposed(by: item.disposeBag)

        item.nextTipAction
            .mapTo(item.lockedTipViewItem)
            .bind(to: animateUnlockNextTip)
            .disposed(by: item.disposeBag)

        item.nextTipAction
            .withLatestFrom(item.lockedTipViewItem.id)
            .flatMap { [unowned self] id in
                self.interactor.unlockTip(withID: id)
            }
            .subscribe()
            .disposed(by: disposeBag)

        item.nextTipAction
            .withLatestFrom(item.lockedTipViewItem.id)
            .do { [unowned self] tipID in
                self.unlockedTipIDs.append(tipID)
            }
            .mapTo(())
            .asDriver(onErrorJustReturn: ())
            .drive(localReloadTrigger)
            .disposed(by: item.disposeBag)

        let nextTipCompletedCount = item.nextTipAction
            .withLatestFrom(todayTimelineTips)
            .compactMap { $0 }
            .map { ([$0.dailyTip] + $0.extraTips).filter { $0.isCompleted }.count }

        item.nextTipAction
            .mapTo(item.lockedTipViewItem.id.value)
            .withLatestFrom(nextTipCompletedCount) { [unowned interactor] tipCardItemID, completedCount in
                interactor.trackKeepGoingTap(count: completedCount, tipID: tipCardItemID)
            }
            .subscribe()
            .disposed(by: item.disposeBag)

        return item
    }

    private func setupTipSaving(item: TipCardViewItem) -> TipCardViewItem {
        item.saveAction
            .withLatestFrom(Observable.combineLatest(item.id, item.isSaved))
            .withUnretained(self, resultSelector: { ($0, $1.0, $1.1) })
            .flatMap { weakSelf, tipId, isSaved -> Single<Bool> in
                if isSaved {
                    return weakSelf.unsaveTip(withId: tipId)
                        .mapTo(!isSaved)
                } else {
                    return weakSelf.saveTip(withId: tipId)
                        .mapTo(!isSaved)
                }
            }
            .subscribe(
                onNext: { isSaved in
                    let toast: ToastView = isSaved ? .addedToSavedTip : .removedSavedTip
                    self.view.show(toast: toast)
                },
                onError: { err in
                    print(err)
                    self.view.show(toast: .failedTaskTryAgain)
                }
            )
            .disposed(by: disposeBag)

        item.id
            .flatMapLatest { [unowned interactor] tipId in
                interactor.isTipSaved(withID: tipId)
            }
            .bind(to: item.isSaved)
            .disposed(by: disposeBag)

        return item
    }

    func handleDailyTip(trigger: Signal<Void>) {
        let tips = todayTimelineTips
            .asSignal(onErrorSignalWith: .empty())
            .compactMap()
            .take(1)
        Signal.combineLatest(tips, trigger, resultSelector: { _, _ in 0 })
            .withLatestFrom(todayTimelineTips.asSignal(onErrorSignalWith: .empty()))
            .compactMap()
            .map { $0.dailyTip.id }
            .do(onNext: { [weak timelineViewItem] _ in
                timelineViewItem?.value.selectedDate.accept(TipsTimelineViewItem.today)
            })
            .emit(onNext: { [weak wireframe] id in
                wireframe?.navigateToTipPreview(tipId: id, source: .dailyTip)
            })
            .disposed(by: disposeBag)
    }

}
