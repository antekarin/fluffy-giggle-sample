import RxCocoa
import RxSwift
import Foundation

struct TipCardViewItem {
    let id: BehaviorRelay<String>

    let backgroundImageURL: BehaviorRelay<URL?>
    let backgroundImage: PublishRelay<UIImage?>

    let tagItems: BehaviorRelay<[TipTagViewItem]>
    let newTagShown: BehaviorRelay<Bool>
    let title: BehaviorRelay<String>
    let subtitle: BehaviorRelay<String?>

    let isSaved: BehaviorRelay<Bool>
    let isCompleted: BehaviorRelay<Bool>
    let isLocked: BehaviorRelay<Bool>
    let isLoading = BehaviorRelay<Bool>(value: false)

    let style: BehaviorRelay<TipCardView.Style>

    let saveAction = PublishSubject<Void>()
    let tapAction = PublishSubject<String>()
    let reloadTrigger = PublishSubject<Void>()

    init(id: String, backgroundImageURL: URL?, backgroundImage: UIImage? = nil, tagItems: [TipTagViewItem], newTagShown: Bool, title: String, subtitle: String?, isSaved: Bool, isCompleted: Bool, isLocked: Bool, style: TipCardView.Style = .expanded) {
        self.id = BehaviorRelay<String>(value: id)
        self.tagItems = BehaviorRelay<[TipTagViewItem]>(value: tagItems)
        self.newTagShown = BehaviorRelay<Bool>(value: newTagShown)
        self.title = BehaviorRelay<String>(value: title)
        self.subtitle = BehaviorRelay<String?>(value: subtitle)
        self.isSaved = BehaviorRelay<Bool>(value: isSaved)
        self.isCompleted = BehaviorRelay<Bool>(value: isCompleted)
        self.isLocked = BehaviorRelay<Bool>(value: isLocked)
        self.style = BehaviorRelay<TipCardView.Style>(value: style)
        self.backgroundImageURL = BehaviorRelay<URL?>(value: backgroundImageURL)
        self.backgroundImage = PublishRelay<UIImage?>()
    }

    init(apiTip: APITipPreview, style: TipCardView.Style) {
        let tagItems = apiTip.topics.prefix(2).map { TipTagViewItem(text: $0) }
        self.init(
            id: apiTip.id,
            backgroundImageURL: apiTip.coachImageUrlThumbnailLarge,
            tagItems: tagItems,
            newTagShown: false,
            title: apiTip.headline,
            subtitle: apiTip.description,
            isSaved: apiTip.isSaved ?? false,
            isCompleted: apiTip.isCompleted,
            isLocked: apiTip.isLocked ?? false,
            style: style
        )
    }
}

// MARK: - Logic helpers -

extension TipCardViewItem {

    func updateWith(tip: APITip) {
        id.accept(tip.id)
        title.accept(tip.headline)
        subtitle.accept(tip.title)
        tagItems.accept(tip.topics.prefix(2).map { TipTagViewItem(text: $0) })
        backgroundImageURL.accept(tip.tipBackgroundImageURL)
        isCompleted.accept(tip.isCompleted)
        isLocked.accept(false)
        isSaved.accept(tip.isSaved)
    }

    func deepCopy() -> TipCardViewItem {
        TipCardViewItem(id: id.value, backgroundImageURL: backgroundImageURL.value, tagItems: tagItems.value, newTagShown: newTagShown.value, title: title.value, subtitle: subtitle.value, isSaved: isSaved.value, isCompleted: isCompleted.value, isLocked: isLocked.value, style: style.value)
    }
}
