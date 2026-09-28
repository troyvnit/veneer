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
  /// Runs of text drawn in `accent` wherever they appear (mentions).
  private var highlights: [String] = []
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
    highlights = (args["highlights"] as? [String] ?? []).filter { !$0.isEmpty }
    recordingBar.setLabels(cancel: args["recordingCancelLabel"] as? String, done: args["recordingDoneLabel"] as? String)
    applyHighlights()
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

  func setText(_ text: String, selection: NSRange? = nil) {
    if textView.text != text {
      textView.text = text
      textChanged(notify: false)
    }
    let length = (text as NSString).length
    var range = NSRange(location: length, length: 0)
    if let selection {
      let start = min(max(0, selection.location), length)
      range = NSRange(location: start, length: min(max(0, selection.length), length - start))
    }
    if textView.selectedRange != range { textView.selectedRange = range }
  }

  /// Draws `highlights` in the accent colour, the rest in the label colour,
  /// without replacing the text (so the caret and an in-progress IME
  /// composition stay put). Typing after a highlight types plain text.
  func applyHighlights() {
    let font = textView.font ?? .preferredFont(forTextStyle: .body)
    let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
    textView.typingAttributes = base
    guard textView.markedTextRange == nil else { return }
    let storage = textView.textStorage
    let whole = NSRange(location: 0, length: storage.length)
    storage.beginEditing()
    storage.setAttributes(base, range: whole)
    let string = storage.string as NSString
    var taken: [NSRange] = []
    for token in highlights.sorted(by: { $0.count > $1.count }) {
      var search = whole
      while search.length > 0 {
        let found = string.range(of: token, options: [], range: search)
        guard found.location != NSNotFound else { break }
        if !taken.contains(where: { NSIntersectionRange($0, found).length > 0 }) {
          storage.addAttribute(.foregroundColor, value: accent, range: found)
          taken.append(found)
        }
        let next = found.location + found.length
        search = NSRange(location: next, length: whole.length - next)
      }
    }
    storage.endEditing()
  }

  func setShown(_ shown: Bool, animated: Bool = true) {
    guard shown != isShown else { return }
    isShown = shown
    if !shown {
      unfocus()
      cancelRecording()
    }
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

  // MARK: - Voice recording

  /// Set while recording, and while asking for the microphone before it.
  private var recorder: VoiceRecorder?
  /// The bar is up: recording has started.
  private(set) var isRecording = false
  /// The row shown in place of the composer's content while recording;
  /// subclasses place it and fade their own content.
  let recordingBar = RecordingBarView()

  /// `{maxDuration (seconds)?}`.
  func startRecording(_ args: [String: Any]) {
    guard recorder == nil else { return }
    let recorder = VoiceRecorder(maxDuration: (args["maxDuration"] as? NSNumber)?.doubleValue)
    self.recorder = recorder
    unfocus()
    recordingBar.accent = accent
    recordingBar.onCancel = { [weak self] in self?.cancelRecording() }
    recordingBar.onDone = { [weak self] in self?.finishRecording() }
    recorder.onSample = { [weak self] level, elapsed in self?.recordingBar.append(level: level, elapsed: elapsed) }
    recorder.onLimit = { [weak self] in self?.finishRecording() }
    recorder.start { [weak self] failure in
      // Cancelled (or the composer went away) while asking for access.
      guard let self, self.recorder === recorder else {
        if failure == nil { recorder.cancel() }
        return
      }
      if let failure {
        self.recorder = nil
        self.onEvent?("composerRecording", ["state": "failed", "reason": failure.rawValue])
        return
      }
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      self.isRecording = true
      self.recordingBar.reset()
      self.onEvent?("composerRecording", ["state": "started"])
      self.recordingChanged()
    }
  }

  func finishRecording() {
    guard let recorder, isRecording else { return }
    self.recorder = nil
    isRecording = false
    recordingChanged()
    guard let clip = recorder.finish() else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    onEvent?("composerRecording", [
      "state": "finished",
      "path": clip.url.path,
      "durationMs": Int((clip.duration * 1000).rounded()),
    ])
  }

  func cancelRecording() {
    guard let recorder else { return }
    let wasRecording = isRecording
    self.recorder = nil
    isRecording = false
    recorder.cancel()
    guard wasRecording else { return }
    onEvent?("composerRecording", ["state": "cancelled"])
    recordingChanged()
  }

  /// Recording started or ended: swap the content for the bar (or back).
  func recordingChanged() { animateContentLayout() }

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

  func textViewDidChangeSelection(_ textView: UITextView) {
    guard textView.markedTextRange == nil else { return }
    onEvent?("composerSelection", selectionArgs)
  }

  private var selectionArgs: [String: Any] {
    let range = textView.selectedRange
    return ["selectionStart": range.location, "selectionEnd": range.location + range.length]
  }

  func textChanged(notify: Bool) {
    placeholder.isHidden = !text.isEmpty
    applyHighlights()
    if notify { onEvent?("composerText", ["text": text].merging(selectionArgs) { a, _ in a }) }
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
    // Dividers split the items into inline sections, as UIKit draws them.
    var sections: [[UIMenuElement]] = [[]]
    for (i, item) in items.enumerated() {
      if (item["divider"] as? Bool) == true {
        if !(sections.last?.isEmpty ?? true) { sections.append([]) }
        continue
      }
      let image = NativeIconDescriptor(item["icon"]).flatMap {
        NativeIconRenderer.shared.image(for: $0, pointSize: $0.isSymbol ? nil : iconSize)
      }
      let action = UIAction(title: item["title"] as? String ?? "", image: image) { _ in onSelect("\(id).menu\(i)") }
      if (item["destructive"] as? Bool) == true { action.attributes = .destructive }
      sections[sections.count - 1].append(action)
    }
    sections.removeAll { $0.isEmpty }
    if sections.count == 1 { return UIMenu(children: sections[0]) }
    return UIMenu(children: sections.map { UIMenu(options: .displayInline, children: $0) })
  }
}
