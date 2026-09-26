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
  private var composer: NativeComposerView?
  private var tabBarEdgeEffect: String?
  /// Top of the software keyboard in overlay coordinates; nil when hidden.
  private var keyboardTop: CGFloat?
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
    host.update(args)
    host.setHidden((args["hidden"] as? Bool) ?? false)
    edgeEffects.set(.top, style: host.isHidden ? nil : (args["edgeEffect"] as? String), elements: host.isHidden ? [] : [host.bar])
    setNeedsLayout()
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

  func setComposer(_ args: [String: Any]?) {
    guard let args else {
      composer?.unfocus()
      composer?.removeFromSuperview()
      composer = nil
      keyboardDismissProxy.stopDriving()
      updateBottomEdgeEffect()
      return
    }
    let view = composer ?? {
      let view = NativeComposerView()
      view.onEvent = { [weak self] method, payload in
        if method == "composerFocus" { self?.focusChanged() }
        self?.onEvent?(method, payload)
      }
      view.onNeedsLayout = { [weak self] in
        self?.layoutComposer()
        self?.reportComposer(duration: 0.2)
      }
      addSubview(view)
      composer = view
      return view
    }()
    view.update(args)
    view.setShown(!((args["hidden"] as? Bool) ?? false))
    interactiveDismissal = (args["interactiveDismissal"] as? Bool) ?? true
    updateKeyboardDismissal()
    layoutComposer()
    reportComposer(duration: 0)
    updateBottomEdgeEffect()
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
    guard let info = note.userInfo,
      let end = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
      let screen = window?.screen
    else { return }
    let local = screen.coordinateSpace.convert(end, to: self)
    keyboardTop = local.minY < bounds.height - 1 && local.height > 0 ? local.minY : nil
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
      composer.setExpanded(composer.isEditingText)
      self.layoutComposer()
      composer.layoutIfNeeded()
    }
    reportComposer(duration: duration)
  }

  private func updateKeyboardDismissal() {
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

  /// The keyboard's current top: from the last notification normally, from
  /// the layout guide while a finger is dragging it (interactive dismissal).
  private var liveKeyboardTop: CGFloat? {
    guard keyboardDismissProxy.isTracking, keyboardTop != nil else { return keyboardTop }
    let top = keyboardTracker.frame.minY
    return top < bounds.height - 1 ? top : nil
  }

  /// 9 pt above the keyboard or the tab bar, whichever is higher; 44 pt
  /// capsule aligned with the tab bar when idle, 8 pt margins when expanded.
  private func layoutComposer() {
    guard let composer else { return }
    let M = NativeComposerView.Metrics.self
    let tabTop = tabBarHost.flatMap { $0.isHidden ? nil : $0.tabBar.convert($0.tabBar.bounds, to: self).minY }
      ?? bounds.height - safeAreaInsets.bottom
    let limit = min(liveKeyboardTop ?? .greatestFiniteMagnitude, tabTop)
    let margin = composer.isExpanded ? M.expandedMargin : M.idleMargin
    let width = bounds.width - 2 * margin
    let height = composer.preferredHeight(width: width)
    let frame = CGRect(x: margin, y: limit - M.gap - height, width: width, height: height)
    if composer.frame != frame { composer.frame = frame }
  }

  private var lastComposerHeight: CGFloat = -1

  /// Tells Flutter how much space the composer takes above the keyboard or
  /// tab bar, and over what duration it's changing.
  private func reportComposer(duration: Double) {
    guard let composer else { return }
    let M = NativeComposerView.Metrics.self
    let margin = composer.isExpanded ? M.expandedMargin : M.idleMargin
    let height = composer.preferredHeight(width: bounds.width - 2 * margin) + M.gap
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
  private func reportInsets() {
    if let tabBarHost, tabBarHost.isHidden { return }
    let bottom = tabBarHost.map { bounds.height - $0.tabBar.convert($0.tabBar.bounds, to: self).minY } ?? 0
    let top = navigationBarHost.map { $0.isHidden ? 0 : $0.bar.convert($0.bar.bounds, to: self).maxY } ?? 0
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
