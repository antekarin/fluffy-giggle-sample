import RxSwift

struct NextDayEmptyStateViewItem {

    // TODO: Define headline text randomization
    let smalltitle: String
    let largeTitle: String
    let action = PublishSubject<Void>()

}
