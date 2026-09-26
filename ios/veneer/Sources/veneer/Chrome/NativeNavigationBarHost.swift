import UIKit

/// A real `UINavigationBar` at the top of the overlay. On iOS 26 its bar
/// button items are Liquid Glass: 44 pt circles and capsules, adjacent
/// trailing items sharing one capsule, with the system's spacing, press
/// response and accessibility.
///
/// Supports a leading button (e.g. back), a title — either the system's
/// plain title/subtitle or a tappable capsule with icon, title and subtitle,
/// like a channel header — and trailing buttons.
@available(iOS 26.0, *)
final class NativeNavigationBarHost: NSObject {
  var onEvent: ((String, Any?) -> Void)?

  let bar = UINavigationBar()
  private let item = UINavigationItem()
  private var lastConfig: NSDictionary?
  private(set) var isHidden = false

  private static let iconSize: CGFloat = 20

  override init() {
    super.init()
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    bar.standardAppearance = appearance
    bar.scrollEdgeAppearance = appearance
    bar.compactAppearance = appearance
    bar.translatesAutoresizingMaskIntoConstraints = false
    bar.setItems([item], animated: false)
  }

  private var leading: NSLayoutConstraint?
  private var trailing: NSLayoutConstraint?

  /// Where UIKit puts the outermost glass items: 20 pt in from the bar's edges.
  private static let systemSideInset: CGFloat = 20

  func attach(to container: UIView) {
    guard bar.superview !== container else { return }
    container.addSubview(bar)
    let leading = bar.leadingAnchor.constraint(equalTo: container.leadingAnchor)
    let trailing = bar.trailingAnchor.constraint(equalTo: container.trailingAnchor)
    self.leading = leading
    self.trailing = trailing
    NSLayoutConstraint.activate([leading, trailing, bar.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor)])
  }

  func detach() {
    bar.removeFromSuperview()
    lastConfig = nil
    lastLeading = nil
    lastTrailing = nil
  }

  /// `{leading: button?, title: {title, subtitle, icon, capsule, id}?,
  ///   trailing: [button], tintColor}`, where button = `{id, icon, title, menu?}`.
  ///
  /// Items are replaced only when their part of the config changed, and
  /// animated once the bar is showing, so UIKit morphs the glass between the
  /// old and new buttons (e.g. two trailing buttons becoming one).
  func update(_ args: [String: Any]) {
    let config = args as NSDictionary
    guard lastConfig != config else { return }
    let animated = lastConfig != nil && !isHidden && bar.window != nil
    lastConfig = config

    let title = args["title"] as? [String: Any]
    let leadingKey: NSArray = [args["leading"] ?? NSNull(), title ?? NSNull()]
    if leadingKey != lastLeading {
      lastLeading = leadingKey
      var leading: [UIBarButtonItem] = []
      if let back = args["leading"] as? [String: Any] { leading.append(button(back)) }
      if let title, (title["capsule"] as? Bool) == true {
        let capsule = TitleCapsuleControl()
        capsule.configure(title)
        capsule.addAction(UIAction { [weak self] _ in self?.onEvent?("navItemPressed", ["id": title["id"] ?? "title"]) }, for: .touchUpInside)
        if !leading.isEmpty { leading.append(.fixedSpace(0)) }  // separate glass backgrounds
        leading.append(UIBarButtonItem(customView: capsule))
        item.title = nil
        item.subtitle = nil
      } else {
        item.title = title?["title"] as? String
        item.subtitle = title?["subtitle"] as? String
      }
      item.setLeftBarButtonItems(leading, animated: animated)
    }
    item.hidesBackButton = true

    let trailing = (args["trailing"] as? [[String: Any]]) ?? []
    if trailing as NSArray != lastTrailing {
      lastTrailing = trailing as NSArray
      // UIKit lays right items out trailing-first; Dart lists them in reading order.
      item.setRightBarButtonItems(trailing.reversed().map(button), animated: animated)
    }
    bar.tintColor = (args["tintColor"] as? NSNumber).map(UIColor.init(argb:))
  }

  private var lastLeading: NSArray?
  private var lastTrailing: NSArray?

  private func button(_ spec: [String: Any]) -> UIBarButtonItem {
    let id = spec["id"] as? String ?? ""
    let image = NativeIconDescriptor(spec["icon"]).flatMap {
      NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? nil : Self.iconSize)
    }
    let title = spec["title"] as? String
    let item: UIBarButtonItem
    if let menu = NativeMenu.make(spec["menu"], id: id, onSelect: { [weak self] itemId in
      self?.onEvent?("navItemPressed", ["id": itemId])
    }) {
      item = image != nil ? UIBarButtonItem(image: image, menu: menu) : UIBarButtonItem(title: title, menu: menu)
    } else {
      let action = UIAction(title: title ?? "", image: image) { [weak self] _ in
        self?.onEvent?("navItemPressed", ["id": id])
      }
      item = UIBarButtonItem(primaryAction: action)
      if image != nil { item.title = nil }
    }
    item.accessibilityLabel = title
    return item
  }

  /// Distance from the screen (or sheet) edges to the outermost buttons;
  /// nil keeps UIKit's. The bar ignores layout margins for its glass items,
  /// so the bar itself is shifted.
  func setSideInset(_ inset: CGFloat?) {
    let shift = inset.map { $0 - Self.systemSideInset } ?? 0
    leading?.constant = shift
    trailing?.constant = -shift
  }

  func setHidden(_ hidden: Bool) {
    guard hidden != isHidden else { return }
    isHidden = hidden
    UIView.animate(withDuration: hidden ? 0.15 : 0.25) { self.bar.alpha = hidden ? 0 : 1 }
  }

  /// Only the bar's controls take touches; its empty areas pass through.
  func hitTest(_ point: CGPoint, in container: UIView, with event: UIEvent?) -> UIView? {
    guard !isHidden, bar.superview != nil,
      let hit = bar.hitTest(container.convert(point, to: bar), with: event)
    else { return nil }
    var v: UIView? = hit
    while let current = v, current !== bar {
      if current is UIControl { return hit }
      v = current.superview
    }
    return nil
  }
}

/// Channel-header style title: an icon beside a bold title and a secondary
/// subtitle, as the custom view of a glass bar button item.
@available(iOS 26.0, *)
final class TitleCapsuleControl: UIControl {
  private let iconView = UIImageView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let stack = UIStackView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    iconView.contentMode = .scaleAspectFit
    iconView.tintColor = .label
    iconView.preferredSymbolConfiguration = .init(pointSize: 17, weight: .semibold)
    titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
    titleLabel.textColor = .label
    subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
    subtitleLabel.textColor = .secondaryLabel

    let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    text.axis = .vertical
    text.spacing = 0
    stack.addArrangedSubview(iconView)
    stack.addArrangedSubview(text)
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 10
    stack.isUserInteractionEnabled = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      heightAnchor.constraint(equalToConstant: 44),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(_ spec: [String: Any]) {
    titleLabel.text = spec["title"] as? String
    subtitleLabel.text = spec["subtitle"] as? String
    subtitleLabel.isHidden = (spec["subtitle"] as? String)?.isEmpty ?? true
    iconView.image = NativeIconDescriptor(spec["icon"]).flatMap {
      NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? nil : 18)
    }
    iconView.isHidden = iconView.image == nil
    accessibilityLabel = [titleLabel.text, subtitleLabel.text].compactMap { $0 }.joined(separator: ", ")
  }

  override var isHighlighted: Bool {
    didSet { stack.alpha = isHighlighted ? 0.5 : 1 }
  }
}
