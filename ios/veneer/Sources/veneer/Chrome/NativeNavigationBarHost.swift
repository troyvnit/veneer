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
@MainActor
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
  ///   trailing: [button], tintColor}`, where button = `{id, icon, title, menu?,
  ///   prominent, tint}`.
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
        item.title = nil
        item.subtitle = nil
        if (title["fill"] as? Bool) == true {
          // A bar button item hugs its content; the title view is what UIKit
          // stretches between the items, so it carries its own glass.
          item.titleView = FillingTitleCapsule(capsule)
          item.style = .editor
        } else {
          if !leading.isEmpty { leading.append(.fixedSpace(0)) }  // separate glass backgrounds
          leading.append(UIBarButtonItem(customView: capsule))
          item.titleView = nil
          item.style = .navigator
        }
      } else if let title, BarTitleView.isCustom(title) {
        // Styled or leading-aligned: our own labels as the title view, which
        // UIKit fits (and truncates) between the items. The editor style
        // places the title at the leading edge, after the back button.
        let view = BarTitleView()
        view.configure(title)
        item.title = nil
        item.subtitle = nil
        item.titleView = view
        item.style = (title["alignment"] as? String) == "leading" ? .editor : .navigator
      } else {
        item.titleView = nil
        item.style = .navigator
        item.title = title?["title"] as? String
        item.subtitle = title?["subtitle"] as? String
      }
      item.setLeftBarButtonItems(leading, animated: animated)
    }
    item.hidesBackButton = true

    let trailing = (args["trailing"] as? [[String: Any]]) ?? []
    if trailing as NSArray != lastTrailing {
      lastTrailing = trailing as NSArray
      // UIKit lays right items out trailing-first; Dart lists them in reading
      // order. A zero fixed space between groups splits their glass.
      var items: [UIBarButtonItem] = []
      var group: Int?
      for spec in trailing.reversed() {
        let g = (spec["group"] as? NSNumber)?.intValue ?? 0
        if let group, group != g { items.append(.fixedSpace(0)) }
        group = g
        items.append(button(spec))
      }
      item.setRightBarButtonItems(items, animated: animated)
    }
    bar.tintColor = (args["tintColor"] as? NSNumber).map(UIColor.init(argb:))
  }

  private var lastLeading: NSArray?
  private var lastTrailing: NSArray?

  private func button(_ spec: [String: Any]) -> UIBarButtonItem {
    let id = spec["id"] as? String ?? ""
    let size = (spec["iconSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? Self.iconSize
    let image = NativeIconDescriptor(spec["icon"]).flatMap {
      NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? nil : size)
    }
    let title = spec["title"] as? String
    let menu = NativeMenu.make(spec["menu"], id: id, onSelect: { [weak self] itemId in
      self?.onEvent?("navItemPressed", ["id": itemId])
    })
    if (spec["showsTitle"] as? Bool) == true, let image, let title, !title.isEmpty {
      let item = UIBarButtonItem(customView: titledButton(id: id, image: image, title: title, style: spec["titleStyle"], menu: menu))
      item.accessibilityLabel = title
      if (spec["prominent"] as? Bool) == true { item.style = .prominent }
      item.tintColor = (spec["tint"] as? NSNumber).map(UIColor.init(argb:))
      return item
    }
    if let padding = (spec["iconPadding"] as? NSNumber).map({ CGFloat($0.doubleValue) }), let image {
      let item = UIBarButtonItem(customView: PaddedGlassButton(paddedButton(id: id, image: image, title: title, padding: padding, menu: menu)))
      item.hidesSharedBackground = true
      item.accessibilityLabel = title
      if (spec["prominent"] as? Bool) == true { item.style = .prominent }
      item.tintColor = (spec["tint"] as? NSNumber).map(UIColor.init(argb:))
      return item
    }
    let item: UIBarButtonItem
    if let menu {
      item = image != nil ? UIBarButtonItem(image: image, menu: menu) : UIBarButtonItem(title: title, menu: menu)
    } else {
      let action = UIAction(title: title ?? "", image: image) { [weak self] _ in
        self?.onEvent?("navItemPressed", ["id": id])
      }
      item = UIBarButtonItem(primaryAction: action)
      if image != nil { item.title = nil }
    }
    item.accessibilityLabel = title
    if let badge = spec["badge"] as? String {
      if badge.isEmpty {
        item.badge = .indicator()
      } else if let count = Int(badge) {
        item.badge = .count(count)
      } else {
        item.badge = .string(badge)
      }
    }
    if (spec["prominent"] as? Bool) == true { item.style = .prominent }
    item.tintColor = (spec["tint"] as? NSNumber).map(UIColor.init(argb:))
    return item
  }

  /// The icon with its own padding instead of UIKit's bar-button insets, so
  /// the glass hugs it: a 42 pt avatar with 1 pt padding is a 44 pt circle.
  private func paddedButton(id: String, image: UIImage, title: String?, padding: CGFloat, menu: UIMenu?) -> UIButton {
    var config = UIButton.Configuration.plain()
    config.image = image
    config.contentInsets = NSDirectionalEdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding)
    let button = UIButton(configuration: config)
    button.accessibilityLabel = title
    if let menu {
      button.menu = menu
      button.showsMenuAsPrimaryAction = true
    } else {
      button.addAction(UIAction { [weak self] _ in self?.onEvent?("navItemPressed", ["id": id]) }, for: .primaryActionTriggered)
    }
    button.frame.size = CGSize(width: image.size.width + padding * 2, height: image.size.height + padding * 2)
    return button
  }

  private static let titledPadding: CGFloat = 16
  private static let titledGap: CGFloat = 8

  /// Icon and title side by side; UIKit puts the bar's glass behind it.
  private func titledButton(id: String, image: UIImage, title: String, style raw: Any?, menu: UIMenu?) -> UIButton {
    let style = raw as? [String: Any]
    let size = (style?["size"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 17
    let font = style == nil
      ? UIFont.systemFont(ofSize: size, weight: .semibold)
      : NativeIconRenderer.shared.textFont(family: style?["family"] as? String, size: size, weight: (style?["weight"] as? NSNumber)?.intValue)
    let color = (style?["color"] as? NSNumber).map(UIColor.init(argb:)) ?? .label

    var config = UIButton.Configuration.plain()
    config.image = image
    config.imagePlacement = .leading
    config.imagePadding = Self.titledGap
    config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: Self.titledPadding, bottom: 0, trailing: Self.titledPadding)
    config.baseForegroundColor = color
    config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: font, .foregroundColor: color]))
    config.titleLineBreakMode = .byTruncatingTail

    let button = UIButton(configuration: config)
    button.accessibilityLabel = title
    if let menu {
      button.menu = menu
      button.showsMenuAsPrimaryAction = true
    } else {
      button.addAction(UIAction { [weak self] _ in self?.onEvent?("navItemPressed", ["id": id]) }, for: .primaryActionTriggered)
    }
    button.sizeToFit()
    button.frame.size.height = 44
    return button
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

/// A plain title and subtitle in the app's fonts and colours.
@available(iOS 26.0, *)
final class BarTitleView: UIView {
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let stack = UIStackView()
  private var leadingAligned = false

  /// Needs our own view: a text style, or leading alignment.
  static func isCustom(_ spec: [String: Any]) -> Bool {
    (spec["capsule"] as? Bool) != true
      && ((spec["alignment"] as? String) == "leading" || spec["style"] is [String: Any] || spec["subtitleStyle"] is [String: Any])
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    stack.axis = .vertical
    stack.spacing = 0
    stack.addArrangedSubview(titleLabel)
    stack.addArrangedSubview(subtitleLabel)
    // Long titles truncate in whatever space the bar leaves them.
    for label in [titleLabel, subtitleLabel] {
      label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      label.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      heightAnchor.constraint(equalToConstant: 44),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .header
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(_ spec: [String: Any]) {
    leadingAligned = (spec["alignment"] as? String) == "leading"
    let alignment: NSTextAlignment = leadingAligned ? .natural : .center
    stack.alignment = leadingAligned ? .leading : .center
    Self.apply(spec["style"], to: titleLabel, text: spec["title"] as? String,
      fallback: .systemFont(ofSize: 17, weight: .semibold), color: .label)
    Self.apply(spec["subtitleStyle"], to: subtitleLabel, text: spec["subtitle"] as? String,
      fallback: .systemFont(ofSize: 12), color: .secondaryLabel)
    titleLabel.textAlignment = alignment
    subtitleLabel.textAlignment = alignment
    subtitleLabel.isHidden = (spec["subtitle"] as? String)?.isEmpty ?? true
    accessibilityLabel = [titleLabel.text, subtitleLabel.text].compactMap { $0 }.joined(separator: ", ")
    invalidateIntrinsicContentSize()
  }

  static func apply(_ raw: Any?, to label: UILabel, text: String?, fallback: UIFont, color: UIColor) {
    let style = raw as? [String: Any]
    let size = (style?["size"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? fallback.pointSize
    let font = style == nil
      ? fallback
      : NativeIconRenderer.shared.textFont(family: style?["family"] as? String, size: size, weight: (style?["weight"] as? NSNumber)?.intValue)
    label.font = font
    label.textColor = (style?["color"] as? NSNumber).map(UIColor.init(argb:)) ?? color
    label.lineBreakMode = .byTruncatingTail
    if let height = (style?["height"] as? NSNumber).map({ CGFloat($0.doubleValue) }) {
      let paragraph = NSMutableParagraphStyle()
      paragraph.minimumLineHeight = size * height
      paragraph.maximumLineHeight = size * height
      paragraph.lineBreakMode = .byTruncatingTail
      label.attributedText = NSAttributedString(string: text ?? "", attributes: [
        .font: font, .foregroundColor: label.textColor as Any, .paragraphStyle: paragraph,
        .baselineOffset: (size * height - font.lineHeight) / 4,
      ])
    } else {
      label.text = text
    }
  }

  /// Leading titles take all the room the bar gives them, so they start at
  /// the leading edge; centred ones size to their text.
  override var intrinsicContentSize: CGSize {
    guard !leadingAligned else { return CGSize(width: UIView.layoutFittingExpandedSize.width, height: 44) }
    let fitted = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    return CGSize(width: fitted.width, height: 44)
  }
}

/// Channel-header style title: an icon beside a bold title and a secondary
/// subtitle, as the custom view of a glass bar button item.
@available(iOS 26.0, *)
final class TitleCapsuleControl: UIControl {
  private let iconView = UIImageView()
  private let accessoryView = UIImageView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let stack = UIStackView()
  private var stackLeading: NSLayoutConstraint?
  private var iconWidth: NSLayoutConstraint?

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
    accessoryView.contentMode = .scaleAspectFit
    accessoryView.tintColor = .label
    accessoryView.preferredSymbolConfiguration = .init(pointSize: 13, weight: .semibold)
    stack.addArrangedSubview(iconView)
    stack.addArrangedSubview(text)
    stack.addArrangedSubview(accessoryView)
    stack.setCustomSpacing(6, after: text)
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 10
    stack.isUserInteractionEnabled = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    let stackLeading = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
    self.stackLeading = stackLeading
    iconWidth = iconView.widthAnchor.constraint(equalToConstant: 18)
    iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor).isActive = true
    NSLayoutConstraint.activate([
      stackLeading,
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      heightAnchor.constraint(equalToConstant: 44),
    ])
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(_ spec: [String: Any]) {
    BarTitleView.apply(spec["style"], to: titleLabel, text: spec["title"] as? String,
      fallback: .systemFont(ofSize: 16, weight: .bold), color: .label)
    BarTitleView.apply(spec["subtitleStyle"], to: subtitleLabel, text: spec["subtitle"] as? String,
      fallback: .systemFont(ofSize: 12, weight: .regular), color: .secondaryLabel)
    subtitleLabel.isHidden = (spec["subtitle"] as? String)?.isEmpty ?? true
    let iconSize = (spec["iconSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 18
    iconView.image = NativeIconDescriptor(spec["icon"]).flatMap {
      NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? nil : iconSize)
    }
    iconView.isHidden = iconView.image == nil
    // Text alone needs the capsule's own padding; a glyph sits closer, and an
    // avatar-sized icon is concentric with the capsule, 2 pt from its edge.
    let largeIcon = !iconView.isHidden && iconSize >= 32
    stackLeading?.constant = iconView.isHidden ? 12 : largeIcon ? 2 : 4
    stack.spacing = largeIcon ? 8 : 10
    iconWidth?.constant = iconSize
    iconWidth?.isActive = largeIcon
    accessoryView.image = NativeIconDescriptor(spec["accessory"]).flatMap {
      NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? nil : 16)
    }
    accessoryView.isHidden = accessoryView.image == nil
    accessibilityLabel = [titleLabel.text, subtitleLabel.text].compactMap { $0 }.joined(separator: ", ")
  }

  override var isHighlighted: Bool {
    didSet { stack.alpha = isHighlighted ? 0.5 : 1 }
  }
}

/// A padded bar button in its own round Liquid Glass. UIKit's shared bar
/// glass pads a custom view sideways, so a padded item hides it and carries
/// glass exactly its own size.
@available(iOS 26.0, *)
final class PaddedGlassButton: UIView {
  private let glass: UIVisualEffectView = {
    let effect = UIGlassEffect(style: .regular)
    effect.isInteractive = true
    return UIVisualEffectView(effect: effect)
  }()

  init(_ button: UIButton) {
    let size = button.frame.size
    super.init(frame: CGRect(origin: .zero, size: size))
    glass.frame = bounds
    glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    glass.clipsToBounds = true
    glass.layer.cornerRadius = min(size.width, size.height) / 2
    glass.layer.cornerCurve = .continuous
    addSubview(glass)
    button.frame = glass.contentView.bounds
    button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    glass.contentView.addSubview(button)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var intrinsicContentSize: CGSize { bounds.size }
}

/// A capsule title that spans the space between the bar's items: its own
/// Liquid Glass (a bar button item's comes from UIKit), and an expanded
/// intrinsic width that UIKit clamps to what the items leave.
@available(iOS 26.0, *)
final class FillingTitleCapsule: UIView {
  private let glass: UIVisualEffectView = {
    let effect = UIGlassEffect(style: .regular)
    effect.isInteractive = true
    return UIVisualEffectView(effect: effect)
  }()

  init(_ capsule: TitleCapsuleControl) {
    super.init(frame: .zero)
    glass.translatesAutoresizingMaskIntoConstraints = false
    glass.clipsToBounds = true
    glass.layer.cornerRadius = 22
    glass.layer.cornerCurve = .continuous
    addSubview(glass)
    capsule.translatesAutoresizingMaskIntoConstraints = false
    glass.contentView.addSubview(capsule)
    NSLayoutConstraint.activate([
      glass.leadingAnchor.constraint(equalTo: leadingAnchor),
      glass.trailingAnchor.constraint(equalTo: trailingAnchor),
      glass.topAnchor.constraint(equalTo: topAnchor),
      glass.bottomAnchor.constraint(equalTo: bottomAnchor),
      capsule.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
      capsule.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
      capsule.centerYAnchor.constraint(equalTo: glass.contentView.centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.layoutFittingExpandedSize.width, height: 44)
  }
}
