import UIKit

class SelfSizingCollectionView: UICollectionView {

    override func reloadData() {
        super.reloadData()

        invalidateIntrinsicContentSize()
        setNeedsLayout()
        layoutIfNeeded()
    }

    override var intrinsicContentSize: CGSize {
        collectionViewLayout.collectionViewContentSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if bounds.size != intrinsicContentSize {
            invalidateIntrinsicContentSize()
        }
    }

    override var frame: CGRect {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }
}
