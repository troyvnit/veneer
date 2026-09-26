import UIKit

/// One glass shape. Content (SF Symbol / label) is native so it gets the
/// system's vibrant treatment on glass — Flutter pixels can only ever sit
/// *under* this layer, never inside it.
@available(iOS 26.0, *)
final class GlassShapeView: UIVisualEffectView {
  let id: Int
  var onTap: ((Int) -> Void)?
  private(set) var isInteractive = false
  private(set) var isShown = false
  /// Latest visibility requested by Flutter; `isShown` catches up async.
  var targetVisible = false

  /// Owning group and clip scope, as last placed by `GlassLayerView`.
  var groupId = 0
  var clipId = 0

  private var glass = UIGlassEffect(style: .regular)
  private let stack = UIStackView()
  private let imageView = UIImageView()
  private let label = UILabel()
  private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))

  /// Default for glyphs and SVGs: matches an SF Symbol at the body text style.
  private static let iconSize: CGFloat = 22

  init(id: Int) {
    self.id = id
    super.init(effect: nil)
    cornerConfiguration = .capsule()

    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    imageView.preferredSymbolConfiguration = .init(textStyle: .body, scale: .medium)
    imageView.contentMode = .scaleAspectFit
    label.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
    label.adjustsFontForContentSizeCategory = true
    stack.addArrangedSubview(imageView)
    stack.addArrangedSubview(label)
    contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
    stack.alpha = 0
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func apply(_ c: GlassShapeConfig) {
    let g = UIGlassEffect(style: c.clear ? .clear : .regular)
    g.tintColor = c.tint
    g.isInteractive = c.interactive
    glass = g
    if isShown { effect = g }

    isInteractive = c.interactive
    if c.interactive { addGestureRecognizer(tap) } else { removeGestureRecognizer(tap) }

    if let r = c.cornerRadius {
      cornerConfiguration = .corners(radius: .fixed(r))
    } else {
      cornerConfiguration = .capsule()
    }

    // Symbols take the body text style via preferredSymbolConfiguration;
    // glyphs and SVGs render at the matching size as template images.
    imageView.preferredSymbolConfiguration =
      c.iconSize.map { UIImage.SymbolConfiguration(pointSize: $0) } ?? .init(textStyle: .body, scale: .medium)
    imageView.image = c.icon.flatMap {
      NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? c.iconSize : c.iconSize ?? Self.iconSize)
    }
    imageView.isHidden = imageView.image == nil
    label.text = c.label
    label.isHidden = (c.label ?? "").isEmpty
    imageView.tintColor = c.foreground ?? .label
    label.textColor = c.foreground ?? .label
    accessibilityLabel = c.label
    isAccessibilityElement = c.interactive
    accessibilityTraits = c.interactive ? .button : .none
  }

  /// Materialize / dematerialize by animating `effect`, never `alpha`:
  /// a `UIVisualEffectView` with alpha < 1 renders incorrectly.
  func setVisible(_ visible: Bool) {
    guard visible != isShown else { return }
    isShown = visible
    UIView.animate(withDuration: visible ? 0.3 : 0.2) {
      self.effect = visible ? self.glass : nil
      self.stack.alpha = visible ? 1 : 0
    }
  }

  func dematerialize(completion: @escaping () -> Void) {
    isShown = false
    targetVisible = false
    UIView.animate(withDuration: 0.2, animations: {
      self.effect = nil
      self.stack.alpha = 0
    }, completion: { _ in completion() })
  }

  /// Hidden and non-interactive shapes must be transparent to hit testing,
  /// or they shadow interactive shapes beneath them (e.g. an offstage
  /// page's pill under an onstage button) and the touch falls to Flutter.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isInteractive, isShown else { return nil }
    return super.hitTest(point, with: event)
  }

  @objc private func handleTap() { onTap?(id) }
}

private extension UIFont {
  func withWeight(_ weight: UIFont.Weight) -> UIFont {
    let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: 0)
  }
}
