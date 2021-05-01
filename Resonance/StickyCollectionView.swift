import Cocoa

final class StickyCollectionView: NSScrollView {
    let collectionView = NSCollectionView()
    var stickToBottom = true

    init() {
        super.init(frame: .zero)
        hasHorizontalScroller = true
        hasVerticalScroller = true
        documentView = collectionView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func scrollToStickyPosition() {
        guard stickToBottom else { return }

        guard collectionView.numberOfSections > 0 else  { return }
        let count = collectionView.numberOfItems(inSection: 0)
        guard count > 0 else { return }
        collectionView.scrollToItems(at: [IndexPath(item: count - 1, section: 0)], scrollPosition: .bottom)
    }
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)

        let threshold: CGFloat = 128
        stickToBottom = documentVisibleRect.maxY + threshold >= collectionView.bounds.height
    }
}
