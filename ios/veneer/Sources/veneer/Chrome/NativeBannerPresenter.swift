import UIKit

/// In-app notification banners (`showNativeBanner`).
///
/// Each banner lives in a window of its own above the app's (and its native
/// sheets'), so it covers UIKit chrome that Flutter content can't. The window
/// passes every touch outside the banner through, never becomes key (the
/// keyboard and first responder stay put) and mirrors the scene's status bar
/// style. One banner shows at a time: a new one replaces it, the old one
/// sliding away and reporting `bannerDismissed` to the engine that showed it.
@available(iOS 26.0, *)
final class NativeBannerPresenter {
  static let shared = NativeBannerPresenter()

  private final class Entry {
    let id: Int
    let view: NativeBannerView
    let duration: TimeInterval
    let notify: (String, [String: Any]) -> Void
    var timer: Timer?
    var tapped = false

    init(id: Int, view: NativeBannerView, duration: TimeInterval, notify: @escaping (String, [String: Any]) -> Void) {
      self.id = id
      self.view = view
      self.duration = duration
      self.notify = notify
    }
  }

  private var window: BannerWindow?
  private var current: Entry?
  private var leaving = 0

  /// `args`: `{id, title, subtitle?, body?, trailing?, icon?, badge?,
  /// bodyMaxLines, duration, semanticLabel?, …NativeBannerStyle}`.
  func show(
    _ args: [String: Any], from controller: UIViewController?,
    notify: @escaping (String, [String: Any]) -> Void
  ) -> Bool {
    guard let id = (args["id"] as? NSNumber)?.intValue,
      let scene = controller?.view.window?.windowScene ?? Self.foregroundScene
    else { return false }
    if let current { dismiss(current) }

    let window = window(in: scene)
    let root = window.rootViewController!.view!
    let view = NativeBannerView(args)
    root.addSubview(view)
    let margin = { (key: String) in CGFloat((args[key] as? NSNumber)?.doubleValue ?? 16) }
    let guide = root.safeAreaLayoutGuide
    let fill = view.widthAnchor.constraint(
      equalTo: guide.widthAnchor, constant: -(margin("marginLeft") + margin("marginRight")))
    fill.priority = .defaultHigh
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: guide.topAnchor, constant: CGFloat((args["marginTop"] as? NSNumber)?.doubleValue ?? 8)),
      view.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: margin("marginLeft")),
      view.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -margin("marginRight")),
      view.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
      view.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maximumWidth),
      fill,
    ])
    root.layoutIfNeeded()

    let entry = Entry(
      id: id, view: view, duration: (args["duration"] as? NSNumber)?.doubleValue ?? 5, notify: notify)
    current = entry
    view.onTap = { [weak self, weak entry] in
      guard let self, let entry, !entry.tapped else { return }
      entry.tapped = true
      entry.notify("bannerTapped", ["id": entry.id])
      self.dismiss(entry)
    }
    view.onSwipedAway = { [weak self, weak entry] in
      guard let self, let entry else { return }
      self.dismiss(entry, swiped: true)
    }
    view.onHeld = { [weak self, weak entry] held in
      guard let self, let entry else { return }
      if held { entry.timer?.invalidate() } else { self.schedule(entry) }
    }

    view.transform = CGAffineTransform(translationX: 0, y: -view.frame.maxY - Self.offscreenSlack)
    UIView.animate(springDuration: 0.45, bounce: 0.12) { view.transform = .identity }
    schedule(entry)
    UIAccessibility.post(notification: .announcement, argument: view.accessibilityLabel)
    return true
  }

  func hide() {
    if let current { dismiss(current) }
  }

  private func schedule(_ entry: Entry) {
    entry.timer?.invalidate()
    entry.timer = Timer.scheduledTimer(withTimeInterval: entry.duration, repeats: false) { [weak self, weak entry] _ in
      guard let self, let entry else { return }
      self.dismiss(entry)
    }
  }

  private func dismiss(_ entry: Entry, swiped: Bool = false) {
    entry.timer?.invalidate()
    entry.timer = nil
    if current === entry { current = nil }
    let view = entry.view
    view.onTap = nil
    view.onSwipedAway = nil
    view.onHeld = nil
    view.isUserInteractionEnabled = false
    leaving += 1
    UIView.animate(
      withDuration: swiped ? 0.2 : 0.28, delay: 0, options: [.curveEaseIn, .beginFromCurrentState],
      animations: { view.transform = CGAffineTransform(translationX: 0, y: -view.frame.maxY - Self.offscreenSlack) },
      completion: { [weak self] _ in
        view.removeFromSuperview()
        entry.notify("bannerDismissed", ["id": entry.id])
        guard let self else { return }
        self.leaving -= 1
        if self.current == nil, self.leaving == 0 { self.window?.isHidden = true }
      })
  }

  private func window(in scene: UIWindowScene) -> BannerWindow {
    let window: BannerWindow
    if let existing = self.window, existing.windowScene === scene {
      window = existing
    } else {
      self.window?.isHidden = true
      window = BannerWindow(windowScene: scene)
      window.windowLevel = .alert + 1
      window.backgroundColor = .clear
      window.rootViewController = BannerRootController()
      self.window = window
    }
    let root = window.rootViewController as! BannerRootController
    root.statusBarStyle = scene.statusBarManager?.statusBarStyle ?? .default
    root.statusBarHidden = scene.statusBarManager?.isStatusBarHidden ?? false
    root.setNeedsStatusBarAppearanceUpdate()
    window.isHidden = false
    return window
  }

  private static let maximumWidth: CGFloat = 600
  private static let offscreenSlack: CGFloat = 24

  private static var foregroundScene: UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
  }
}

/// Lets every touch outside a banner reach the app's windows below.
@available(iOS 26.0, *)
private final class BannerWindow: UIWindow {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === rootViewController?.view ? nil : hit
  }

  override var canBecomeKey: Bool { false }
}

@available(iOS 26.0, *)
private final class BannerRootController: UIViewController {
  var statusBarStyle: UIStatusBarStyle = .default
  var statusBarHidden = false

  override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }
  override var prefersStatusBarHidden: Bool { statusBarHidden }

  override func loadView() {
    view = UIView()
    view.backgroundColor = .clear
  }
}

/// The banner: an icon in a circle (badge on its corner), title with a
/// trailing label, subtitle and body, on Liquid Glass with a border and a
/// shadow. Tap to open, swipe up to dismiss; touches hold its timer.
@available(iOS 26.0, *)
final class NativeBannerView: UIView {
  var onTap: (() -> Void)?
  var onSwipedAway: (() -> Void)?
  var onHeld: ((Bool) -> Void)?

  private let glass = UIVisualEffectView()
  private let radius: CGFloat
  private let shadowSpread: CGFloat

  init(_ args: [String: Any]) {
    let number = { (key: String, fallback: CGFloat) in
      (args[key] as? NSNumber).map { CGFloat($0.doubleValue) } ?? fallback
    }
    let color = { (key: String) in (args[key] as? NSNumber).map(UIColor.init(argb:)) }
    radius = number("cornerRadius", 24)
    shadowSpread = number("shadowSpread", -4)
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    overrideUserInterfaceStyle = (args["dark"] as? Bool) == true ? .dark : .light

    layer.shadowColor = (color("shadowColor") ?? UIColor.black.withAlphaComponent(0.08)).cgColor
    layer.shadowOpacity = 1
    layer.shadowRadius = number("shadowBlur", 16) / 2
    layer.shadowOffset = CGSize(width: 0, height: number("shadowOffsetY", 8))

    let effect = UIGlassEffect(style: .regular)
    effect.tintColor = color("tint")
    effect.isInteractive = true
    glass.effect = effect
    glass.cornerConfiguration = .corners(radius: .fixed(radius))
    glass.translatesAutoresizingMaskIntoConstraints = false
    addSubview(glass)

    let border = UIView()
    border.translatesAutoresizingMaskIntoConstraints = false
    border.isUserInteractionEnabled = false
    border.layer.cornerRadius = radius
    border.layer.cornerCurve = .continuous
    border.layer.borderWidth = number("borderWidth", 1)
    border.layer.borderColor = (color("borderColor") ?? UIColor.separator).cgColor
    addSubview(border)

    let row = UIStackView(arrangedSubviews: [Self.media(args, number: number, color: color), Self.text(args, number: number)])
    row.axis = .horizontal
    row.alignment = .center
    row.spacing = number("iconGap", 12)
    row.translatesAutoresizingMaskIntoConstraints = false
    glass.contentView.addSubview(row)

    let padding = number("horizontalPadding", 16)
    NSLayoutConstraint.activate([
      glass.topAnchor.constraint(equalTo: topAnchor),
      glass.bottomAnchor.constraint(equalTo: bottomAnchor),
      glass.leadingAnchor.constraint(equalTo: leadingAnchor),
      glass.trailingAnchor.constraint(equalTo: trailingAnchor),
      border.topAnchor.constraint(equalTo: topAnchor),
      border.bottomAnchor.constraint(equalTo: bottomAnchor),
      border.leadingAnchor.constraint(equalTo: leadingAnchor),
      border.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
      row.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
      row.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: padding),
      row.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -padding),
    ])

    isAccessibilityElement = true
    accessibilityTraits = .button
    accessibilityLabel =
      (args["semanticLabel"] as? String)
      ?? ["title", "subtitle", "body", "trailing"].compactMap { args[$0] as? String }.filter { !$0.isEmpty }
      .joined(separator: ", ")

    let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
    let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
    tap.require(toFail: pan)
    addGestureRecognizer(tap)
    addGestureRecognizer(pan)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layoutSubviews() {
    super.layoutSubviews()
    let inset = -shadowSpread
    layer.shadowPath =
      UIBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerRadius: max(0, radius - inset)).cgPath
  }

  override func accessibilityActivate() -> Bool {
    onTap?()
    return true
  }

  @objc private func tapped() { onTap?() }

  @objc private func panned(_ pan: UIPanGestureRecognizer) {
    let y = pan.translation(in: superview).y
    switch pan.state {
    case .began:
      onHeld?(true)
    case .changed:
      transform = CGAffineTransform(translationX: 0, y: y < 0 ? y : y / (1 + y / 40))
    case .ended, .cancelled, .failed:
      let velocity = pan.velocity(in: superview).y
      if pan.state == .ended, y < -bounds.height / 3 || velocity < -400 {
        onSwipedAway?()
      } else {
        UIView.animate(springDuration: 0.35, bounce: 0.2) { self.transform = .identity }
        onHeld?(false)
      }
    default:
      break
    }
  }

  // MARK: - Content

  private static func media(
    _ args: [String: Any], number: (String, CGFloat) -> CGFloat, color: (String) -> UIColor?
  ) -> UIView {
    let box = number("iconBoxSize", 40)
    let circle = UIView()
    circle.translatesAutoresizingMaskIntoConstraints = false
    circle.backgroundColor = color("iconBackground")
    circle.layer.cornerRadius = box / 2
    NSLayoutConstraint.activate([
      circle.widthAnchor.constraint(equalToConstant: box),
      circle.heightAnchor.constraint(equalToConstant: box),
    ])
    if let icon = NativeIconDescriptor(args["icon"]) {
      let size = number("iconSize", 24)
      let image = UIImageView(image: NativeIconRenderer.shared.image(for: icon, pointSize: size))
      image.contentMode = .scaleAspectFit
      image.tintColor = .label
      image.translatesAutoresizingMaskIntoConstraints = false
      circle.addSubview(image)
      NSLayoutConstraint.activate([
        image.widthAnchor.constraint(equalToConstant: size),
        image.heightAnchor.constraint(equalToConstant: size),
        image.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
        image.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
      ])
    }
    if let badge = NativeIconDescriptor(args["badge"]) {
      let size = number("badgeSize", 16)
      let padding = number("badgePadding", 2)
      let offset = number("badgeOffset", -4)
      let chip = UIView()
      chip.translatesAutoresizingMaskIntoConstraints = false
      chip.backgroundColor = color("badgeBackground") ?? .systemBackground
      chip.layer.cornerRadius = size / 2 + padding
      chip.layer.shadowColor = (color("badgeShadowColor") ?? UIColor.black.withAlphaComponent(0.1)).cgColor
      chip.layer.shadowOpacity = 1
      chip.layer.shadowRadius = 1.5
      chip.layer.shadowOffset = CGSize(width: 0, height: 1)
      let image = UIImageView(image: NativeIconRenderer.shared.image(for: badge, pointSize: size))
      image.contentMode = .scaleAspectFit
      image.tintColor = color("badgeColor") ?? .systemRed
      image.translatesAutoresizingMaskIntoConstraints = false
      chip.addSubview(image)
      circle.addSubview(chip)
      NSLayoutConstraint.activate([
        image.widthAnchor.constraint(equalToConstant: size),
        image.heightAnchor.constraint(equalToConstant: size),
        image.topAnchor.constraint(equalTo: chip.topAnchor, constant: padding),
        image.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -padding),
        image.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: padding),
        image.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -padding),
        chip.topAnchor.constraint(equalTo: circle.topAnchor, constant: offset),
        chip.trailingAnchor.constraint(equalTo: circle.trailingAnchor, constant: -offset),
      ])
    }
    return circle
  }

  private static func text(_ args: [String: Any], number: (String, CGFloat) -> CGFloat) -> UIView {
    let title = label(args["title"] as? String ?? "", style: args["titleStyle"], weight: 500, lines: 1)
    title.setContentHuggingPriority(.defaultLow, for: .horizontal)
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    var heading: [UIView] = [title]
    if let trailing = args["trailing"] as? String, !trailing.isEmpty {
      let time = label(trailing, style: args["trailingStyle"], weight: 400, lines: 1, alignment: .right)
      time.setContentHuggingPriority(.required, for: .horizontal)
      time.setContentCompressionResistancePriority(.required, for: .horizontal)
      heading.append(time)
    }
    let headingRow = UIStackView(arrangedSubviews: heading)
    headingRow.axis = .horizontal
    headingRow.alignment = .firstBaseline
    headingRow.spacing = number("trailingGap", 12)

    let column = UIStackView(arrangedSubviews: [headingRow])
    column.axis = .vertical
    column.alignment = .fill
    column.isLayoutMarginsRelativeArrangement = true
    let vertical = number("verticalPadding", 16)
    column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: vertical, leading: 0, bottom: vertical, trailing: 0)
    if let subtitle = args["subtitle"] as? String, !subtitle.isEmpty {
      let view = label(subtitle, style: args["subtitleStyle"], weight: 500, lines: 1)
      column.addArrangedSubview(view)
      column.setCustomSpacing(number("subtitleGap", 8), after: view)
    }
    if let body = args["body"] as? String, !body.isEmpty {
      let lines = (args["bodyMaxLines"] as? NSNumber)?.intValue ?? 3
      column.addArrangedSubview(label(body, style: args["bodyStyle"], weight: 400, lines: lines))
    }
    return column
  }

  private static func label(
    _ text: String, style raw: Any?, weight: Int, lines: Int, alignment: NSTextAlignment = .natural
  ) -> UILabel {
    let style = raw as? [String: Any]
    let size = (style?["size"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 15
    let font = NativeIconRenderer.shared.textFont(
      family: style?["family"] as? String, size: size, weight: (style?["weight"] as? NSNumber)?.intValue ?? weight)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: (style?["color"] as? NSNumber).map(UIColor.init(argb:)) ?? UIColor.label,
      .paragraphStyle: paragraph,
    ]
    if let height = (style?["height"] as? NSNumber).map({ CGFloat($0.doubleValue) }) {
      let lineHeight = (size * height).rounded()
      paragraph.minimumLineHeight = lineHeight
      paragraph.maximumLineHeight = lineHeight
      attributes[.baselineOffset] = (lineHeight - font.lineHeight) / 4
    }
    let label = UILabel()
    label.attributedText = NSAttributedString(string: text, attributes: attributes)
    label.numberOfLines = lines
    label.lineBreakMode = .byTruncatingTail
    label.adjustsFontForContentSizeCategory = false
    return label
  }
}
