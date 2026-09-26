import UIKit

/// iOS 26's scroll edge effect — the soft, progressive blur that content
/// fades into under bars — applied over Flutter content.
///
/// UIKit attaches this effect to `UIScrollView`, and Flutter doesn't scroll
/// with one. So a transparent, non-interactive scroll view spans the
/// overlay, parked one point "scrolled" in each direction so its edges are
/// active, and the chrome registers with it through
/// `UIScrollEdgeElementContainerInteraction`, which shapes the effect
/// around the bars' controls exactly as for a UIKit screen.
@available(iOS 26.0, *)
final class ScrollEdgeEffectHost {
  let scrollView = UIScrollView()
  /// Keyed by `UIRectEdge.rawValue` (the option set isn't Hashable).
  private var interactions: [UInt: [UIScrollEdgeElementContainerInteraction]] = [:]

  init() {
    scrollView.backgroundColor = .clear
    scrollView.isUserInteractionEnabled = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.topEdgeEffect.isHidden = true
    scrollView.bottomEdgeEffect.isHidden = true
    scrollView.leftEdgeEffect.isHidden = true
    scrollView.rightEdgeEffect.isHidden = true
  }

  func attach(to container: UIView, at index: Int) {
    guard scrollView.superview !== container else { return }
    scrollView.frame = container.bounds
    scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.insertSubview(scrollView, at: index)
    layout()
  }

  /// Keeps the content one point larger than the viewport in both
  /// directions and parked in the middle, so both edges count as scrolled.
  func layout() {
    let size = scrollView.bounds.size
    guard size.height > 0 else { return }
    scrollView.contentSize = CGSize(width: size.width, height: size.height + 2)
    scrollView.contentOffset = CGPoint(x: 0, y: 1)
  }

  /// Shows the effect at `edge`, shaped around the controls inside `elements`.
  func set(_ edge: UIRectEdge, style: String?, elements: [UIView]) {
    let effect: UIScrollEdgeEffect = edge == .top ? scrollView.topEdgeEffect : scrollView.bottomEdgeEffect
    for old in interactions.removeValue(forKey: edge.rawValue) ?? [] { old.view?.removeInteraction(old) }
    guard let style, style != "none", !elements.isEmpty else {
      effect.isHidden = true
      return
    }
    effect.isHidden = false
    effect.style = style == "hard" ? .hard : style == "soft" ? .soft : .automatic
    interactions[edge.rawValue] = elements.map { element in
      let interaction = UIScrollEdgeElementContainerInteraction()
      interaction.scrollView = scrollView
      interaction.edge = edge
      element.addInteraction(interaction)
      return interaction
    }
  }
}
