import UIKit
import RxSwift
import RxCocoa
import RxDataSources
import Lottie
import SkeletonView

final class CoachViewController: UIViewController {

    // UI

    private lazy var timelineView = setupTimelineView()
    private lazy var tipsTableView = setupTipsTableView()
    private lazy var infoOverlayView = InfoView(frame: .zero)
    private lazy var loaderView = CoachTabLoaderView(item: CoachTabLoaderViewItem.today)

    private lazy var backToTodayContainerView = setupBackToTodayView()
    private lazy var backToTodayButton = PrimaryButton(item: PrimaryButtonItem(title: L10n.backToToday, icon: nil))

    private var backToTodayBottomConstraint: NSLayoutConstraint!
    private var tipsTableViewBottomAnchor: NSLayoutConstraint!

    private static let tipsTableViewDefaultContentInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 110.0, right: 0.0)

    // MARK: - Public properties -

    var presenter: CoachPresenterInterface!

    // MARK: - Private properties -

    private let isTipCompletionAnimationScheduled = BehaviorSubject<Bool>(value: false)
    private let completeTipAnimationStarted = PublishRelay<Void>()

    private let disposeBag = DisposeBag()

    // MARK: - Lifecycle -

    override func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        setupLayout()
        configureView()
    }

    // MARK: - Logic helpers

    var dataSource: RxTableViewSectionedReloadDataSource<Coach.TipsSectionType> {
        RxTableViewSectionedReloadDataSource<Coach.TipsSectionType> { _, tableView, indexPath, item in
            switch item {
            case let .headline(item):
                let cell = tableView.dequeueReusableCell(for: indexPath, cellType: HeadlineCell.self)
                cell.configure(with: item)
                return cell
            case let .tip(item), let .exploreTip(item):
                let cell = tableView.dequeueReusableCell(for: indexPath, cellType: TipCardCell.self)
                cell.configure(with: item)
                return cell
            case let .getDifferentTip(item):
                let differentTipCell = tableView.dequeueReusableCell(for: indexPath, cellType: DifferentTipCell.self)
                differentTipCell.configure(with: item)
                return differentTipCell
            case let .lockedTip(item):
                let cell = tableView.dequeueReusableCell(for: indexPath, cellType: TipLockedCell.self)
                cell.configure(with: item)
                return cell
            case let .exploreNote(item):
                let cell = tableView.dequeueReusableCell(for: indexPath, cellType: ExploreNoteCell.self)
                cell.configure(with: item)
                return cell
            case let .unlockNewTip(item):
                let cell = tableView.dequeueReusableCell(for: indexPath, cellType: UnlockTipCell.self)
                cell.configure(with: item)
                return cell
            case let .headerTitle(item):
                let cell = tableView.dequeueReusableCell(for: indexPath, cellType: SimpleLabelCell.self)
                cell.configure(with: item)
                return cell
            case .separator:
                return tableView.dequeueReusableCell(for: indexPath, cellType: CoachSeparatorCell.self)
            }
        }
    }
}

// MARK: - Extensions -

extension CoachViewController: CoachViewInterface {
    func show(toast: ToastView) {
        toast.launch()
    }
}

private extension CoachViewController {
    
    func configureView() {
        let output = Coach.ViewOutput(backToTodayAction: backToTodayButton.rx.tap.asSignal(),
                                      chatAction: navigationItem.rightBarButtonItem!.rx.tap.asSignal(),
                                      tipCompletedAnimationStarted: completeTipAnimationStarted.asSignal())
        let input = presenter.configure(with: output)
        input.timelineItem
            .drive(onNext: { item in
                self.timelineView.configure(with: item)
            })
            .disposed(by: disposeBag)

        input.sectionItems
            .drive(tipsTableView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)

        input.selectedDate
            .mapTo(())
            .asObservable()
            .concat(input.sectionItems.asObservable().mapTo(()))
            .asDriverOnErrorComplete()
            .mapTo(CGPoint.zero)
            .drive(tipsTableView.rx.contentOffset)
            .disposed(by: disposeBag)

        Driver.combineLatest(input.isBackToTodayShown, input.setContentViewsHidden) { isbackToTodayShown, areContentViewsHidden in
                return isbackToTodayShown && !areContentViewsHidden
            }
            .map({ $0 ? 0 : 200.0 })
            .drive(backToTodayBottomConstraint.rx.constant)
            .disposed(by: disposeBag)

        input.infoOverlayItem
            .compactMap()
            .drive(infoOverlayView.rx.item)
            .disposed(by: disposeBag)

        input.infoOverlayItem
            .map { $0 == nil }
            .drive(infoOverlayView.rx.isHidden)
            .disposed(by: disposeBag)

        input.infoOverlayItem
            .map { $0 != nil }
            .drive(tipsTableView.rx.isHidden)
            .disposed(by: disposeBag)

        input.isTipsScrollEnabled
            .drive(tipsTableView.rx.isScrollEnabled)
            .disposed(by: disposeBag)

        input.animateUnlockNextTip
            .do { [weak self] item in
                self?.animateUnlockNextTip(lockedTipCardViewItem: item)
            }
            .drive()
            .disposed(by: disposeBag)

        input.animateTipCompletion
            .map { $0 > 0 }
            .drive(isTipCompletionAnimationScheduled)
            .disposed(by: disposeBag)

        input.animateTipCompletion
            .delay(.milliseconds(10))
            .drive { [unowned self, unowned tipsTableView] row in
                tipsTableView.contentInset = UIEdgeInsets(top: Self.tipsTableViewDefaultContentInsets.top, left: Self.tipsTableViewDefaultContentInsets.left, bottom: tipsTableView.frame.size.height + Self.tipsTableViewDefaultContentInsets.bottom, right: Self.tipsTableViewDefaultContentInsets.right)
                tipsTableViewBottomAnchor.constant = tipsTableView.frame.size.height
                tipsTableView.superview?.setNeedsLayout()
                tipsTableView.superview?.layoutIfNeeded()

                let indexPath = IndexPath(row: row, section: 0)
                tipsTableView.scrollToRow(at: indexPath, at: .middle, animated: false)
            }
            .disposed(by: disposeBag)

        input.animateCallItADay
            .do { [weak self] userName in
                self?.animateCallItADay(userName: userName)
            }
            .drive()
            .disposed(by: disposeBag)

        input.isLoaderShown
            .map { !$0 }
            .drive(loaderView.rx.isHidden)
            .disposed(by: disposeBag)

        input.isLoaderShown
            .filter { $0 }
            .do(onNext: { [unowned loaderView] _ in
                loaderView.showAnimatedGradientSkeleton(usingGradient: SkeletonGradient(baseColor: .sampleCodeDarkGray1), transition: .none)
            })
            .drive()
            .disposed(by: disposeBag)

        rx.viewDidAppear
            .withLatestFrom(isTipCompletionAnimationScheduled.asSignalOnErrorComplete())
            .filter { $0 }
            .do(onNext: { [unowned self] _ in
                self.isTipCompletionAnimationScheduled.onNext(false)
            })
            .emit { [unowned self] _ in
                self.animateCompleteTip()
            }
            .disposed(by: disposeBag)
    }

    func setupView() {
        tipsTableView.backgroundColor = .sampleCodeBlack

        // Navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "logotype-default"), style: .plain, target: self, action: #selector(leftBarButonItemAction))
        navigationItem.leftBarButtonItem?.isEnabled = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "icon-chat"), style: .plain, target: self, action: #selector(rightBarButonItemAction))

        backToTodayContainerView.addSubview(backToTodayButton)
        backToTodayButton.pinToSuperview(insets: UIEdgeInsets(top: 24.0, left: 16.0, bottom: -24.0, right: -16.0))

        view.addSubview(tipsTableView)
        view.addSubview(backToTodayContainerView)
        view.addSubview(infoOverlayView)
        view.addSubview(timelineView)
        view.addSubview(loaderView)
    }

    func setupLayout() {
        NSLayoutConstraint.activate([
            timelineView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            timelineView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            timelineView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            timelineView.heightAnchor.constraint(equalToConstant: 56.0)
        ])

        tipsTableViewBottomAnchor = tipsTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            tipsTableView.topAnchor.constraint(equalTo: timelineView.bottomAnchor),
            tipsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tipsTableView.leadingAnchor.constraint(equalTo: timelineView.leadingAnchor),
            tipsTableViewBottomAnchor
        ])

        backToTodayBottomConstraint = backToTodayContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate([
            backToTodayBottomConstraint!,
            backToTodayContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backToTodayContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backToTodayContainerView.heightAnchor.constraint(equalToConstant: 98.0)
        ])

        NSLayoutConstraint.activate([
            infoOverlayView.topAnchor.constraint(equalTo: timelineView.bottomAnchor),
            infoOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoOverlayView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        loaderView.pin(to: tipsTableView)
    }

}

// MARK: - Actions

private extension CoachViewController {

    @objc func leftBarButonItemAction() {}

    @objc func rightBarButonItemAction() {}

}

// MARK: - UI Elements

private extension CoachViewController {

    func setupTimelineView() -> TipsTimelineView {
        let timelineView = TipsTimelineView(frame: .zero)
        timelineView.translatesAutoresizingMaskIntoConstraints = false
        return timelineView
    }

    func setupTipsTableView() -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 150.0
        tableView.contentInset = Self.tipsTableViewDefaultContentInsets
        tableView.backgroundView = nil
        tableView.backgroundColor = nil
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.automaticallyAdjustsScrollIndicatorInsets = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.showsVerticalScrollIndicator = false
        tableView.register(cellType: TipCardCell.self)
        tableView.register(cellType: DifferentTipCell.self)
        tableView.register(cellType: CoachSeparatorCell.self)
        tableView.register(cellType: TipLockedCell.self)
        tableView.register(cellType: HeadlineCell.self)
        tableView.register(cellType: ExploreNoteCell.self)
        tableView.register(cellType: UnlockTipCell.self)
        tableView.register(cellType: SimpleLabelCell.self)
        return tableView
    }

    func setupBackToTodayView() -> UIView {
        let gradientView = GradientView(gradient: Gradient(type: .bottomTop, colors: [.sampleCodeDeepDarkGray, .clear]))
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        return gradientView
    }

}

// MARK: - Animations -

private extension CoachViewController {

    struct AnimationSetupInfo {
        let animationContainerView: UIView
        let topSliceSnapshotView: UIView
        let bottomSliceSnapshotView: UIView
    }

    func animateCallItADay(userName: String?) {
        let animationContainerView = UIView(frame: .zero)
        animationContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animationContainerView)
        animationContainerView.backgroundColor = .sampleCodeBlack
        animationContainerView.pin(to: tipsTableView)
        animationContainerView.alpha = 0.0

        let progressLabel = Label(item: LabelItem(text: L10n.savingYourProgress, fontStyle: .body, color: .sampleCodeWhite, textAlignment: .center))
        let loaderView = AnimationView(name: "loader")
        loaderView.loopMode = .loop
        loaderView.play()
        let firstViewsSet = [loaderView, progressLabel]
        firstViewsSet.forEach({ $0.translatesAutoresizingMaskIntoConstraints = false })
        animationContainerView.addSubview(progressLabel)
        animationContainerView.addSubview(loaderView)
        NSLayoutConstraint.activate([
            progressLabel.centerXAnchor.constraint(equalTo: animationContainerView.centerXAnchor),
            progressLabel.centerYAnchor.constraint(equalTo: animationContainerView.centerYAnchor, constant: -50.0),
            loaderView.widthAnchor.constraint(equalToConstant: 100.0),
            loaderView.heightAnchor.constraint(equalTo: loaderView.widthAnchor),
            loaderView.centerXAnchor.constraint(equalTo: animationContainerView.centerXAnchor),
            loaderView.bottomAnchor.constraint(equalTo: progressLabel.topAnchor)
        ])

        let progressSavedLabel = Label(item: LabelItem(text: L10n.progressSaved, fontStyle: .body, color: .sampleCodeWhite, textAlignment: .center))
        let checkmarkView = UIImageView(image: #imageLiteral(resourceName: "checkmark-extra-large"))
        checkmarkView.contentMode = .center

        let secondViewsSet = [progressSavedLabel, checkmarkView]
        secondViewsSet.forEach({ $0.translatesAutoresizingMaskIntoConstraints = false })
        secondViewsSet.forEach({ $0.alpha = 0.0 })
        animationContainerView.addSubview(progressSavedLabel)
        animationContainerView.addSubview(checkmarkView)
        progressSavedLabel.pin(to: progressLabel)
        checkmarkView.pin(to: loaderView)

        let endingMessage = L10n.callItDayMessage(userName ?? " ").replacingOccurrences(of: "  ", with: "")
        let endingMessageLabel = Label(item: LabelItem(text: endingMessage, fontStyle: .title1, color: .sampleCodeWhite, numberOfLines: 0, textAlignment: .center))
        let emojiLabel = Label(item: LabelItem(text: "🙌", fontStyle: .emoji, textAlignment: .center))

        [endingMessageLabel, emojiLabel].forEach({ $0.translatesAutoresizingMaskIntoConstraints = false })
        [endingMessageLabel, emojiLabel].forEach({ $0.alpha = 0.0 })
        animationContainerView.addSubview(endingMessageLabel)
        animationContainerView.addSubview(emojiLabel)
        NSLayoutConstraint.activate([
            endingMessageLabel.centerXAnchor.constraint(equalTo: animationContainerView.centerXAnchor),
            endingMessageLabel.centerYAnchor.constraint(equalTo: animationContainerView.centerYAnchor, constant: -50.0),
            endingMessageLabel.widthAnchor.constraint(equalToConstant: 319),
            emojiLabel.bottomAnchor.constraint(equalTo: endingMessageLabel.topAnchor, constant: -12.0),
            emojiLabel.centerXAnchor.constraint(equalTo: animationContainerView.centerXAnchor)
        ])

        let endingMessageCurtainView = UIView(frame: .zero)
        endingMessageCurtainView.translatesAutoresizingMaskIntoConstraints = false
        animationContainerView.addSubview(endingMessageCurtainView)
        endingMessageCurtainView.backgroundColor = animationContainerView.backgroundColor
        endingMessageCurtainView.pin(to: endingMessageLabel)
        endingMessageCurtainView.alpha = 0.0

        view.setNeedsLayout()
        view.layoutIfNeeded()

        let fadeInAnimator = UIViewPropertyAnimator(duration: 0.33, curve: .easeOut) {
            animationContainerView.alpha = 1.0
        }
        let progressCompletedAnimator = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
            firstViewsSet.forEach({ $0.alpha = 0.0 })
            secondViewsSet.forEach({ $0.alpha = 1.0 })
        }
        fadeInAnimator.addCompletion { _ in
            progressCompletedAnimator.startAnimation(afterDelay: 1.75)
        }
        let fadeOutSecondSetAnimator = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) {
            secondViewsSet.forEach({ $0.alpha = 0.0 })
        }
        progressCompletedAnimator.addCompletion { _ in
            fadeOutSecondSetAnimator.startAnimation(afterDelay: 1.0)
        }
        let showEndingMessageAnimator = UIViewPropertyAnimator(duration: 0.17, curve: .easeInOut) {
            endingMessageCurtainView.transform = CGAffineTransform(translationX: endingMessageCurtainView.frame.size.width, y: 0.0)
        }
        fadeOutSecondSetAnimator.addCompletion { _ in
            endingMessageCurtainView.alpha = 1.0
            endingMessageLabel.alpha = 1.0
            showEndingMessageAnimator.startAnimation(afterDelay: 0.1)
        }
        let showEmojiAnimator = UIViewPropertyAnimator(duration: 0.17, curve: .easeInOut) {
            emojiLabel.alpha = 1.0
        }
        showEndingMessageAnimator.addCompletion { _ in
            showEmojiAnimator.startAnimation(afterDelay: 0.15)
        }
        let fadeOutAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) {
            animationContainerView.alpha = 0.0
        }
        showEmojiAnimator.addCompletion { _ in
            fadeOutAnimator.startAnimation(afterDelay: 2.5)
        }
        fadeOutAnimator.addCompletion { _ in
            animationContainerView.removeFromSuperview()
        }
        fadeInAnimator.startAnimation()
    }

    func animateCompleteTip() {
        view.setNeedsDisplay()
        guard let currentTipCell = tipsTableView.ySortedSubviews.compactMap({ $0 as? TipCardCell }).filter({ $0.contained.style == .expanded }).first else {
            return
        }
        guard let tableViewTopSliceView = tipsTableView.getDrawnHierarchy(), let tableViewBottomSliceView = tipsTableView.getDrawnHierarchy() else {
            return
        }
        let animationContainerView = UIView(frame: .zero)
        [animationContainerView, tableViewTopSliceView, tableViewBottomSliceView].forEach({ $0.translatesAutoresizingMaskIntoConstraints = false })
        animationContainerView.clipsToBounds = true
        animationContainerView.addSubview(tableViewBottomSliceView)
        tableViewBottomSliceView.contentMode = .bottom
        NSLayoutConstraint.activate([
            tableViewBottomSliceView.topAnchor.constraint(equalTo: animationContainerView.topAnchor, constant: currentTipCell.frame.origin.y + currentTipCell.frame.size.height - tipsTableView.contentOffset.y),
            tableViewBottomSliceView.leadingAnchor.constraint(equalTo: animationContainerView.leadingAnchor),
            tableViewBottomSliceView.trailingAnchor.constraint(equalTo: animationContainerView.trailingAnchor),
            tableViewBottomSliceView.bottomAnchor.constraint(equalTo: animationContainerView.bottomAnchor)
        ])

        animationContainerView.addSubview(tableViewTopSliceView)
        NSLayoutConstraint.activate([
            tableViewTopSliceView.topAnchor.constraint(equalTo: animationContainerView.topAnchor),
            tableViewTopSliceView.leadingAnchor.constraint(equalTo: animationContainerView.leadingAnchor),
            tableViewTopSliceView.trailingAnchor.constraint(equalTo: animationContainerView.trailingAnchor),
            tableViewTopSliceView.heightAnchor.constraint(equalToConstant: max(0.0, currentTipCell.frame.origin.y - tipsTableView.contentOffset.y))
        ])

        let middleView = UIView(frame: .zero)
        middleView.translatesAutoresizingMaskIntoConstraints = false
        animationContainerView.addSubview(middleView)
        NSLayoutConstraint.activate([
            middleView.leadingAnchor.constraint(equalTo: animationContainerView.leadingAnchor),
            middleView.trailingAnchor.constraint(equalTo: animationContainerView.trailingAnchor),
            middleView.topAnchor.constraint(equalTo: animationContainerView.topAnchor, constant: currentTipCell.frame.origin.y - tipsTableView.contentOffset.y),
            middleView.heightAnchor.constraint(equalToConstant: currentTipCell.frame.size.height)
        ])
        middleView.setNeedsLayout()
        middleView.layoutIfNeeded()

        let standinTipCardView = TipCardView(item: currentTipCell.contained.item!.deepCopy())
        standinTipCardView.completedImageView.alpha = 0.0
        standinTipCardView.completedImageView.isHidden = false
        standinTipCardView.translatesAutoresizingMaskIntoConstraints = false
        middleView.addSubview(standinTipCardView)
        let horizontalInset = currentTipCell.contained.frame.origin.x
        let verticalInset = currentTipCell.contained.frame.origin.y
        NSLayoutConstraint.activate([
            standinTipCardView.topAnchor.constraint(equalTo: middleView.topAnchor, constant: verticalInset),
            standinTipCardView.leadingAnchor.constraint(equalTo: middleView.leadingAnchor, constant: horizontalInset),
            standinTipCardView.centerXAnchor.constraint(equalTo: middleView.centerXAnchor)
        ])
        standinTipCardView.setNeedsLayout()
        standinTipCardView.layoutIfNeeded()

        let endingItem = standinTipCardView.item!.deepCopy()
        endingItem.isCompleted.accept(true)
        endingItem.style.accept(.compact)
        let endingTipCardView = TipCardView(item: endingItem)
        endingTipCardView.translatesAutoresizingMaskIntoConstraints = false
        endingTipCardView.isHidden = true
        animationContainerView.insertSubview(endingTipCardView, at: 0)
        NSLayoutConstraint.activate([
            endingTipCardView.topAnchor.constraint(equalTo: animationContainerView.topAnchor),
            endingTipCardView.leadingAnchor.constraint(equalTo: animationContainerView.leadingAnchor, constant: TipCardCell.horizontalMargin),
            endingTipCardView.centerXAnchor.constraint(equalTo: animationContainerView.centerXAnchor)
        ])
        endingTipCardView.setNeedsLayout()
        endingTipCardView.layoutIfNeeded()

        tipsTableView.superview?.insertSubview(animationContainerView, aboveSubview: tipsTableView)
        animationContainerView.pin(to: tipsTableView)
        animationContainerView.bringSubviewToFront(middleView)
        animationContainerView.superview?.setNeedsLayout()
        animationContainerView.superview?.layoutIfNeeded()
        animationContainerView.setNeedsLayout()
        animationContainerView.layoutIfNeeded()
        tipsTableView.isHidden = true
        completeTipAnimationStarted.accept(())

        let standinSubtitleLabel = standinTipCardView.setupSubtitleLabel()
        standinSubtitleLabel.text = standinTipCardView.subtitleLabel.text
        standinTipCardView.addSubview(standinSubtitleLabel)
        NSLayoutConstraint.activate([
            standinSubtitleLabel.bottomAnchor.constraint(equalTo: standinTipCardView.textStackView.bottomAnchor),
            standinSubtitleLabel.leadingAnchor.constraint(equalTo: standinTipCardView.textStackView.leadingAnchor),
            standinSubtitleLabel.trailingAnchor.constraint(equalTo: standinTipCardView.textStackView.trailingAnchor)
        ])
        standinTipCardView.setNeedsLayout()
        standinTipCardView.layoutIfNeeded()
        standinTipCardView.subtitleLabel.isHidden = true

        let moveOffset = standinTipCardView.frame.size.height - endingTipCardView.frame.size.height
        let collapseAnimator = UIViewPropertyAnimator(duration: 0.4, controlPoint1: CGPoint(x: 0.36, y: 0), controlPoint2: CGPoint(x: 0.66, y: -0.56)) {
            tableViewBottomSliceView.transform = CGAffineTransform(translationX: 0.0, y:  -moveOffset)
            standinTipCardView.tagsCollectionView.alpha = 0.0
            standinTipCardView.completedImageView.alpha = 1.0
            standinTipCardView.textStackViewToTopViewConstraint?.isActive = true
            standinTipCardView.expandedHeightAnchor?.isActive = false
            standinSubtitleLabel.alpha = 0.0
            standinTipCardView.setNeedsLayout()
            standinTipCardView.layoutIfNeeded()
            animationContainerView.setNeedsLayout()
            animationContainerView.layoutIfNeeded()
        }
        collapseAnimator.addCompletion { _ in
            self.tipsTableView.isHidden = false
            self.tipsTableViewBottomAnchor.constant = 0.0
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
            self.tipsTableView.contentInset = Self.tipsTableViewDefaultContentInsets
            animationContainerView.removeFromSuperview()
        }
        collapseAnimator.startAnimation()
    }

    func animateUnlockNextTip(lockedTipCardViewItem: TipCardViewItem) {
        view.setNeedsDisplay()
        guard let unlockNewCardCell = tipsTableView.subviews.filter({ $0.isKind(of: UnlockTipCell.self) }).first as? UnlockTipCell else {
            return
        }
        guard let animationSetupInfo = setupAnimationContainerView(forCell: unlockNewCardCell) else {
            return
        }
        let animationContainerView = animationSetupInfo.animationContainerView
        let topSliceSnapshot = animationSetupInfo.topSliceSnapshotView
        let bottomSliceSnapshot = animationSetupInfo.bottomSliceSnapshotView

        let middleView = UIView(frame: .zero)
        middleView.translatesAutoresizingMaskIntoConstraints = false
        animationContainerView.addSubview(middleView)
        NSLayoutConstraint.activate([
            middleView.leadingAnchor.constraint(equalTo: animationContainerView.leadingAnchor),
            middleView.trailingAnchor.constraint(equalTo: animationContainerView.trailingAnchor),
            middleView.bottomAnchor.constraint(equalTo: bottomSliceSnapshot.topAnchor),
            middleView.heightAnchor.constraint(equalToConstant: unlockNewCardCell.frame.size.height)
        ])

        let unlockCardView = UnlockTipView(item: unlockNewCardCell.unlockTipView.unlockTipItem!)
        unlockCardView.translatesAutoresizingMaskIntoConstraints = false
        middleView.addSubview(unlockCardView)
        unlockCardView.pinToSuperview(insets: UIEdgeInsets(top: unlockNewCardCell.unlockTipView.frame.origin.y, left: unlockNewCardCell.unlockTipView.frame.origin.x, bottom: -unlockNewCardCell.unlockTipView.frame.origin.y, right: -unlockNewCardCell.unlockTipView.frame.origin.x))

        animationContainerView.isHidden = true
        tipsTableView.superview?.insertSubview(animationContainerView, aboveSubview: tipsTableView)
        animationContainerView.pin(to: tipsTableView)
        tipsTableView.superview?.setNeedsLayout()
        tipsTableView.superview?.layoutIfNeeded()
        animationContainerView.isHidden = false
        tipsTableView.isHidden = true

        let unlockCardViewFrameOrigin = topSliceSnapshot.convert(unlockNewCardCell.unlockTipView.frame.origin, from: unlockNewCardCell.unlockTipView.superview)
        let tipCardView = TipCardView(item: lockedTipCardViewItem)
        animationContainerView.insertSubview(tipCardView, belowSubview: bottomSliceSnapshot)
        tipCardView.frame.origin = unlockCardViewFrameOrigin
        tipCardView.frame.size = CGSize(width: unlockNewCardCell.unlockTipView.frame.size.width, height: TipCardView.expandedTipHeight)
        tipCardView.setNeedsLayout()
        tipCardView.layoutIfNeeded()
        tipCardView.alpha = 0.0
        tipCardView.backgroundImageView.isHidden = true
        let originalImageViewFrame = tipCardView.frame

        let animationImageView = UIImageView(image: unlockNewCardCell.unlockTipView.backgroundImageView.image)
        animationImageView.frame = animationContainerView.convert(unlockNewCardCell.unlockTipView.frame, from: unlockNewCardCell)
        animationImageView.contentMode = .scaleAspectFill
        animationImageView.cornerRadius = tipCardView.cornerRadius
        animationImageView.layer.masksToBounds = true      
        unlockCardView.backgroundImageView.isHidden = true
        animationContainerView.insertSubview(animationImageView, belowSubview: tipCardView)

        let animator = UIViewPropertyAnimator(duration: 0.35, controlPoint1: CGPoint(x: 0.36, y: 0), controlPoint2: CGPoint(x: 0.66, y: -0.56)) {
            [unlockCardView.labelsStackView, unlockCardView.buttonsStackView].forEach { $0.alpha = 0.0 }
            bottomSliceSnapshot.transform = CGAffineTransform(translationX: 0.0, y: TipCardView.expandedTipHeight + 20.0 - unlockNewCardCell.frame.height)
            animationImageView.frame = originalImageViewFrame
            tipCardView.alpha = 1.0
            unlockCardView.blurView.alpha = 0.0
        }
        animator.addCompletion { _ in
            self.tipsTableView.isHidden = false
            animationContainerView.removeFromSuperview()
        }
        animator.startAnimation()
    }

    func setupAnimationContainerView(forCell cell: UITableViewCell) -> AnimationSetupInfo? {
        // Top slice
        let upperSeparatorCellYPosition = cell.frame.origin.y - tipsTableView.contentOffset.y
        let topSliceBounds = CGRect(x: tipsTableView.bounds.origin.x, y: tipsTableView.bounds.origin.y, width: tipsTableView.frame.size.width, height: upperSeparatorCellYPosition)
        guard let topSliceSnapshot = tipsTableView.resizableSnapshotView(from: topSliceBounds, afterScreenUpdates: false, withCapInsets: .zero) else {
            return nil
        }

        // Lower slice
        let lowerSeparatorCellYPosition = cell.frame.origin.y + cell.frame.height - tipsTableView.contentOffset.y
        let bottomSliceHeight = tipsTableView.frame.size.height - lowerSeparatorCellYPosition
        let bottomSliceBounds = CGRect(x: tipsTableView.bounds.origin.x, y: tipsTableView.bounds.origin.y + lowerSeparatorCellYPosition, width: tipsTableView.frame.size.width, height: bottomSliceHeight)
        guard let bottomSliceSnapshot = tipsTableView.resizableSnapshotView(from: bottomSliceBounds, afterScreenUpdates: false, withCapInsets: .zero) else {
            return nil
        }

        let animationContainerView = UIView(frame: .zero)
        animationContainerView.translatesAutoresizingMaskIntoConstraints = false
        topSliceSnapshot.translatesAutoresizingMaskIntoConstraints = false
        animationContainerView.clipsToBounds = true
        animationContainerView.addSubview(topSliceSnapshot)
        NSLayoutConstraint.activate([
            topSliceSnapshot.topAnchor.constraint(equalTo: animationContainerView.topAnchor),
            topSliceSnapshot.leadingAnchor.constraint(equalTo: animationContainerView.leadingAnchor),
            topSliceSnapshot.trailingAnchor.constraint(equalTo: animationContainerView.trailingAnchor),
            topSliceSnapshot.heightAnchor.constraint(equalToConstant: upperSeparatorCellYPosition)
        ])

        bottomSliceSnapshot.translatesAutoresizingMaskIntoConstraints = false
        animationContainerView.addSubview(bottomSliceSnapshot)
        NSLayoutConstraint.activate([
            bottomSliceSnapshot.bottomAnchor.constraint(equalTo: animationContainerView.bottomAnchor),
            bottomSliceSnapshot.leadingAnchor.constraint(equalTo: animationContainerView.leadingAnchor),
            bottomSliceSnapshot.trailingAnchor.constraint(equalTo: animationContainerView.trailingAnchor),
            bottomSliceSnapshot.heightAnchor.constraint(equalToConstant: bottomSliceHeight)
        ])
        return AnimationSetupInfo(animationContainerView: animationContainerView, topSliceSnapshotView: topSliceSnapshot, bottomSliceSnapshotView: bottomSliceSnapshot)
    }

}
