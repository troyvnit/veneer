import UIKit

/// A native message composer: a Liquid Glass capsule above the tab bar that
/// morphs into an expanded card above the keyboard when focused.
///
/// Idle: `[(+)  Placeholder…             🎙]`, 44 pt, aligned with the tab bar.
/// Focused: the text on top, a toolbar row below (`(+) Aa ☺ @ /   ➤`),
/// 8 pt from the screen edges, 9 pt above the keyboard.
///
/// The morph runs inside the keyboard's own animation (its duration and
/// curve from the keyboard notification), so the card, the keyboard and the
/// text move as one. Metrics follow Slack's iOS composer.
@available(iOS 26.0, *)
final class NativeComposerView: ComposerBaseView {
  override class var style: String { "card" }

  enum Metrics {
    static let idleHeight: CGFloat = 44
    static let idleMargin: CGFloat = 20
    static let expandedMargin: CGFloat = 8
    static let gap: CGFloat = 9
    static let circle: CGFloat = 36
    static let row: CGFloat = 44
    static let textTop: CGFloat = 12
    static let textInset: CGFloat = 12
    static let toolbarFirstCenter: CGFloat = 67
    static let toolbarSpacing: CGFloat = 41
    static let sendTrailing: CGFloat = 25
    /// SF Symbols' point size draws a larger glyph than a same-size image,
    /// so symbols and images get separate sizes that match visually (~19 pt
    /// glyphs, as in Slack).
    static let symbolSize: CGFloat = 17
    static let imageSize: CGFloat = 22
    static let cornerRadius: CGFloat = 28
  }

  var isExpanded: Bool { isKeyboardActive }

  private let background = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
  private let plusButton = UIButton(configuration: .glass())
  private let idleButton = UIButton(configuration: .plain())
  private var toolbarButtons: [UIButton] = []
  private let sendButton = UIButton(configuration: .plain())

  required init(frame: CGRect) {
    super.init(frame: frame)
    background.cornerConfiguration = .capsule(maximumRadius: Metrics.cornerRadius)
    addSubview(background)
    textView.textContainerInset = UIEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)

    plusButton.configuration?.cornerStyle = .capsule
    plusButton.addAction(UIAction { [weak self] _ in self?.emitButton("leading") }, for: .touchUpInside)
    idleButton.addAction(UIAction { [weak self] _ in self?.emitButton("idle") }, for: .touchUpInside)
    sendButton.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)

    for v in [textView, plusButton, idleButton, sendButton] as [UIView] { background.contentView.addSubview(v) }
    recordingBar.edgeCenter = Metrics.idleHeight / 2
    recordingBar.alpha = 0
    recordingBar.isUserInteractionEnabled = false
    background.contentView.addSubview(recordingBar)
    // Tapping anywhere on the idle capsule focuses it, like a text field.
    background.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusFromTap)))
    applyState()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: - Configuration

  /// `{leading: button?, idle: button?, toolbar: [button], sendIcon}`,
  /// button = `{id, icon, title, menu?}`.
  override func configure(_ args: [String: Any]) -> Bool {
    let leading = args["leading"] as? [String: Any]
    plusButton.isHidden = leading == nil
    plusButton.configuration?.image = leading.flatMap { icon($0["icon"]) }
    plusButton.configuration?.baseForegroundColor = .label
    plusButton.accessibilityLabel = leading?["title"] as? String
    attachMenu(leading, to: plusButton, id: "leading")

    let idle = args["idle"] as? [String: Any]
    idleButton.isHidden = idle == nil
    configure(idleButton, idle, color: .secondaryLabel)
    attachMenu(idle, to: idleButton, id: "idle")

    toolbarButtons.forEach { $0.removeFromSuperview() }
    toolbarButtons = (args["toolbar"] as? [[String: Any]] ?? []).map { spec in
      let b = UIButton(configuration: .plain())
      configure(b, spec, color: .label)
      let id = spec["id"] as? String ?? ""
      b.addAction(UIAction { [weak self] _ in self?.emitButton(id) }, for: .touchUpInside)
      attachMenu(spec, to: b, id: id)
      background.contentView.addSubview(b)
      return b
    }

    sendButton.configuration?.image = icon(args["sendIcon"])
      ?? UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.symbolSize))
    sendButton.accessibilityLabel = "Send"
    applyState()
    return false
  }

  private func configure(_ button: UIButton, _ spec: [String: Any]?, color: UIColor) {
    button.configuration?.image = spec.flatMap { icon($0["icon"]) }
    button.configuration?.baseForegroundColor = color
    button.configuration?.contentInsets = .zero
    button.accessibilityLabel = spec?["title"] as? String
  }

  private func icon(_ raw: Any?) -> UIImage? {
    icon(raw, symbolSize: Metrics.symbolSize, imageSize: Metrics.imageSize)
  }

  @objc private func focusFromTap() {
    guard !isRecording else { return }
    if !isEditingText { focus() }
  }

  // MARK: - State and layout

  override func keyboardStateChanged() { applyState() }

  override func contentChanged() {
    sendButton.isEnabled = canSend
    sendButton.configuration?.baseForegroundColor = canSend ? accent : .tertiaryLabel
  }

  private func applyState() {
    idleButton.alpha = isExpanded ? 0 : 1
    for b in toolbarButtons { b.alpha = isExpanded ? 1 : 0 }
    sendButton.alpha = isExpanded ? 1 : 0
    textView.isScrollEnabled = isExpanded && textHeight(for: max(bounds.width, 100)) >= maxTextHeight
    // The one-line idle capsule never scrolls: show the text from the top.
    if !isExpanded { textView.contentOffset = .zero }
  }

  private var minTextHeight: CGFloat { max(Metrics.row, ceil(lineHeight) + 22) }
  private var maxTextHeight: CGFloat { minTextHeight + ceil(lineHeight) * CGFloat(max(0, maxLines - 1)) }

  private func textHeight(for width: CGFloat) -> CGFloat {
    fittedTextHeight(width: width - 2 * Metrics.textInset, minimum: minTextHeight)
  }

  /// Height for a given width in the current state.
  func preferredHeight(width: CGFloat) -> CGFloat {
    isExpanded ? Metrics.textTop + textHeight(for: width) + Metrics.row + 4 : Metrics.idleHeight
  }

  /// 9 pt above the keyboard or the tab bar, whichever is higher; 44 pt
  /// capsule aligned with the tab bar when idle, 8 pt margins when expanded.
  override func frame(for placement: ComposerPlacement) -> CGRect {
    let margin = isExpanded ? Metrics.expandedMargin : Metrics.idleMargin
    let width = placement.bounds.width - 2 * margin
    let height = preferredHeight(width: width)
    return CGRect(x: margin, y: placement.baseline - Metrics.gap - height, width: width, height: height)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    background.frame = bounds
    let w = bounds.width, h = bounds.height
    let c = Metrics.circle
    if isExpanded {
      let rowTop = h - Metrics.row - 4
      plusButton.frame = CGRect(x: Metrics.expandedMargin, y: rowTop + (Metrics.row - c) / 2, width: c, height: c)
      textView.frame = CGRect(x: Metrics.textInset, y: Metrics.textTop, width: w - 2 * Metrics.textInset, height: rowTop - Metrics.textTop)
      for (i, b) in toolbarButtons.enumerated() {
        let cx = Metrics.toolbarFirstCenter + CGFloat(i) * Metrics.toolbarSpacing
        b.frame = CGRect(x: cx - Metrics.row / 2, y: rowTop, width: Metrics.row, height: Metrics.row)
      }
      sendButton.frame = CGRect(x: w - Metrics.sendTrailing - Metrics.row / 2, y: rowTop, width: Metrics.row, height: Metrics.row)
      idleButton.frame = CGRect(x: w - Metrics.row, y: rowTop, width: Metrics.row, height: Metrics.row)
    } else {
      let inset = (h - c) / 2
      plusButton.frame = CGRect(x: inset, y: inset, width: c, height: c)
      let textX = plusButton.isHidden ? 16 : inset + c + 9
      let trailing = idleButton.isHidden ? 16 : Metrics.row
      textView.frame = CGRect(x: textX, y: 0, width: w - textX - trailing, height: h)
      idleButton.frame = CGRect(x: w - Metrics.row, y: 0, width: Metrics.row, height: h)
      // Toolbar waits in its expanded position, faded out, so it fades in place.
      let rowTop = h - Metrics.row
      for (i, b) in toolbarButtons.enumerated() {
        let cx = Metrics.toolbarFirstCenter + CGFloat(i) * Metrics.toolbarSpacing
        b.frame = CGRect(x: cx - Metrics.row / 2, y: rowTop, width: Metrics.row, height: Metrics.row)
      }
      sendButton.frame = CGRect(x: w - Metrics.sendTrailing - Metrics.row / 2, y: rowTop, width: Metrics.row, height: Metrics.row)
    }
    placeholder.frame = CGRect(x: 0, y: 11, width: textView.bounds.width, height: ceil(lineHeight))

    // Recording (always idle: it starts by dropping the keyboard): the bar
    // takes the capsule and the content fades under it.
    let recording = isRecording
    recordingBar.frame = bounds
    recordingBar.alpha = recording ? 1 : 0
    recordingBar.isUserInteractionEnabled = recording
    for v in [textView, plusButton, idleButton] as [UIView] {
      v.alpha = recording ? 0 : (v === idleButton && isExpanded ? 0 : 1)
      v.isUserInteractionEnabled = !recording
    }
  }

  // MARK: - Text

  override func textDidChangeLayout() {
    let before = bounds.height
    let after = preferredHeight(width: bounds.width)
    textView.isScrollEnabled = isExpanded && textHeight(for: bounds.width) >= maxTextHeight
    if abs(before - after) > 0.5 {
      UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
        self.onNeedsLayout?()
        self.superview?.layoutIfNeeded()
      }
    }
  }
}
