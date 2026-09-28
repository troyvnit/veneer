import UIKit

/// A native prompt composer, as in assistant apps: one Liquid Glass capsule
/// that grows into a card for longer prompts, with glass side buttons that
/// split off it for a live session (voice).
///
/// Single line (48 pt): `[+  Placeholder…        🎙  (◉)]` — leading button
/// centred 24 pt from the edge, text from 50 pt, inline actions every 48 pt,
/// and a 32 pt filled circle centred 24 pt from the trailing edge: the
/// primary action (e.g. voice) while empty, send once there's something to
/// send.
///
/// Multi-line — the text wraps at the inline width, has a line break, or
/// there are attachments: attachments on top, the text full width below,
/// and the buttons on a row along the bottom; corner radius 24.
///
/// Side actions: 48 pt glass circles 10 pt apart at the trailing edge. They
/// materialize out of the capsule's end while it narrows (all glass shares a
/// `UIGlassContainerEffect`, so they separate like liquid), and the inline
/// actions fade out.
///
/// Placement: idle, the capsule sits concentric with the display's bottom
/// corners (inset by the home indicator's safe area + 4 pt on all three
/// sides), or 9 pt above a tab bar with 20 pt margins. Focused, it widens to
/// 12 pt margins, 12 pt above the keyboard, inside the keyboard's animation.
@available(iOS 26.0, *)
final class NativePromptComposerView: ComposerBaseView {
  override class var style: String { "prompt" }

  enum Metrics {
    static let row: CGFloat = 48
    static let focusedMargin: CGFloat = 12
    static let keyboardGap: CGFloat = 12
    static let tabBarMargin: CGFloat = 20
    static let tabBarGap: CGFloat = 9
    /// Past the home indicator's safe area, idle: ≈ concentric with the
    /// display corners (38 pt on Face ID iPhones).
    static let idleExtraInset: CGFloat = 4
    /// Idle inset on devices without a home indicator.
    static let flatInset: CGFloat = 12
    static let sideSpacing: CGFloat = 10
    static let edgeCenter: CGFloat = 24
    static let actionSpacing: CGFloat = 48
    static let primary: CGFloat = 32
    static let textLeading: CGFloat = 50
    static let textInset: CGFloat = 18
    static let textVerticalInset: CGFloat = 13
    /// Row height below the last text line in the multi-line layout.
    static let multiRowExtra: CGFloat = 32
    static let symbolSize: CGFloat = 20
    static let imageSize: CGFloat = 22
    static let primarySymbolSize: CGFloat = 15
    static let primaryImageSize: CGFloat = 18
    static let cornerRadius: CGFloat = 24
    static let attachmentTop: CGFloat = 12
    static let attachmentHeight: CGFloat = 60
    /// Glass closer than this merges (`UIGlassContainerEffect.spacing`);
    /// under the side spacing, so buttons at rest stand apart.
    static let glassMergeDistance: CGFloat = 8
  }

  private let glassContainer: UIVisualEffectView = {
    let effect = UIGlassContainerEffect()
    effect.spacing = Metrics.glassMergeDistance
    return UIVisualEffectView(effect: effect)
  }()
  private let capsule = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
  private let leadingButton = UIButton(configuration: .plain())
  private var actionButtons: [UIButton] = []
  private let primaryButton = UIButton(configuration: .filled())
  private let sendSpinner = UIActivityIndicatorView(style: .medium)
  private let attachmentStrip = AttachmentStripView()
  private var sideButtons: [SideGlassButton] = []

  private var leadingSpec: [String: Any]?
  private var primarySpec: [String: Any]?
  private var stopSpec: [String: Any]?
  private var sendEnabled = true
  private var sendBusy = false
  private var sendIcon: Any?
  private var actionSpecs: NSArray = []
  private var sideSpecs: NSArray = []
  private(set) var sideShown = false
  private var attachmentIds: [String] = []
  /// The primary circle's current face, so content changes only swap it
  /// when it actually changes (and the symbol replace effect runs once).
  private var primaryFace: String?

  required init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(glassContainer)
    capsule.cornerConfiguration = .capsule(maximumRadius: Metrics.cornerRadius)
    glassContainer.contentView.addSubview(capsule)

    textView.textContainerInset = UIEdgeInsets(
      top: Metrics.textVerticalInset, left: 0, bottom: Metrics.textVerticalInset, right: 0)

    leadingButton.configuration?.baseForegroundColor = .label
    leadingButton.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: Metrics.symbolSize, weight: .regular)
    leadingButton.addAction(UIAction { [weak self] _ in self?.emitButton("leading") }, for: .touchUpInside)

    primaryButton.configuration?.cornerStyle = .capsule
    primaryButton.configuration?.contentInsets = .zero
    primaryButton.configuration?.preferredSymbolConfigurationForImage = .init(
      pointSize: Metrics.primarySymbolSize, weight: .semibold)
    primaryButton.configuration?.symbolContentTransition = UISymbolContentTransition(ReplaceSymbolEffect.replace)
    primaryButton.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .touchUpInside)

    attachmentStrip.onRemove = { [weak self] id in
      self?.onEvent?("composerAttachmentRemoved", ["id": id])
    }

    sendSpinner.hidesWhenStopped = true
    sendSpinner.isUserInteractionEnabled = false
    for v in [attachmentStrip, textView, leadingButton, primaryButton, sendSpinner] as [UIView] {
      capsule.contentView.addSubview(v)
    }
    recordingBar.edgeCenter = Metrics.edgeCenter
    recordingBar.buttonSize = Metrics.primary
    recordingBar.alpha = 0
    recordingBar.isUserInteractionEnabled = false
    capsule.contentView.addSubview(recordingBar)
    // Tapping anywhere on the capsule focuses it, like a text field.
    capsule.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusFromTap)))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: - Configuration

  /// `{leading: button?, actions: [button], primary: button?, stop: button?,
  ///   sendIcon, sendEnabled, sendBusy, editable, side: [button + prominent],
  ///   sideShown, attachments: [{id, title, subtitle, thumbnail, loading}]}`,
  ///   button = `{id, icon, title, menu?}`.
  override func configure(_ args: [String: Any]) -> Bool {
    var animate = false

    let editable = (args["editable"] as? Bool) ?? true
    if textView.isEditable != editable {
      if !editable { unfocus() }
      textView.isEditable = editable
      textView.isSelectable = editable
    }
    let stop = args["stop"] as? [String: Any]
    if (stop == nil) != (stopSpec == nil) { animate = true }
    stopSpec = stop
    sendEnabled = (args["sendEnabled"] as? Bool) ?? true
    sendBusy = (args["sendBusy"] as? Bool) ?? false

    leadingSpec = args["leading"] as? [String: Any]
    leadingButton.isHidden = leadingSpec == nil
    leadingButton.configuration?.image = leadingSpec.flatMap { buttonImage($0["icon"], imageSize: Metrics.imageSize) }
    leadingButton.accessibilityLabel = leadingSpec?["title"] as? String
    attachMenu(leadingSpec, to: leadingButton, id: "leading")

    let actions = (args["actions"] as? [[String: Any]]) ?? []
    if actionSpecs != actions as NSArray {
      if actionSpecs.count != actions.count { animate = true }
      actionSpecs = actions as NSArray
      actionButtons.forEach { $0.removeFromSuperview() }
      actionButtons = actions.map { spec in
        let b = UIButton(configuration: .plain())
        b.configuration?.baseForegroundColor = .label
        b.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: Metrics.symbolSize, weight: .regular)
        b.configuration?.image = buttonImage(spec["icon"], imageSize: Metrics.imageSize)
        b.accessibilityLabel = spec["title"] as? String
        let id = spec["id"] as? String ?? ""
        b.addAction(UIAction { [weak self] _ in self?.emitButton(id) }, for: .touchUpInside)
        attachMenu(spec, to: b, id: id)
        b.alpha = sideShown ? 0 : 1
        capsule.contentView.insertSubview(b, belowSubview: primaryButton)
        return b
      }
    }

    primarySpec = args["primary"] as? [String: Any]
    sendIcon = args["sendIcon"]
    primaryFace = nil  // icons may have changed

    let side = (args["side"] as? [[String: Any]]) ?? []
    if sideSpecs != side as NSArray {
      if sideSpecs.count != side.count {
        sideButtons.forEach { $0.removeFromSuperview() }
        sideButtons = side.map { _ in
          let b = SideGlassButton()
          b.button.addAction(UIAction { [weak self, weak b] _ in
            guard let self, let b else { return }
            self.emitButton(b.id)
          }, for: .touchUpInside)
          glassContainer.contentView.addSubview(b)
          // Start tucked into the capsule's trailing end.
          b.frame = CGRect(x: max(0, capsule.frame.maxX - Metrics.row), y: max(0, bounds.height - Metrics.row), width: Metrics.row, height: Metrics.row)
          return b
        }
        sideShown = false  // new buttons start tucked in, then come out
        animate = true
      }
      for (b, spec) in zip(sideButtons, side) { b.configure(spec, animated: window != nil) }
      sideSpecs = side as NSArray
    }
    let shown = ((args["sideShown"] as? Bool) ?? false) && !sideButtons.isEmpty
    if shown != sideShown {
      sideShown = shown
      animate = true
    }

    let attachments = (args["attachments"] as? [[String: Any]]) ?? []
    let ids = attachments.map { $0["id"] as? String ?? "" }
    if ids != attachmentIds { animate = true }
    attachmentIds = ids
    attachmentStrip.update(attachments)

    if !animate { applySideState() }
    return animate
  }

  private func buttonImage(_ raw: Any?, imageSize: CGFloat) -> UIImage? {
    guard let d = NativeIconDescriptor(raw) else { return nil }
    // Symbols stay unconfigured: the button's symbol configuration sizes them.
    return NativeIconRenderer.shared.image(for: d, pointSize: d.isSymbol ? nil : imageSize)
  }

  @objc private func focusFromTap() {
    guard !isRecording else { return }
    if !isEditingText, textView.isEditable { focus() }
  }

  private func primaryTapped() {
    if let id = stopSpec?["id"] as? String {
      emitButton(id)
    } else if canSend {
      send()
    } else if !hasContent, let id = primarySpec?["id"] as? String {
      emitButton(id)
    }
  }

  // MARK: - Content

  private var hasContent: Bool { hasText || !attachmentIds.isEmpty }

  override var canSend: Bool { hasContent && sendEnabled && !sendBusy && stopSpec == nil }

  private var primaryVisible: Bool { !sideShown || hasContent || stopSpec != nil }

  override func contentChanged() {
    let sending = hasContent || primarySpec == nil
    let face =
      stopSpec != nil ? "stop" : sendBusy && hasContent ? "busy" : sending ? "send:\(canSend)" : "primary"
    guard face != primaryFace else { return }
    primaryFace = face
    var config = primaryButton.configuration
    switch face {
    case "stop":
      config?.image = buttonImage(stopSpec?["icon"], imageSize: Metrics.primaryImageSize) ?? UIImage(systemName: "stop.fill")
      config?.baseBackgroundColor = accent
      config?.baseForegroundColor = .white
      primaryButton.accessibilityLabel = stopSpec?["title"] as? String ?? "Stop"
    case "busy":
      config?.image = nil
      config?.baseBackgroundColor = .tertiarySystemFill
      config?.baseForegroundColor = .tertiaryLabel
      primaryButton.accessibilityLabel = "Send"
    case "primary":
      config?.image = buttonImage(primarySpec?["icon"], imageSize: Metrics.primaryImageSize)
      config?.baseBackgroundColor = accent
      config?.baseForegroundColor = .white
      primaryButton.accessibilityLabel = primarySpec?["title"] as? String
    default:
      config?.image = buttonImage(sendIcon, imageSize: Metrics.primaryImageSize) ?? UIImage(systemName: "arrow.up")
      config?.baseBackgroundColor = canSend ? accent : .tertiarySystemFill
      config?.baseForegroundColor = canSend ? .white : .tertiaryLabel
      primaryButton.accessibilityLabel = "Send"
    }
    primaryButton.configuration = config
    primaryButton.isEnabled = face == "stop" || canSend || face == "primary"
    if face == "busy" { sendSpinner.startAnimating() } else { sendSpinner.stopAnimating() }
  }

  override func textDidChangeLayout() {
    // Wrapping, a line break, or the send circle appearing mid-session can
    // switch layouts; everything moves together on one spring.
    if abs(bounds.height - preferredHeight(width: bounds.width)) > 0.5 || layoutModeChanged {
      animateContentLayout()
    } else {
      setNeedsLayout()
    }
  }

  private var laidOutMultiline: Bool?
  private var laidOutPrimaryVisible: Bool?
  private var layoutModeChanged: Bool {
    laidOutMultiline != isMultiline(capsuleWidth: capsuleWidth(for: bounds.width))
      || laidOutPrimaryVisible != primaryVisible
  }

  // MARK: - Geometry

  private var sideReserve: CGFloat {
    sideShown ? CGFloat(sideButtons.count) * (Metrics.row + Metrics.sideSpacing) : 0
  }

  func capsuleWidth(for width: CGFloat) -> CGFloat { max(Metrics.row * 2, width - sideReserve) }

  private var textLeading: CGFloat { leadingSpec == nil ? Metrics.textInset : Metrics.textLeading }

  private func inlineTextWidth(capsuleWidth: CGFloat) -> CGFloat {
    let actions = sideShown ? 0 : CGFloat(actionButtons.count) * Metrics.actionSpacing
    let primary = primaryVisible ? Metrics.row : Metrics.textInset
    return capsuleWidth - textLeading - actions - primary
  }

  private var oneLineHeight: CGFloat { max(Metrics.row, ceil(lineHeight) + 2 * Metrics.textVerticalInset) }

  /// Wraps at the inline width, contains a line break, or has attachments.
  func isMultiline(capsuleWidth: CGFloat) -> Bool {
    if isRecording { return false }
    if !attachmentIds.isEmpty || text.contains("\n") { return true }
    guard !text.isEmpty else { return false }
    let fitted = textView.sizeThatFits(
      CGSize(width: max(1, inlineTextWidth(capsuleWidth: capsuleWidth)), height: .greatestFiniteMagnitude)
    ).height
    return fitted > oneLineHeight + lineHeight / 2
  }

  private var attachmentsBlock: CGFloat {
    attachmentIds.isEmpty ? 0 : Metrics.attachmentTop + Metrics.attachmentHeight
  }

  private func multilineTextHeight(capsuleWidth: CGFloat) -> CGFloat {
    fittedTextHeight(width: capsuleWidth - 2 * Metrics.textInset, minimum: oneLineHeight)
  }

  func preferredHeight(width: CGFloat) -> CGFloat {
    let cw = capsuleWidth(for: width)
    guard isMultiline(capsuleWidth: cw) else { return Metrics.row }
    return attachmentsBlock + multilineTextHeight(capsuleWidth: cw) + Metrics.multiRowExtra
  }

  override func frame(for placement: ComposerPlacement) -> CGRect {
    let margin: CGFloat
    let bottom: CGFloat
    if isKeyboardActive || placement.keyboardTop != nil {
      margin = Metrics.focusedMargin
      bottom = placement.baseline - Metrics.keyboardGap
    } else if let tabTop = placement.tabBarTop {
      margin = Metrics.tabBarMargin
      bottom = tabTop - Metrics.tabBarGap
    } else {
      let inset = placement.safeAreaBottom > 0 ? placement.safeAreaBottom + Metrics.idleExtraInset : Metrics.flatInset
      margin = inset
      bottom = placement.bounds.height - inset
    }
    let width = placement.bounds.width - 2 * margin
    let height = preferredHeight(width: width)
    return CGRect(x: margin, y: bottom - height, width: width, height: height)
  }

  // MARK: - Layout

  override func layoutSubviews() {
    super.layoutSubviews()
    glassContainer.frame = bounds
    let w = bounds.width, h = bounds.height
    let cw = capsuleWidth(for: w)
    let multiline = isMultiline(capsuleWidth: cw)
    laidOutMultiline = multiline
    laidOutPrimaryVisible = primaryVisible
    capsule.frame = CGRect(x: 0, y: 0, width: cw, height: h)

    let rowTop = h - Metrics.row
    leadingButton.frame = CGRect(x: 0, y: rowTop, width: Metrics.row, height: Metrics.row)

    let actionsShown = !sideShown
    for (i, b) in actionButtons.enumerated() {
      let cx = cw - Metrics.edgeCenter - Metrics.actionSpacing * CGFloat(actionButtons.count - i)
      b.bounds = CGRect(x: 0, y: 0, width: Metrics.row, height: Metrics.row)
      b.center = CGPoint(x: cx, y: rowTop + Metrics.row / 2)
      b.alpha = actionsShown ? 1 : 0
      b.transform = actionsShown ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
      b.isUserInteractionEnabled = actionsShown
    }

    primaryButton.bounds = CGRect(x: 0, y: 0, width: Metrics.primary, height: Metrics.primary)
    primaryButton.center = CGPoint(x: cw - Metrics.edgeCenter, y: rowTop + Metrics.row / 2)
    primaryButton.alpha = primaryVisible ? 1 : 0
    primaryButton.transform = primaryVisible ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
    sendSpinner.center = primaryButton.center

    attachmentStrip.frame = CGRect(x: 0, y: Metrics.attachmentTop, width: cw, height: Metrics.attachmentHeight)
    attachmentStrip.alpha = attachmentIds.isEmpty ? 0 : 1

    if multiline {
      let textHeight = multilineTextHeight(capsuleWidth: cw)
      textView.frame = CGRect(x: Metrics.textInset, y: attachmentsBlock, width: cw - 2 * Metrics.textInset, height: textHeight)
      let maximum = oneLineHeight + ceil(lineHeight) * CGFloat(max(0, maxLines - 1))
      textView.isScrollEnabled = textHeight >= maximum
    } else {
      textView.frame = CGRect(x: textLeading, y: 0, width: inlineTextWidth(capsuleWidth: cw), height: Metrics.row)
      textView.isScrollEnabled = false
    }
    placeholder.frame = CGRect(x: 0, y: Metrics.textVerticalInset, width: textView.bounds.width, height: ceil(lineHeight))

    // Recording: the bar takes the row and the content fades under it.
    let recording = isRecording
    recordingBar.frame = CGRect(x: 0, y: rowTop, width: cw, height: Metrics.row)
    recordingBar.alpha = recording ? 1 : 0
    recordingBar.isUserInteractionEnabled = recording
    leadingButton.alpha = recording ? 0 : 1
    textView.alpha = recording ? 0 : 1
    if recording {
      for v in [primaryButton, attachmentStrip, sendSpinner] + actionButtons as [UIView] { v.alpha = 0 }
    }
    for v in [leadingButton, primaryButton, textView] as [UIView] { v.isUserInteractionEnabled = !recording }
    if recording { for b in actionButtons { b.isUserInteractionEnabled = false } }

    let n = CGFloat(sideButtons.count)
    for (i, b) in sideButtons.enumerated() {
      let shownX = w - (n - CGFloat(i)) * Metrics.row - (n - 1 - CGFloat(i)) * Metrics.sideSpacing
      // Tucked into the capsule's trailing end while hidden, so they grow out of it.
      let x = sideShown ? shownX : cw - Metrics.row
      b.frame = CGRect(x: x, y: rowTop, width: Metrics.row, height: Metrics.row)
    }
  }

  /// Glass materializes (or dissolves) when its effect changes inside an
  /// animation block.
  private func applySideState() {
    for b in sideButtons { b.setOn(sideShown) }
  }

  override func animateContentLayout() {
    UIView.animate(springDuration: 0.5, bounce: 0.12, initialSpringVelocity: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      self.applySideState()
      self.onNeedsLayout?()
      self.superview?.layoutIfNeeded()
      self.setNeedsLayout()
      self.layoutIfNeeded()
    }
  }
}

/// A 48 pt Liquid Glass circle beside the capsule. Prominent buttons are
/// glass tinted with the label colour (white in dark mode, black in light),
/// their glyph in the background colour.
@available(iOS 26.0, *)
final class SideGlassButton: UIVisualEffectView {
  let button = UIButton(configuration: .plain())
  private(set) var id = ""
  private var prominent = false
  private var isOn = false

  init() {
    super.init(effect: nil)
    cornerConfiguration = .capsule()
    button.configuration?.contentInsets = .zero
    button.configuration?.symbolContentTransition = UISymbolContentTransition(ReplaceSymbolEffect.replace)
    button.alpha = 0
    contentView.addSubview(button)
    isUserInteractionEnabled = false
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: SideGlassButton, _) in
      self.applyColors()
      if self.isOn { self.effect = self.glass }
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(_ spec: [String: Any], animated: Bool) {
    id = spec["id"] as? String ?? ""
    let prominent = (spec["prominent"] as? Bool) ?? false
    let changedStyle = prominent != self.prominent
    self.prominent = prominent
    var config = button.configuration
    let d = NativeIconDescriptor(spec["icon"])
    config?.image = d.flatMap { NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? nil : 22) }
    config?.preferredSymbolConfigurationForImage = .init(pointSize: prominent ? 17 : 20, weight: prominent ? .semibold : .regular)
    button.configuration = config
    applyColors()
    button.accessibilityLabel = spec["title"] as? String
    if isOn, changedStyle { effect = glass }
  }

  /// Prominent: resolved against this view's own style. Bright tinted glass
  /// switches its content to the light appearance, where dynamic colours
  /// would resolve the glyph to white on white.
  private var prominentTint: UIColor { UIColor.label.resolvedColor(with: traitCollection) }

  private func applyColors() {
    button.configuration?.baseForegroundColor =
      prominent ? UIColor.systemBackground.resolvedColor(with: traitCollection) : .label
  }

  private var glass: UIGlassEffect {
    let g = UIGlassEffect(style: .regular)
    g.isInteractive = true
    if prominent { g.tintColor = prominentTint }
    return g
  }

  func setOn(_ on: Bool) {
    guard on != isOn else { return }
    isOn = on
    effect = on ? glass : nil
    button.alpha = on ? 1 : 0
    isUserInteractionEnabled = on
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    button.frame = contentView.bounds
  }
}

/// Attachments along the top of the multi-line composer: image tiles and
/// file chips, each with a remove button. Tiles grow in and shrink out.
@available(iOS 26.0, *)
final class AttachmentStripView: UIScrollView {
  var onRemove: ((String) -> Void)?

  private var tiles: [String: AttachmentTileView] = [:]
  private var order: [String] = []
  private static let spacing: CGFloat = 8
  private static let inset: CGFloat = 12

  override init(frame: CGRect) {
    super.init(frame: frame)
    showsHorizontalScrollIndicator = false
    alwaysBounceHorizontal = true
    clipsToBounds = false
    contentInsetAdjustmentBehavior = .never
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func update(_ specs: [[String: Any]]) {
    let ids = specs.map { $0["id"] as? String ?? "" }
    for id in order where !ids.contains(id) {
      guard let tile = tiles.removeValue(forKey: id) else { continue }
      // Shrinks away in the composer's animation, then leaves.
      UIView.animate(withDuration: 0.25, animations: {
        tile.alpha = 0
        tile.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
      }, completion: { _ in tile.removeFromSuperview() })
    }
    for (spec, id) in zip(specs, ids) {
      if let tile = tiles[id] {
        tile.configure(spec)
      } else {
        let tile = AttachmentTileView(id: id)
        tile.configure(spec)
        tile.onRemove = { [weak self] in self?.onRemove?(id) }
        tile.alpha = 0
        tile.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        addSubview(tile)
        tiles[id] = tile
      }
    }
    order = ids
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    var x = Self.inset
    for id in order {
      guard let tile = tiles[id] else { continue }
      let size = CGSize(width: tile.preferredWidth, height: bounds.height)
      tile.bounds = CGRect(origin: .zero, size: size)
      tile.center = CGPoint(x: x + size.width / 2, y: size.height / 2)
      tile.alpha = 1
      tile.transform = .identity
      x += size.width + Self.spacing
    }
    contentSize = CGSize(width: x - Self.spacing + Self.inset, height: bounds.height)
  }
}

/// One attachment. Without a title it's a square image tile; with one, a chip
/// with a thumbnail, the title and a subtitle.
@available(iOS 26.0, *)
final class AttachmentTileView: UIView {
  let id: String
  var onRemove: (() -> Void)?

  private let thumbnailClip = UIView()
  private let thumbnail = UIImageView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let removeButton = ExpandedHitButton(configuration: .filled())
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let dim = UIView()
  private var isChip = false

  private static let chipThumbnail: CGFloat = 44
  private static let chipMaxWidth: CGFloat = 220
  private static let removeSize: CGFloat = 22

  init(id: String) {
    self.id = id
    super.init(frame: .zero)
    layer.cornerRadius = 16
    layer.cornerCurve = .continuous
    thumbnailClip.clipsToBounds = true
    thumbnailClip.layer.cornerCurve = .continuous
    thumbnail.clipsToBounds = true
    thumbnailClip.addSubview(thumbnail)
    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = .label
    subtitleLabel.font = .systemFont(ofSize: 13)
    subtitleLabel.textColor = .secondaryLabel
    removeButton.configuration?.cornerStyle = .capsule
    removeButton.configuration?.contentInsets = .zero
    removeButton.configuration?.image = UIImage(systemName: "xmark")
    removeButton.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: 9, weight: .bold)
    removeButton.configuration?.baseBackgroundColor = UIColor.black.withAlphaComponent(0.6)
    removeButton.configuration?.baseForegroundColor = .white
    removeButton.accessibilityLabel = "Remove"
    removeButton.addAction(UIAction { [weak self] _ in self?.onRemove?() }, for: .touchUpInside)
    dim.backgroundColor = UIColor.black.withAlphaComponent(0.35)
    dim.isUserInteractionEnabled = false
    spinner.color = .white
    spinner.hidesWhenStopped = true
    thumbnailClip.addSubview(dim)
    thumbnailClip.addSubview(spinner)
    for v in [thumbnailClip, titleLabel, subtitleLabel, removeButton] { addSubview(v) }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func configure(_ spec: [String: Any]) {
    let title = spec["title"] as? String
    let subtitle = spec["subtitle"] as? String
    isChip = !(title ?? "").isEmpty
    titleLabel.text = title
    subtitleLabel.text = subtitle
    titleLabel.isHidden = !isChip
    subtitleLabel.isHidden = !isChip || (subtitle ?? "").isEmpty
    backgroundColor = isChip ? .tertiarySystemFill : .clear
    accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")

    let side = isChip ? Self.chipThumbnail : 60
    let d = NativeIconDescriptor(spec["thumbnail"])
    if let d, d.keepsColors {
      thumbnail.image = d.isRaster
        ? NativeIconRenderer.shared.fullImage(for: d)
        : NativeIconRenderer.shared.image(for: d, pointSize: side)
      thumbnail.contentMode = .scaleAspectFill
      thumbnailClip.backgroundColor = .clear
    } else {
      thumbnail.image = d.flatMap { NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? 20 : 22) }
      thumbnail.contentMode = .center
      thumbnail.tintColor = .secondaryLabel
      thumbnailClip.backgroundColor = .quaternarySystemFill
    }
    thumbnail.preferredSymbolConfiguration = .init(pointSize: 20, weight: .regular)
    let loading = (spec["loading"] as? Bool) ?? false
    dim.isHidden = !loading
    thumbnail.isHidden = loading && !(d?.keepsColors ?? false)
    if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
    setNeedsLayout()
  }

  var preferredWidth: CGFloat {
    guard isChip else { return 60 }
    let text = max(titleLabel.intrinsicContentSize.width, subtitleLabel.isHidden ? 0 : subtitleLabel.intrinsicContentSize.width)
    return min(Self.chipMaxWidth, 8 + Self.chipThumbnail + 10 + ceil(text) + 38)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let h = bounds.height
    if isChip {
      let t = Self.chipThumbnail
      thumbnailClip.frame = CGRect(x: 8, y: (h - t) / 2, width: t, height: t)
      thumbnailClip.layer.cornerRadius = 10
      let textX = thumbnailClip.frame.maxX + 10
      let textW = bounds.width - textX - 38
      if subtitleLabel.isHidden {
        titleLabel.frame = CGRect(x: textX, y: 0, width: textW, height: h)
      } else {
        titleLabel.frame = CGRect(x: textX, y: h / 2 - 19, width: textW, height: 20)
        subtitleLabel.frame = CGRect(x: textX, y: h / 2 + 1, width: textW, height: 18)
      }
    } else {
      thumbnailClip.frame = bounds
      thumbnailClip.layer.cornerRadius = 16
    }
    thumbnail.frame = thumbnailClip.bounds
    dim.frame = thumbnailClip.bounds
    spinner.center = CGPoint(x: thumbnailClip.bounds.midX, y: thumbnailClip.bounds.midY)
    let r = Self.removeSize
    removeButton.frame = CGRect(x: bounds.width - r - 5, y: 5, width: r, height: r)
  }
}

/// A small button with a finger-sized hit area.
@available(iOS 26.0, *)
final class ExpandedHitButton: UIButton {
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    bounds.insetBy(dx: -10, dy: -10).contains(point)
  }
}
