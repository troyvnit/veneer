import UIKit

/// Where a composer is placed: the overlay's bounds and what it sits above.
struct ComposerPlacement {
  var bounds: CGRect
  var safeAreaBottom: CGFloat
  /// Top of the visible tab bar, if any.
  var tabBarTop: CGFloat?
  /// Top of the software keyboard, if it's showing.
  var keyboardTop: CGFloat?

  /// The line Flutter's own bottom inset reaches: the keyboard, the tab bar or
  /// the bottom safe area, whichever is highest.
  var baseline: CGFloat {
    min(keyboardTop ?? .greatestFiniteMagnitude, tabBarTop ?? bounds.height - safeAreaBottom)
  }
}

/// What the composers share: the UIKit text view and placeholder, focus,
/// text, send, show/hide, menus and the events sent to Dart. Subclasses
/// (`NativeComposerView`, `NativePromptComposerView`) own their shape,
/// layout and morphs.
///
/// The overlay drives placement: it asks for `frame(for:)` inside the
/// keyboard's animation block after calling `setKeyboardActive`, so every
/// morph rides the keyboard's own duration and curve.
@available(iOS 26.0, *)
class ComposerBaseView: UIView, UITextViewDelegate {
  var onEvent: ((String, Any?) -> Void)?
  /// Asks the host to recompute this view's frame (text grew, config changed).
  var onNeedsLayout: (() -> Void)?

  /// The `style` value in the Dart config this class renders.
  class var style: String { "" }

  let textView = UITextView()
  let placeholder = UILabel()
  private(set) var isShown = true
  /// Focused with the keyboard up (or a hardware keyboard): set by the host
  /// inside the keyboard animation.
  private(set) var isKeyboardActive = false
  var maxLines = 6
  var clearOnSend = true
  var accent: UIColor = .systemBlue
  private var lastConfig: NSDictionary?

  required override init(frame: CGRect) {
    super.init(frame: frame)
    textView.backgroundColor = .clear
    textView.font = .preferredFont(forTextStyle: .body)
    textView.adjustsFontForContentSizeCategory = true
    textView.textContainer.lineFragmentPadding = 0
    textView.delegate = self
    textView.isScrollEnabled = false
    textView.showsVerticalScrollIndicator = false
    placeholder.font = textView.font
    placeholder.adjustsFontForContentSizeCategory = true
    placeholder.textColor = .placeholderText
    textView.addSubview(placeholder)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: - Configuration

  /// Shared keys: `{placeholder, tintColor, maxLines, clearOnSend}`; the rest
  /// goes to `configure(_:)`.
  final func update(_ args: [String: Any]) {
    let config = args as NSDictionary
    guard lastConfig != config else { return }
    lastConfig = config
    placeholder.text = args["placeholder"] as? String
    maxLines = (args["maxLines"] as? NSNumber)?.intValue ?? 6
    clearOnSend = (args["clearOnSend"] as? Bool) ?? true
    accent = (args["tintColor"] as? NSNumber).map(UIColor.init(argb:)) ?? .systemBlue
    textView.tintColor = accent
    let animate = configure(args) && window != nil && isShown
    contentChanged()
    if animate {
      animateContentLayout()
    } else {
      onNeedsLayout?()
      setNeedsLayout()
    }
  }

  /// Applies style-specific keys. Returns whether the change should animate
  /// (e.g. buttons appearing), rather than apply at once.
  func configure(_ args: [String: Any]) -> Bool { false }

  /// Text or other content changed: refresh send state, placeholder etc.
  func contentChanged() {}

  func icon(_ raw: Any?, symbolSize: CGFloat, imageSize: CGFloat) -> UIImage? {
    guard let d = NativeIconDescriptor(raw) else { return nil }
    return NativeIconRenderer.shared.image(for: d, pointSize: d.isSymbol ? symbolSize : imageSize)
  }

  /// A native `UIMenu` for a button spec's `menu`, opened by a plain tap.
  func attachMenu(_ spec: [String: Any]?, to button: UIButton, id: String) {
    let menu = spec.flatMap { NativeMenu.make($0["menu"], id: id) { [weak self] itemId in self?.emitButton(itemId) } }
    button.menu = menu
    button.showsMenuAsPrimaryAction = menu != nil
  }

  // MARK: - Commands

  func focus() { textView.becomeFirstResponder() }
  func unfocus() { textView.resignFirstResponder() }
  var isEditingText: Bool { textView.isFirstResponder }
  var text: String { textView.text ?? "" }
  var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  func setText(_ text: String) {
    guard textView.text != text else { return }
    textView.text = text
    textChanged(notify: false)
  }

  func setShown(_ shown: Bool, animated: Bool = true) {
    guard shown != isShown else { return }
    isShown = shown
    if !shown { unfocus() }
    isUserInteractionEnabled = shown
    guard animated else {
      alpha = shown ? 1 : 0
      return
    }
    UIView.animate(withDuration: shown ? 0.25 : 0.15, delay: 0, options: [.beginFromCurrentState]) {
      self.alpha = shown ? 1 : 0
    }
  }

  func emitButton(_ id: String) { onEvent?("composerButton", ["id": id]) }

  /// Whether the send button is live.
  var canSend: Bool { hasText }

  func send() {
    guard canSend else { return }
    onEvent?("composerSend", ["text": text])
    if clearOnSend {
      textView.text = ""
      textChanged(notify: true)
    }
  }

  // MARK: - State and layout

  /// Called by the host inside the keyboard's animation block.
  func setKeyboardActive(_ active: Bool) {
    guard active != isKeyboardActive else { return }
    isKeyboardActive = active
    keyboardStateChanged()
    setNeedsLayout()
  }

  func keyboardStateChanged() {}

  /// This view's frame in the overlay for the current state.
  func frame(for placement: ComposerPlacement) -> CGRect { .zero }

  /// Space Flutter content should leave above `placement.baseline`.
  func occupiedHeight(for placement: ComposerPlacement) -> CGFloat {
    max(0, placement.baseline - frame(for: placement).minY)
  }

  var lineHeight: CGFloat { (textView.font ?? .preferredFont(forTextStyle: .body)).lineHeight }

  /// Fitted text view height for a width, between one line and `maxLines`.
  func fittedTextHeight(width: CGFloat, minimum: CGFloat) -> CGFloat {
    let fitted = textView.sizeThatFits(CGSize(width: max(1, width), height: .greatestFiniteMagnitude)).height
    let maximum = minimum + ceil(lineHeight) * CGFloat(max(0, maxLines - 1))
    return min(max(ceil(fitted), minimum), maximum)
  }

  /// Animates a height change the text or content caused.
  func animateContentLayout() {
    UIView.animate(springDuration: 0.35, bounce: 0, initialSpringVelocity: 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      self.onNeedsLayout?()
      self.superview?.layoutIfNeeded()
      self.layoutIfNeeded()
    }
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

  func textChanged(notify: Bool) {
    placeholder.isHidden = !text.isEmpty
    if notify { onEvent?("composerText", ["text": text]) }
    contentChanged()
    textDidChangeLayout()
  }

  /// Subclasses decide whether a text change moves anything.
  func textDidChangeLayout() {}
}

/// `UIMenu` from Dart menu items: `[{title, icon, destructive}]`. Picking item
/// `i` reports button id `"<id>.menu<i>"`.
@available(iOS 26.0, *)
enum NativeMenu {
  static func make(_ raw: Any?, id: String, iconSize: CGFloat = 20, onSelect: @escaping (String) -> Void) -> UIMenu? {
    guard let items = raw as? [[String: Any]], !items.isEmpty else { return nil }
    let actions: [UIMenuElement] = items.enumerated().map { i, item in
      let image = NativeIconDescriptor(item["icon"]).flatMap {
        NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? nil : iconSize)
      }
      let action = UIAction(title: item["title"] as? String ?? "", image: image) { _ in onSelect("\(id).menu\(i)") }
      if (item["destructive"] as? Bool) == true { action.attributes = .destructive }
      return action
    }
    return UIMenu(children: actions)
  }
}
