import Kingfisher
import RxCocoa
import RxDataSources
import RxSwift
import SkeletonView
import DeviceKit

class TipCardView: UIView {

    static let expandedTipHeight: CGFloat = 352.0

    enum Style {
        case expanded
        case compact
    }

    // UI
    lazy var backgroundImageView = setupBackgroundImageView()
    private let cardOverlayView = CardOverlayView()

    lazy var tagsCollectionView = setupTagsCollectionView()
    private lazy var newTagView = setupNewTag()

    private lazy var titleLabel = setupTitle()
    lazy var subtitleLabel = setupSubtitleLabel()

    private lazy var saveTipButton = setupSaveTipButton()
    lazy var completedImageView = setupCompletedImageView()

    lazy var tagsStackView = setupTagsStackView()
    lazy var textStackView = setupTextStackView()

    var expandedHeightAnchor: NSLayoutConstraint?
    var textStackViewToTopViewConstraint: NSLayoutConstraint?
    private var titleLabelHeightConstraint: NSLayoutConstraint?
    
    private let tapRecognizer = UITapGestureRecognizer()

    // Logic
    var style: Style = .expanded {
        didSet {
            tagsStackView.isHidden = style == .expanded ? false : true
            subtitleLabel.isHidden = style == .expanded ? false : true
            expandedHeightAnchor?.isActive = style == .expanded ? true : false
            textStackViewToTopViewConstraint?.isActive = style == .expanded ? false : true
        }
    }

    var item: TipCardViewItem?

    private var disposeBag = DisposeBag()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupView()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        setupView()
        setupLayout()
    }

    convenience init(item: TipCardViewItem) {
        self.init()

        configure(with: item)
    }

}

// MARK: Configuration

extension TipCardView {

    func configure(with item: TipCardViewItem) {
        self.item = item
        disposeBag = DisposeBag()

        let dataSource = RxCollectionViewSectionedReloadDataSource<TipTagSection> { _, collectionView, indexPath, item in
            let cell = collectionView.dequeueReusableCell(for: indexPath, cellType: TipTagCell.self)
            cell.configure(with: item)
            return cell
        }

        item.tagItems
            .map { [TipTagSection(items: $0.map { TipTagCellItem(tagItem: $0) })] }
            .bind(to: tagsCollectionView.rx.items(dataSource: dataSource))
            .disposed(by: disposeBag)

        item.newTagShown
            .map { !$0 }
            .bind(to: newTagView.rx.isHidden)
            .disposed(by: disposeBag)

        item.title
            .bind(to: titleLabel.rx.text)
            .disposed(by: disposeBag)

        item.subtitle
            .bind(to: subtitleLabel.rx.text)
            .disposed(by: disposeBag)

        item.isSaved
            .map { isSaved in
                let title = isSaved ? L10n.tipSaved : L10n.saveTip
                let image = isSaved ? #imageLiteral(resourceName: "icon-tip-saved") : #imageLiteral(resourceName: "icon-save-tip")
                return RegularButtonItem(title: title, fontStyle: .body, backgroundColor: .clear, borderColor: .clear, selectedBackgroundColor: .clear, disabledBackgroundColor: .clear, icon: image, titleColor: .white, titleColorSelected: .sampleCodeWhite, titleDisabledColor: .sampleCodeWhite)
            }
            .bind(to: saveTipButton.rx.item)
            .disposed(by: disposeBag)

        item.isLoading
            .asDriver()
            .drive(onNext: { [weak self] isLoading in
                guard let self = self else { return }
                isLoading ? self.showAnimatedGradientSkeleton(usingGradient: SkeletonGradient(baseColor: .sampleCodeDarkGray1), transition: .none) : self.hideSkeleton()
            })
            .disposed(by: disposeBag)

        item.style
            .subscribe(onNext: { [unowned self] style in
                self.style = style
            })
            .disposed(by: disposeBag)
        
        item.backgroundImageURL
            .subscribe(onNext: { [unowned self] url in
                self.backgroundImageView.setImage(with: url, placeholder: nil)
            })
            .disposed(by: disposeBag)

        item.backgroundImage
            .bind(to: backgroundImageView.rx.image)
            .disposed(by: disposeBag)
        
        item.isCompleted
            .map { !$0 }
            .bind(to: completedImageView.rx.isHidden)
            .disposed(by: disposeBag)

        tapRecognizer
            .rx
            .event
            .withLatestFrom(item.id.asObservable())
            .bind(to: item.tapAction)
            .disposed(by: disposeBag)
        
        saveTipButton
            .rx
            .tap
            .bind(to: item.saveAction)
            .disposed(by: disposeBag)

        setNeedsLayout()
        layoutIfNeeded()
    }

}

// MARK: View Setup

private extension TipCardView {

    func setupView() {
        clipsToBounds = true
        cornerRadius = 8.0
        cardOverlayView.cornerRadius = 8.0

        addSubview(backgroundImageView)
        addSubview(cardOverlayView)

        tagsStackView.addArrangedSubview(tagsCollectionView)
        tagsStackView.addArrangedSubview(newTagView)
        addSubview(tagsStackView)

        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(subtitleLabel)
        addSubview(textStackView)

        addSubview(completedImageView)
        addSubview(saveTipButton)
        isSkeletonable = true
        
        addGestureRecognizer(tapRecognizer)
    }

    func setupLayout() {
        expandedHeightAnchor = heightAnchor.constraint(equalToConstant: TipCardView.expandedTipHeight)
        textStackViewToTopViewConstraint = textStackView.topAnchor.constraint(equalTo: topAnchor, constant: 20.0)

        backgroundImageView.pinToSuperview()
        cardOverlayView.pinToSuperview()

        NSLayoutConstraint.activate([
            tagsStackView.topAnchor.constraint(equalTo: topAnchor, constant: 20.0),
            tagsStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20.0),
            tagsStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20.0)
        ])

        NSLayoutConstraint.activate([
            textStackView.leadingAnchor.constraint(equalTo: tagsStackView.leadingAnchor),
            textStackView.trailingAnchor.constraint(equalTo: tagsStackView.trailingAnchor)
        ])

        NSLayoutConstraint.activate([
            saveTipButton.topAnchor.constraint(equalTo: textStackView.bottomAnchor, constant: 20.0),
            saveTipButton.leadingAnchor.constraint(equalTo: textStackView.leadingAnchor),
            saveTipButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20.0),
            saveTipButton.heightAnchor.constraint(equalToConstant: 24.0)
        ])

        NSLayoutConstraint.activate([
            completedImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            completedImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            completedImageView.widthAnchor.constraint(equalTo: completedImageView.heightAnchor),
            completedImageView.heightAnchor.constraint(equalToConstant: 32.0)
        ])

        NSLayoutConstraint.activate([
            newTagView.heightAnchor.constraint(equalToConstant: 28.0),
            tagsCollectionView.widthAnchor.constraint(equalTo: tagsStackView.widthAnchor)
        ])
    }

}

// MARK: UI Elements

extension TipCardView {

    func setupSubtitleLabel() -> UILabel {
        let fontStyle: UIFont.Style = Device.current.diagonal >= 4.7 ? .body : .subhead
        let label = Label(item: LabelItem(fontStyle: fontStyle, color: .sampleCodeWhite.withAlphaComponent(0.75), numberOfLines: 2, textAlignment: .left))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isSkeletonable = true
        label.minimumScaleFactor = 0.5
        label.layer.shadowColor = UIColor.black.withAlphaComponent(0.16).cgColor
        label.layer.shadowOpacity = 1.0
        label.layer.shadowRadius = 6.0
        label.layer.shadowOffset = CGSize(width: 0, height: 0)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

}

private extension TipCardView {

    func setupTagsStackView() -> UIStackView {
        let stackView = UIStackView(frame: .zero)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.isSkeletonable = true
        return stackView
    }

    func setupTextStackView() -> UIStackView {
        let stackView = UIStackView(frame: .zero)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 6.0
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.isSkeletonable = true
        return stackView
    }

    func setupSaveTipStackView() -> UIStackView {
        let stackView = UIStackView(frame: .zero)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.distribution = .fillProportionally
        return stackView
    }

    func setupTagsCollectionView() -> UICollectionView {
        let flowLayout = LeftAlignedCollectionViewFlowLayout()
        flowLayout.scrollDirection = .vertical
        flowLayout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        let collectionView = SelfSizingCollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.isSkeletonable = true
        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(cellType: TipTagCell.self)
        collectionView.setContentHuggingPriority(.required, for: .vertical)
        return collectionView
    }

    func setupNewTag() -> TipTagView {
        let view = TipTagView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: TipTagViewItem(text: L10n.new.uppercased()))
        view.isSkeletonable = true
        return view
    }

    func setupTitle() -> UILabel {
        let fontStyle: UIFont.Style = Device.current.diagonal >= 4.7 ? .title2 : .title3
        let label = Label(item: LabelItem(fontStyle: fontStyle, color: .sampleCodeWhite, numberOfLines: 4, textAlignment: .left))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isSkeletonable = true
        label.minimumScaleFactor = 0.5
        label.layer.shadowColor = UIColor.black.withAlphaComponent(0.16).cgColor
        label.layer.shadowOpacity = 1.0
        label.layer.shadowRadius = 6.0
        label.layer.shadowOffset = CGSize(width: 0, height: 0)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    func setupSaveTipButton() -> RegularButton {
        let button = RegularButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isSkeletonable = true
        button.setContentHuggingPriority(.required, for: .vertical)
        return button
    }

    func setupCompletedImageView() -> UIImageView {
        let completedImageView = UIImageView(image: #imageLiteral(resourceName: "icon-check-large"))
        completedImageView.translatesAutoresizingMaskIntoConstraints = false
        completedImageView.contentMode = .scaleAspectFill
        return completedImageView
    }

    func setupBackgroundImageView() -> UIImageView {
        let imageView = UIImageView(frame: .zero)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.isSkeletonable = true
        imageView.layer.masksToBounds = true
        return imageView
    }
}

struct TipTagSection {
    var items: [Item]
}

extension TipTagSection: SectionModelType {

    typealias Item = TipTagCellItem

    init(original: TipTagSection, items: [Item]) {
        self = original
        self.items = items
    }
}
