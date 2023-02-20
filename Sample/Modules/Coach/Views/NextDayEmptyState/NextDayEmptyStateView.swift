import RxCocoa
import RxSwift
import UIKit

class NextDayEmptyStateView: UIView {

    private lazy var headlineView = HeadlineView(frame: .zero)
    private lazy var bodyStackView = StackView(item: StackViewItem(axis: .vertical, distribution: .fillProportionally, alignment: .fill, spacing: 12.0))

    private lazy var lockedTipView = TipLockedView(item: TipLockedViewItem(image: #imageLiteral(resourceName: "tip-locked-bg-brown")))
    private lazy var locked2TipView = TipLockedView(item: TipLockedViewItem(image: #imageLiteral(resourceName: "tip-locked-bg-blue")))
    private lazy var locked3TipView = TipLockedView(item: TipLockedViewItem(image: #imageLiteral(resourceName: "tip-locked-bg-green")))
    private lazy var separatorCell1 = CoachSeparatorCell(style: .default, reuseIdentifier: nil)
    private lazy var separatorCell2 = CoachSeparatorCell(style: .default, reuseIdentifier: nil)

    private lazy var actionButton = PrimaryButton(frame: .zero)

    private let disposeBag = DisposeBag()

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

    convenience init(item: NextDayEmptyStateViewItem) {
        self.init(frame: .zero)

        configure(with: item)
    }

}

// MARK: - Configure -

extension NextDayEmptyStateView {

    func configure(with item: NextDayEmptyStateViewItem) {
        headlineView.configure(with: HeadlineViewItem(smallTitleString: item.smalltitle, mainTitleString: item.largeTitle))

        actionButton.rx
            .tap
            .bind(to: item.action)
            .disposed(by: disposeBag)
    }

}

// MARK: - View Setup -

extension NextDayEmptyStateView {

    func setupView() {
        backgroundColor = UIColor.sampleCodeBlack
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(headlineView)

        bodyStackView.addArrangedSubview(lockedTipView)
        bodyStackView.addArrangedSubview(separatorCell1)
        bodyStackView.addArrangedSubview(locked2TipView)
        bodyStackView.addArrangedSubview(separatorCell2)
        bodyStackView.addArrangedSubview(locked3TipView)
        addSubview(bodyStackView)

        addSubview(actionButton)
    }

    func setupLayout() {
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: headlineView.topAnchor, constant: -12.0),
            leadingAnchor.constraint(equalTo: headlineView.leadingAnchor, constant: -16.0),
            centerXAnchor.constraint(equalTo: headlineView.centerXAnchor)
        ])

        NSLayoutConstraint.activate([
            bodyStackView.topAnchor.constraint(equalTo: headlineView.bottomAnchor, constant: 24.0),
            bodyStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12.0),
            bodyStackView.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])

        NSLayoutConstraint.activate([
            actionButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -24.0),
            actionButton.leadingAnchor.constraint(equalTo: headlineView.leadingAnchor),
            actionButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 50.0)
        ])
    }

}
