import UIKit

/// Interactive keyboard dismissal for Flutter content, using UIKit's own
/// mechanism: the keyboard follows a dragging finger off screen and can be
/// pulled back up to cancel, exactly as in a `UIScrollView` with
/// `keyboardDismissMode = .interactive`.
///
/// UIKit only drives that from a scroll view's pan gesture, and Flutter's
/// list isn't a `UIScrollView`. So an invisible, content-less scroll view
/// provides the mechanism, and its `panGestureRecognizer` is attached to the
/// `FlutterView` — a supported way to drive a scroll view from touches on
/// another view. With `cancelsTouchesInView = false` Flutter still receives
/// every touch and scrolls its list; the same drag moves this scroll view,
/// which is all UIKit needs to track the keyboard.
///
/// The drag only begins for touches that belong to Flutter (not to native
/// chrome such as the composer's text view or the tab bar).
@available(iOS 26.0, *)
final class KeyboardDismissProxy: UIScrollView, UIScrollViewDelegate {
  /// Returns whether a drag starting at this point (in the host view) is
  /// on Flutter content.
  var isFlutterTouch: ((CGPoint) -> Bool)?

  private weak var host: UIView?
  private static let contentHeight: CGFloat = 1_000_000

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isUserInteractionEnabled = false  // its own hit testing never matters
    keyboardDismissMode = .interactive
    alwaysBounceVertical = true
    showsVerticalScrollIndicator = false
    showsHorizontalScrollIndicator = false
    contentInsetAdjustmentBehavior = .never
    scrollsToTop = false
    delegate = self
    topEdgeEffect.isHidden = true
    bottomEdgeEffect.isHidden = true
    panGestureRecognizer.cancelsTouchesInView = false
    panGestureRecognizer.delaysTouchesBegan = false
    panGestureRecognizer.delaysTouchesEnded = false
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// Moves the pan gesture onto `view` (the FlutterView).
  func drive(from view: UIView) {
    guard host !== view else { return }
    host?.removeGestureRecognizer(panGestureRecognizer)
    view.addGestureRecognizer(panGestureRecognizer)
    host = view
  }

  func stopDriving() {
    host?.removeGestureRecognizer(panGestureRecognizer)
    addGestureRecognizer(panGestureRecognizer)
    host = nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if contentSize.width != bounds.width {
      contentSize = CGSize(width: bounds.width, height: Self.contentHeight)
      recenter()
    }
  }

  /// Parks the (empty) content in the middle, so it never hits an edge.
  private func recenter() {
    guard !isTracking else { return }
    contentOffset = CGPoint(x: 0, y: Self.contentHeight / 2)
  }

  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer === panGestureRecognizer, let host else {
      return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
    // Vertical drags on Flutter content only.
    let velocity = panGestureRecognizer.velocity(in: host)
    guard abs(velocity.y) >= abs(velocity.x) else { return false }
    return isFlutterTouch?(panGestureRecognizer.location(in: host)) ?? false
  }

  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    if !decelerate { recenter() }
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { recenter() }
}
