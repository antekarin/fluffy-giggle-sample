import UIKit
import RxSwift
import RxCocoa

final class CoachWireframe: BaseWireframe {

    // MARK: - Private properties -

    // MARK: - Module setup -

    init(router: AppRouteable) {
        let moduleViewController = CoachViewController()
        moduleViewController.title = ""
        super.init(viewController: moduleViewController)

        let interactor = CoachInteractor(router: router)
        let presenter = CoachPresenter(view: moduleViewController, interactor: interactor, wireframe: self)
        moduleViewController.presenter = presenter
    }

}

// MARK: - Extensions -

extension CoachWireframe: CoachWireframeInterface {

    func navigateToExplore() {
        viewController.tabBarController?.selectedIndex = 1
    }
    
    func navigateToTipPreview(tipId: String, source: Tip.Source) {
        let wireframe = TipPreviewWireframe(tipId: tipId, source: source)
        navigationController?.pushWireframe(wireframe)
    }
    
}
