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
final class NativeComposerView: UIView, UITextViewDelegate {
  var onEvent: ((String, Any?) -> Void)?
  /// Asks the host to recompute this view's frame (text grew, config changed).
  var onNeedsLayout: (() -> Void)?

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

  private(set) var isExpanded = false
  private(set) var isShown = true

  private let background = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
  private let plusButton = UIButton(configuration: .glass())
  private let textView = UITextView()
  private let placeholder = UILabel()
  private let idleButton = UIButton(configuration: .plain())
  private var toolbarButtons: [UIButton] = []
  private let sendButton = UIButton(configuration: .plain())
  private var maxLines = 6
  private var clearOnSend = true
  private var accent: UIColor = .systemBlue
  private var lastConfig: NSDictionary?

  override init(frame: CGRect) {
    super.init(frame: frame)
    background.cornerConfiguration = .capsule(maximumRadius: Metrics.cornerRadius)
    addSubview(background)

    textView.backgroundColor = .clear
    textView.font = .preferredFont(forTextStyle: .body)
    textView.adjustsFontForContentSizeCategory = true
    textView.textContainerInset = UIEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)
    textView.textContainer.lineFragmentPadding = 0
    textView.delegate = self
    textView.isScrollEnabled = false
    textView.showsVerticalScrollIndicator = false
    placeholder.font = textView.font
    placeholder.adjustsFontForContentSizeCategory = true
    placeholder.textColor = .placeholderText
    textView.addSubview(placeholder)

    plusButton.configuration?.cornerStyle = .capsule
    plusButton.addAction(UIAction { [weak self] _ in self?.emitButton("leading") }, for: .touchUpInside)
    idleButton.addAction(UIAction { [weak self] _ in self?.emitButton("idle") }, for: .touchUpInside)
    sendButton.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)

    for v in [textView, plusButton, idleButton, sendButton] as [UIView] { background.contentView.addSubview(v) }
    // Tapping anywhere on the idle capsule focuses it, like a text field.
    background.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusFromTap)))
    applyState()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: - Configuration

  /// `{placeholder, leading: button?, idle: button?, toolbar: [button],
  ///   sendIcon, tintColor, maxLines, clearOnSend}`, button = `{id, icon, title}`.
  func update(_ args: [String: Any]) {
    let config = args as NSDictionary
    guard lastConfig != config else { return }
    lastConfig = config

    placeholder.text = args["placeholder"] as? String
    maxLines = (args["maxLines"] as? NSNumber)?.intValue ?? 6
    clearOnSend = (args["clearOnSend"] as? Bool) ?? true
    accent = (args["tintColor"] as? NSNumber).map(UIColor.init(argb:)) ?? .systemBlue
    textView.tintColor = accent

    let leading = args["leading"] as? [String: Any]
    plusButton.isHidden = leading == nil
    plusButton.configuration?.image = leading.flatMap { icon($0["icon"]) }
    plusButton.configuration?.baseForegroundColor = .label
    plusButton.accessibilityLabel = leading?["title"] as? String

    let idle = args["idle"] as? [String: Any]
    idleButton.isHidden = idle == nil
    configure(idleButton, idle, color: .secondaryLabel)

    toolbarButtons.forEach { $0.removeFromSuperview() }
    toolbarButtons = (args["toolbar"] as? [[String: Any]] ?? []).map { spec in
      let b = UIButton(configuration: .plain())
      configure(b, spec, color: .label)
      let id = spec["id"] as? String ?? ""
      b.addAction(UIAction { [weak self] _ in self?.emitButton(id) }, for: .touchUpInside)
      background.contentView.addSubview(b)
      return b
    }

    sendButton.configuration?.image = icon(args["sendIcon"])
      ?? UIImage(systemName: "paperplane.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: Metrics.symbolSize))
    sendButton.accessibilityLabel = "Send"
    applyState()
    updateSendButton()
    onNeedsLayout?()
    setNeedsLayout()
  }

  private func configure(_ button: UIButton, _ spec: [String: Any]?, color: UIColor) {
    button.configuration?.image = spec.flatMap { icon($0["icon"]) }
    button.configuration?.baseForegroundColor = color
    button.configuration?.contentInsets = .zero
    button.accessibilityLabel = spec?["title"] as? String
  }

  private func icon(_ raw: Any?) -> UIImage? {
    guard let d = NativeIconDescriptor(raw) else { return nil }
    return NativeIconRenderer.shared.image(for: d, pointSize: d.isSymbol ? Metrics.symbolSize : Metrics.imageSize)
  }

  // MARK: - Commands

  func focus() { textView.becomeFirstResponder() }
  func unfocus() { textView.resignFirstResponder() }
  var isEditingText: Bool { textView.isFirstResponder }

  func setText(_ text: String) {
    guard textView.text != text else { return }
    textView.text = text
    textChanged(notify: false)
  }

  func setShown(_ shown: Bool) {
    guard shown != isShown else { return }
    isShown = shown
    if !shown { unfocus() }
    isUserInteractionEnabled = shown
    UIView.animate(withDuration: shown ? 0.25 : 0.15) { self.alpha = shown ? 1 : 0 }
  }

  @objc private func focusFromTap() {
    if !isEditingText { focus() }
  }

  private func emitButton(_ id: String) { onEvent?("composerButton", ["id": id]) }

  private func send() {
    let text = textView.text ?? ""
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    onEvent?("composerSend", ["text": text])
    if clearOnSend {
      textView.text = ""
      textChanged(notify: true)
    }
  }

  // MARK: - State and layout

  /// Called by the host inside the keyboard's animation block.
  func setExpanded(_ expanded: Bool) {
    guard expanded != isExpanded else { return }
    isExpanded = expanded
    applyState()
    setNeedsLayout()
  }

  private func applyState() {
    idleButton.alpha = isExpanded ? 0 : 1
    for b in toolbarButtons { b.alpha = isExpanded ? 1 : 0 }
    sendButton.alpha = isExpanded ? 1 : 0
    textView.isScrollEnabled = isExpanded && textHeight(for: max(bounds.width, 100)) >= maxTextHeight
  }

  private var lineHeight: CGFloat { (textView.font ?? .preferredFont(forTextStyle: .body)).lineHeight }
  private var minTextHeight: CGFloat { max(Metrics.row, ceil(lineHeight) + 22) }
  private var maxTextHeight: CGFloat { minTextHeight + ceil(lineHeight) * CGFloat(max(0, maxLines - 1)) }

  private func textHeight(for width: CGFloat) -> CGFloat {
    let w = width - 2 * Metrics.textInset
    let fitted = textView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
    return min(max(ceil(fitted), minTextHeight), maxTextHeight)
  }

  /// Height for a given width in the current state.
  func preferredHeight(width: CGFloat) -> CGFloat {
    isExpanded ? Metrics.textTop + textHeight(for: width) + Metrics.row + 4 : Metrics.idleHeight
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
  }

  // MARK: - Hit testing

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    isShown && super.point(inside: point, with: event)
  }

  // MARK: - UITextViewDelegate

  func textViewDidBeginEditing(_ textView: UITextView) {
    onEvent?("composerFocus", ["focused": true])
  }

  func textViewDidEndEditing(_ textView: UITextView) {
    onEvent?("composerFocus", ["focused": false])
  }

  func textViewDidChange(_ textView: UITextView) { textChanged(notify: true) }

  private func textChanged(notify: Bool) {
    placeholder.isHidden = !(textView.text ?? "").isEmpty
    updateSendButton()
    if notify { onEvent?("composerText", ["text": textView.text ?? ""]) }
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

  private func updateSendButton() {
    let enabled = !(textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    sendButton.isEnabled = enabled
    sendButton.configuration?.baseForegroundColor = enabled ? accent : .tertiaryLabel
  }
}
