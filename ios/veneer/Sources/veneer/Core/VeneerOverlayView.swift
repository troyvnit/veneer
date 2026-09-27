import UIKit

/// Full-screen view added as a subview of the `FlutterView`, above Flutter's
/// Metal layer. Glass in here samples the Flutter pixels underneath through
/// the window's backdrop, so Flutter content scrolling "under" native glass
/// is refracted exactly like UIKit content would be.
///
/// Holds, bottom to top:
///   * `glassLayer` — Flutter-positioned Liquid Glass (groups, clip scopes).
///   * the scroll edge effect host — iOS 26's soft edge blur, over Flutter
///     content and content glass, shaped around the chrome.
///   * native chrome, laid out by UIKit, not Flutter: a real
///     `UITabBarController` (`NativeTabBarHost`), `UINavigationBar`
///     (`NativeNavigationBarHost`) and the composer (`NativeComposerView`),
///     which follows the keyboard's own animation.
///
/// Touches pass straight through to Flutter unless they land on chrome or
/// on an interactive glass shape.
@available(iOS 26.0, *)
final class VeneerOverlayView: UIView {
  let glassLayer = GlassLayerView()
  var onEvent: ((String, Any?) -> Void)? {
    didSet { tabBarHost?.onEvent = onEvent }
  }
  /// Parent for chrome view controllers (the `FlutterViewController`).
  weak var hostViewController: UIViewController?

  private var tabBarHost: NativeTabBarHost?
  private var navigationBarHost: NativeNavigationBarHost?
  private let edgeEffects = ScrollEdgeEffectHost()
  private var composer: ComposerBaseView?
  private var tabBarEdgeEffect: String?
  /// Top of the software keyboard in overlay coordinates; nil when hidden.
  /// The software keyboard's frame in screen coordinates; nil when hidden.
  /// Kept in screen space and converted when needed: this view can move
  /// while the keyboard is up (a sheet growing to its large detent for it).
  private var keyboardScreenFrame: CGRect?

  /// Top of the software keyboard in overlay coordinates; nil when hidden.
  private var keyboardTop: CGFloat? {
    guard let frame = keyboardScreenFrame, let screen = window?.screen else { return nil }
    let local = screen.coordinateSpace.convert(frame, to: self)
    return local.minY < bounds.height - 1 && local.height > 0 ? local.minY : nil
  }
  private var focusAnimationPending = false
  /// Drives UIKit's interactive keyboard dismissal from drags on Flutter content.
  private let keyboardDismissProxy = KeyboardDismissProxy()
  private var interactiveDismissal = true
  /// Pinned to `keyboardLayoutGuide.top`, which UIKit updates frame by frame
  /// while the keyboard follows a finger (no notifications are posted then).
  private let keyboardTracker = UIView()
  private var lastReportedInsets = UIEdgeInsets(top: -1, left: 0, bottom: -1, right: 0)

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    glassLayer.frame = bounds
    glassLayer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    glassLayer.onShapeTapped = { [weak self] id in
      self?.onEvent?("shapeTapped", ["id": id])
    }
    glassLayer.onShapeMenu = { [weak self] id, index in
      self?.onEvent?("shapeMenu", ["id": id, "index": index])
    }
    addSubview(glassLayer)
    edgeEffects.attach(to: self, at: 1)

    keyboardDismissProxy.frame = bounds
    keyboardDismissProxy.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    keyboardDismissProxy.isFlutterTouch = { [weak self] point in
      guard let self else { return false }
      return self.hitTest(point, with: nil) == nil
    }
    insertSubview(keyboardDismissProxy, at: 0)

    keyboardLayoutGuide.usesBottomSafeArea = false
    keyboardTracker.isUserInteractionEnabled = false
    keyboardTracker.translatesAutoresizingMaskIntoConstraints = false
    addSubview(keyboardTracker)
    NSLayoutConstraint.activate([
      keyboardTracker.leadingAnchor.constraint(equalTo: leadingAnchor),
      keyboardTracker.widthAnchor.constraint(equalToConstant: 1),
      keyboardTracker.heightAnchor.constraint(equalToConstant: 1),
      keyboardTracker.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
    ])
    NotificationCenter.default.addObserver(
      self, selector: #selector(keyboardWillChangeFrame(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: - Hit testing

  /// Each layer is asked separately, top to bottom: the tab bar
  /// controller's full-screen (but empty) view sits above the glass layer, so
  /// a plain `super.hitTest` would return that container and starve the
  /// interactive glass beneath it.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isUserInteractionEnabled, !isHidden, self.point(inside: point, with: event) else { return nil }
    // The frame check matters: while its text view is first responder, UIKit
    // resolves hits on the composer to text-interaction views even for points
    // far outside it, which would steal every tap from Flutter.
    if let composer, composer.isShown, composer.frame.contains(point),
      let hit = composer.hitTest(convert(point, to: composer), with: event)
    {
      return hit
    }
    if let navigationBarHost, let hit = navigationBarHost.hitTest(point, in: self, with: event) { return hit }
    if let tabBarHost, let hit = tabBarHost.hitTest(point, in: self, with: event) { return hit }
    return glassLayer.hitTest(convert(point, to: glassLayer), with: event)
  }

  /// Platform views and other plugins may add subviews to the FlutterView
  /// after us; glass must stay above them to sample them.
  func keepOnTop() {
    guard let superview, superview.subviews.last !== self else { return }
    superview.bringSubviewToFront(self)
  }

  // MARK: - Chrome: tab bar

  /// The engine behind this overlay is going away (a dismissed sheet):
  /// drop the native views and stop following the keyboard.
  func tearDown() {
    NotificationCenter.default.removeObserver(self)
    composer?.unfocus()
    setComposer(nil)
    setNavigationBar(nil)
    setTabBar(nil)
    onEvent = nil
    removeFromSuperview()
  }

  func setTabBar(_ args: [String: Any]?) {
    guard let args else {
      tabBarHost?.detach()
      tabBarHost = nil
      reportInsets()
      return
    }
    let host = tabBarHost ?? {
      let host = NativeTabBarHost()
      host.onEvent = onEvent
      host.onLayout = { [weak self] in
        self?.reportInsets()
        self?.layoutComposer()
      }
      host.attach(to: self, host: hostViewController)
      tabBarHost = host
      return host
    }()
    host.update(args)
    tabBarEdgeEffect = args["edgeEffect"] as? String
    updateBottomEdgeEffect()
  }

  private func updateBottomEdgeEffect() {
    let elements = [tabBarHost?.tabBar, composer?.isShown == true ? composer : nil].compactMap { $0 }
    edgeEffects.set(.bottom, style: tabBarEdgeEffect ?? (composer != nil ? "soft" : nil), elements: elements)
  }

  // MARK: - Chrome: navigation bar

  func setNavigationBar(_ args: [String: Any]?) {
    guard let args else {
      edgeEffects.set(.top, style: nil, elements: [])
      navigationBarHost?.detach()
      navigationBarHost = nil
      setNeedsLayout()
      return
    }
    let host = navigationBarHost ?? {
      let host = NativeNavigationBarHost()
      host.onEvent = onEvent
      host.attach(to: self)
      navigationBarHost = host
      return host
    }()
    // In a sheet, buttons are concentric with the sheet's corners.
    if isInSheet { host.setSideInset(NativeSheetSession.edgeInset) }
    host.update(args)
    host.setHidden((args["hidden"] as? Bool) ?? false)
    edgeEffects.setTopScrolled((args["scrolled"] as? Bool) ?? false)
    edgeEffects.set(.top, style: host.isHidden ? nil : (args["edgeEffect"] as? String), elements: host.isHidden ? [] : [host.bar])
    setNeedsLayout()
  }

  func setNavigationBarScrolled(_ scrolled: Bool) {
    edgeEffects.setTopScrolled(scrolled)
  }

  func setChromeHidden(_ hidden: Bool) {
    tabBarHost?.setHidden(hidden)
  }

  /// Chrome must stay above subviews added later (e.g. the tab bar
  /// controller's view): navigation bar, then the composer on top.
  override func didAddSubview(_ subview: UIView) {
    super.didAddSubview(subview)
    if let bar = navigationBarHost?.bar, bar.superview === self, subview !== bar { bringSubviewToFront(bar) }
    if let composer, composer.superview === self, subview !== composer { bringSubviewToFront(composer) }
  }

  // MARK: - Chrome: composer

  private static let composerStyles: [String: ComposerBaseView.Type] = [
    NativeComposerView.style: NativeComposerView.self,
    NativePromptComposerView.style: NativePromptComposerView.self,
  ]

  func setComposer(_ args: [String: Any]?) {
    guard let args else {
      composer?.unfocus()
      composer?.removeFromSuperview()
      composer = nil
      lastComposerHeight = -1
      keyboardDismissProxy.stopDriving()
      updateBottomEdgeEffect()
      return
    }
    let type = Self.composerStyles[args["style"] as? String ?? ""] ?? NativeComposerView.self
    let hidden = (args["hidden"] as? Bool) ?? false
    let view: ComposerBaseView
    if let composer, Swift.type(of: composer) == type {
      view = composer
    } else {
      // Another page's composer style: cross-fade from the old one.
      if let old = composer {
        old.unfocus()
        UIView.animate(withDuration: 0.2, animations: { old.alpha = 0 }, completion: { _ in old.removeFromSuperview() })
      }
      view = makeComposer(type)
      view.setShown(false, animated: false)
    }
    view.update(args)
    interactiveDismissal = (args["interactiveDismissal"] as? Bool) ?? true
    layoutComposer()
    view.layoutIfNeeded()
    view.setShown(!hidden)
    updateKeyboardDismissal()
    reportComposer(duration: 0)
    updateBottomEdgeEffect()
  }

  private func makeComposer(_ type: ComposerBaseView.Type) -> ComposerBaseView {
    let view = type.init(frame: .zero)
    view.onEvent = { [weak self] method, payload in
      if method == "composerFocus" { self?.focusChanged() }
      self?.onEvent?(method, payload)
    }
    view.onNeedsLayout = { [weak self, weak view] in
      guard let self, let view, view === self.composer else { return }
      self.layoutComposer()
      self.reportComposer(duration: 0.35)
    }
    addSubview(view)
    composer = view
    lastComposerHeight = -1
    return view
  }

  func composerCommand(_ args: [String: Any]) {
    guard let composer else { return }
    switch args["command"] as? String {
    case "focus": composer.focus()
    case "unfocus": composer.unfocus()
    case "setText": composer.setText(args["text"] as? String ?? "")
    default: break
    }
  }

  /// Keyboard notifications drive the morph with the keyboard's own
  /// duration and curve, so card and keyboard move as one.
  @objc private func keyboardWillChangeFrame(_ note: Notification) {
    // A native sheet over this view has its own overlay; the keyboard is its.
    if let host = hostViewController, host.presentedViewController != nil, !host.isBeingPresented,
      keyboardScreenFrame == nil
    {
      return
    }
    guard let info = note.userInfo,
      let end = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
      let screen = window?.screen
    else { return }
    let wasShowing = keyboardScreenFrame != nil
    keyboardScreenFrame = end.minY < screen.bounds.height - 1 && end.height > 0 ? end : nil
    // The software keyboard went away while the text view kept focus: UIKit
    // can end an interactive dismissal (or a keyboard swap) without
    // resigning a first responder outside the dragged scroll view. Drop the
    // focus too, so the composer can't stay expanded with no keyboard (and a
    // later tap doesn't bring the keyboard back unasked). A hardware keyboard
    // never shows the software one, so it isn't affected.
    if wasShowing, keyboardScreenFrame == nil, let composer, composer.isEditingText {
      DispatchQueue.main.async { [weak composer] in
        guard let composer, composer.isEditingText, self.keyboardScreenFrame == nil else { return }
        composer.unfocus()
      }
    }
    focusAnimationPending = false
    let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
    let curve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
    animateComposer(duration: duration, options: UIView.AnimationOptions(rawValue: curve << 16))
  }

  /// Focus without a software keyboard notification (hardware keyboard):
  /// animate on our own, unless the keyboard animation already took over.
  private func focusChanged() {
    focusAnimationPending = true
    DispatchQueue.main.async { [weak self] in
      guard let self, self.focusAnimationPending else { return }
      self.focusAnimationPending = false
      self.animateComposer(duration: 0.35, options: .curveEaseInOut)
    }
  }

  private func animateComposer(duration: Double, options: UIView.AnimationOptions) {
    guard let composer else { return }
    UIView.animate(withDuration: duration, delay: 0, options: [options, .beginFromCurrentState, .allowUserInteraction]) {
      composer.setKeyboardActive(composer.isEditingText)
      self.layoutComposer()
      composer.layoutIfNeeded()
    }
    reportComposer(duration: duration)
  }

  /// Whether this overlay is inside a native sheet's view.
  private var isInSheet: Bool {
    guard let host = hostViewController else { return false }
    return host.presentingViewController != nil && host.modalPresentationStyle == .pageSheet
  }

  /// From the sheet's Flutter content, on each touch: whether the content
  /// under the finger is scrolled to its top edge.
  private var sheetContentAtTop = true

  func setSheetContentAtTop(_ atTop: Bool) {
    sheetContentAtTop = atTop
    updateKeyboardDismissal()
  }

  /// UIKit's rule for a sheet over scrolling content: pulling down drags the
  /// sheet when the content is at its top; pushing up grows the sheet until
  /// its largest detent. Every other drag scrolls the content.
  private func sheetTakesDrag(velocity: CGPoint) -> Bool {
    guard isInSheet, let sheet = hostViewController?.sheetPresentationController else { return false }
    if velocity.y > 0 { return sheetContentAtTop }
    let largest = sheet.detents.last?.identifier
    return sheet.selectedDetentIdentifier != nil && sheet.selectedDetentIdentifier != largest
  }

  private func updateKeyboardDismissal() {
    if isInSheet, let host = superview {
      // In a sheet the proxy always runs: it's what keeps the sheet still
      // while Flutter content scrolls (see sheetTakesDrag).
      keyboardDismissProxy.yieldsToSheet = { [weak self] velocity in self?.sheetTakesDrag(velocity: velocity) ?? false }
      keyboardDismissProxy.drive(from: host)
      return
    }
    if let host = superview, interactiveDismissal, composer?.isShown == true {
      keyboardDismissProxy.drive(from: host)
    } else {
      keyboardDismissProxy.stopDriving()
    }
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    updateKeyboardDismissal()
  }

  /// A sheet's view can be laid out before UIKit presents it (to measure
  /// content-sized sheets), when it isn't in a sheet yet: whether its drags
  /// belong to the sheet or the content is settled once it's on screen.
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { updateKeyboardDismissal() }
  }

  /// The keyboard's current top: from the last notification normally, from
  /// the layout guide while a finger is dragging it (interactive dismissal).
  private var liveKeyboardTop: CGFloat? {
    guard keyboardDismissProxy.isTracking, keyboardTop != nil else { return keyboardTop }
    let top = keyboardTracker.frame.minY
    return top < bounds.height - 1 ? top : nil
  }

  private func composerPlacement(keyboardTop: CGFloat?) -> ComposerPlacement {
    ComposerPlacement(
      bounds: bounds,
      safeAreaBottom: safeAreaInsets.bottom,
      tabBarTop: tabBarHost.flatMap { $0.isHidden ? nil : $0.tabBar.convert($0.tabBar.bounds, to: self).minY },
      keyboardTop: keyboardTop)
  }

  /// Where the composer's own style puts it: above the keyboard, the tab bar
  /// or the home indicator.
  private func layoutComposer() {
    guard let composer else { return }
    let frame = composer.frame(for: composerPlacement(keyboardTop: liveKeyboardTop))
      .offsetBy(dx: composerOffset.x, dy: composerOffset.y)
    if composer.frame != frame { composer.frame = frame }
  }

  /// How far the composer's Flutter page is displaced from where it rests.
  private var composerOffset = CGPoint.zero

  /// Called with every Flutter frame's geometry (inside the FFI call), so the
  /// composer rides whatever moves its page: a sheet sliding up or dragged
  /// down, a route sliding in. Only moves the view; never lays out (see the
  /// FFI rules).
  func setComposerOffset(_ offset: CGPoint) {
    guard offset != composerOffset else { return }
    let delta = CGPoint(x: offset.x - composerOffset.x, y: offset.y - composerOffset.y)
    composerOffset = offset
    guard let composer else { return }
    composer.center = CGPoint(x: composer.center.x + delta.x, y: composer.center.y + delta.y)
  }

  private var lastComposerHeight: CGFloat = -1

  /// Tells Flutter how much space the composer takes above the keyboard or
  /// tab bar, and over what duration it's changing.
  private func reportComposer(duration: Double) {
    guard let composer else { return }
    let height = composer.occupiedHeight(for: composerPlacement(keyboardTop: keyboardTop))
    guard abs(height - lastComposerHeight) > 0.5 else { return }
    lastComposerHeight = height
    onEvent?("composerLayout", ["height": Double(height), "duration": duration])
  }

  // MARK: - Layout → Flutter insets

  override func layoutSubviews() {
    super.layoutSubviews()
    edgeEffects.layout()
    reportInsets()
    layoutComposer()
  }

  /// Distance from the top of native chrome to the bottom of the screen.
  /// Flutter adds this to MediaQuery padding so scroll views end above the
  /// bar but still scroll underneath it. Not reported while the bar is
  /// hidden for a popup, so the page underneath doesn't re-lay out.
  /// A new Dart isolate attached (a hot restart, say): it knows nothing of
  /// what was reported before, so the next layout reports everything again.
  func resendLayout() {
    lastReportedInsets = UIEdgeInsets(top: -1, left: 0, bottom: -1, right: 0)
    lastComposerHeight = -1
    setNeedsLayout()
  }

  func reportInsets() {
    // A hidden tab bar keeps its last inset, so the page underneath doesn't
    // re-lay out; the navigation bar's inset is reported regardless.
    let bottom =
      tabBarHost.map { $0.isHidden ? lastReportedInsets.bottom : bounds.height - $0.tabBar.convert($0.tabBar.bounds, to: self).minY } ?? 0
    let top = navigationBarHost.map { $0.bar.convert($0.bar.bounds, to: self).maxY } ?? 0
    guard abs(bottom - lastReportedInsets.bottom) > 0.5 || abs(top - lastReportedInsets.top) > 0.5 else { return }
    lastReportedInsets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
    onEvent?("chromeInsets", ["bottom": Double(bottom), "top": Double(top)])
  }
}

extension UIColor {
  convenience init(argb: NSNumber) {
    let v = UInt32(bitPattern: Int32(truncatingIfNeeded: argb.int64Value))
    self.init(
      red: CGFloat((v >> 16) & 0xFF) / 255,
      green: CGFloat((v >> 8) & 0xFF) / 255,
      blue: CGFloat(v & 0xFF) / 255,
      alpha: CGFloat((v >> 24) & 0xFF) / 255
    )
  }
}
