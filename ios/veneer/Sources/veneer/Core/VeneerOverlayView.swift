import UIKit

/// Full-screen view added as a subview of the `FlutterView`, above Flutter's
/// Metal layer. Glass in here samples the Flutter pixels underneath through
/// the window's backdrop, so Flutter content scrolling "under" native glass
/// is refracted exactly like UIKit content would be.
///
/// Holds, bottom to top:
///   * `glassLayer` — Flutter-positioned Liquid Glass (groups, clip scopes).
///   * native chrome — a real `UITabBarController` (`NativeTabBarHost`),
///     laid out by UIKit, not Flutter.
///
/// Touches pass straight through to Flutter unless they land on chrome or
/// on an interactive glass shape.
final class VeneerOverlayView: UIView {
  let glassLayer = GlassLayerView()
  var onEvent: ((String, Any?) -> Void)? {
    didSet { tabBarHost?.onEvent = onEvent }
  }
  /// Parent for chrome view controllers (the `FlutterViewController`).
  weak var hostViewController: UIViewController?

  private var tabBarHost: NativeTabBarHost?
  private var lastReportedBottomInset: CGFloat = -1

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    glassLayer.frame = bounds
    glassLayer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    glassLayer.onShapeTapped = { [weak self] id in
      self?.onEvent?("shapeTapped", ["id": id])
    }
    addSubview(glassLayer)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: - Hit testing

  /// Each layer is asked separately, top to bottom: the tab bar
  /// controller's full-screen (but empty) view sits above the glass layer, so
  /// a plain `super.hitTest` would return that container and starve the
  /// interactive glass beneath it.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isUserInteractionEnabled, !isHidden, self.point(inside: point, with: event) else { return nil }
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
      host.onLayout = { [weak self] in self?.reportInsets() }
      host.attach(to: self, host: hostViewController)
      tabBarHost = host
      return host
    }()
    host.update(args)
  }

  func setChromeHidden(_ hidden: Bool) {
    tabBarHost?.setHidden(hidden)
  }

  // MARK: - Layout → Flutter insets

  override func layoutSubviews() {
    super.layoutSubviews()
    reportInsets()
  }

  /// Distance from the top of native chrome to the bottom of the screen.
  /// Flutter adds this to MediaQuery padding so scroll views end above the
  /// bar but still scroll underneath it. Not reported while the bar is
  /// hidden for a popup, so the page underneath doesn't re-lay out.
  private func reportInsets() {
    if let tabBarHost, tabBarHost.isHidden { return }
    let bottomInset = tabBarHost.map { bounds.height - $0.tabBar.convert($0.tabBar.bounds, to: self).minY } ?? 0
    guard abs(bottomInset - lastReportedBottomInset) > 0.5 else { return }
    lastReportedBottomInset = bottomInset
    onEvent?("chromeInsets", ["bottom": Double(bottomInset)])
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
