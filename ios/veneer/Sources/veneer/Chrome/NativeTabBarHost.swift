import UIKit

/// A real `UITabBarController` driving the bottom bar, so everything the
/// system does — the floating Liquid Glass bar, the selection morph, the
/// detached trailing button ("split" layout), badges, VoiceOver, large
/// content viewer on long-press — is UIKit's own.
///
/// The controller is a child of the `FlutterViewController`, with its view in
/// the Veneer overlay. Its tabs host empty, touch-transparent view
/// controllers: Flutter keeps drawing the pages underneath and the bar's
/// glass samples them.
///
/// The trailing button is a `UISearchTab`, which UIKit lays out detached at
/// the trailing edge on iOS 26; iOS 27 requires it to be named the
/// `prominentTabIdentifier` for the same layout. It acts either as a button
/// (selection vetoed in `shouldSelectTab`, press sent to Dart) or as a real
/// selectable tab.
@available(iOS 26.0, *)
final class NativeTabBarHost: NSObject, UITabBarControllerDelegate {
  var onEvent: ((String, Any?) -> Void)?
  /// Called when the bar's frame may have changed.
  var onLayout: (() -> Void)?

  let controller = ChromeTabBarController()

  private var tabIdentifiers: [String] = []
  private var actionIdentifier: String?
  private var actionSelectable = false
  private var lastStructure: NSArray?
  private var lastContent: NSArray?
  private var isApplyingProgrammaticSelection = false

  private static let tabPrefix = "veneer.tab."
  private static let actionIdentifierValue = "veneer.action"
  private static let tabIconSize: CGFloat = 25

  override init() {
    super.init()
    controller.view.backgroundColor = .clear
    controller.view.isOpaque = false
    controller.tabBarMinimizeBehavior = .never
    controller.onLayout = { [weak self] in self?.onLayout?() }
  }

  var tabBar: UITabBar { controller.tabBar }

  func attach(to container: UIView, host: UIViewController?) {
    guard controller.view.superview !== container else { return }
    host?.addChild(controller)
    controller.view.frame = container.bounds
    controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(controller.view)
    controller.didMove(toParent: host)
  }

  func detach() {
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
    lastStructure = nil
    lastContent = nil
  }

  // MARK: - Configuration

  /// `{items: [{title, icon, selectedIcon, badge}], selectedIndex,
  ///   tintColor, action: {title, icon, selectedIcon, badge, selectable}?}`
  func update(_ args: [String: Any]) {
    let items = args["items"] as? [[String: Any]] ?? []
    let action = args["action"] as? [String: Any]

    // Replace tabs only when the bar's structure changes; replacing restarts
    // UIKit's layout and selection state. Icons, titles and badges update in
    // place on the existing UITabs, the way a UIKit app would, so badge and
    // image changes animate natively.
    let structure: NSArray = [items.count, action != nil, (action?["selectable"] as? Bool) ?? false]
    let content: NSArray = [items, action ?? NSNull()]
    if lastStructure != structure {
      lastStructure = structure
      lastContent = content
      rebuildTabs(items: items, action: action)
    } else if lastContent != content {
      lastContent = content
      updateTabs(items: items, action: action)
    }

    controller.tabBar.tintColor = (args["tintColor"] as? NSNumber).map(UIColor.init(argb:))
    select(index: (args["selectedIndex"] as? NSNumber)?.intValue ?? 0)

    // Attach the delegate only after tabs and selection exist: UIKit calls
    // it synchronously for programmatic changes too.
    if controller.delegate == nil { controller.delegate = self }
  }

  private func rebuildTabs(items: [[String: Any]], action: [String: Any]?) {
    var tabs: [UITab] = items.enumerated().map { index, item in
      let tab = UITab(
        title: item["title"] as? String ?? "",
        image: icon(item["icon"]),
        identifier: "\(Self.tabPrefix)\(index)"
      ) { _ in PassthroughTabContentController() }
      configure(tab, from: item)
      return tab
    }
    tabIdentifiers = tabs.map(\.identifier)

    if let action {
      let search = UISearchTab { _ in PassthroughTabContentController() }
      search.automaticallyActivatesSearch = false
      search.title = action["title"] as? String ?? ""
      if let image = icon(action["icon"]) { search.image = image }
      configure(search, from: action)
      tabs.append(search)
      actionIdentifier = search.identifier
      actionSelectable = (action["selectable"] as? Bool) ?? false
    } else {
      actionIdentifier = nil
      actionSelectable = false
    }

    isApplyingProgrammaticSelection = true
    controller.setTabs(tabs, animated: false)
    if #available(iOS 27.0, *) {
      controller.setProminentTabIdentifier(actionIdentifier, animated: false)
    }
    isApplyingProgrammaticSelection = false
  }

  private func updateTabs(items: [[String: Any]], action: [String: Any]?) {
    for (identifier, item) in zip(tabIdentifiers, items) {
      guard let tab = controller.tab(forIdentifier: identifier) else { continue }
      tab.title = item["title"] as? String ?? ""
      tab.image = icon(item["icon"])
      configure(tab, from: item)
    }
    if let action, let actionIdentifier, let tab = controller.tab(forIdentifier: actionIdentifier) {
      tab.title = action["title"] as? String ?? ""
      if let image = icon(action["icon"]) { tab.image = image }
      configure(tab, from: action)
    }
  }

  private func configure(_ tab: UITab, from item: [String: Any]) {
    if #available(iOS 26.1, *) {
      tab.selectedImage = icon(item["selectedIcon"])
    }
    tab.badgeValue = item["badge"] as? String
    if let label = item["title"] as? String, !label.isEmpty { tab.accessibilityIdentifier = label }
  }

  private func icon(_ raw: Any?) -> UIImage? {
    guard let descriptor = NativeIconDescriptor(raw) else { return nil }
    // Symbols stay unconfigured so the tab bar applies its own metrics.
    return NativeIconRenderer.shared.image(
      for: descriptor, pointSize: descriptor.isSymbol ? nil : Self.tabIconSize)
  }

  private func select(index: Int) {
    let identifier: String? =
      index < tabIdentifiers.count
      ? tabIdentifiers[index]
      : (actionSelectable && index == tabIdentifiers.count ? actionIdentifier : nil)
    guard let identifier, let tab = controller.tab(forIdentifier: identifier),
      controller.selectedTab !== tab
    else { return }
    isApplyingProgrammaticSelection = true
    controller.selectedTab = tab
    isApplyingProgrammaticSelection = false
  }

  func setHidden(_ hidden: Bool) {
    guard controller.isTabBarHidden != hidden else { return }
    controller.setTabBarHidden(hidden, animated: true)
  }

  var isHidden: Bool { controller.isTabBarHidden }

  // MARK: - Hit testing

  /// Chrome takes a touch only when it lands on the bar itself (including
  /// the detached trailing button); everywhere else it falls through.
  func hitTest(_ point: CGPoint, in container: UIView, with event: UIEvent?) -> UIView? {
    guard !controller.isTabBarHidden,
      let hit = controller.view.hitTest(container.convert(point, to: controller.view), with: event),
      hit.isDescendant(of: controller.tabBar)
    else { return nil }
    return hit
  }

  // MARK: - UITabBarControllerDelegate

  func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
    guard tab.identifier == actionIdentifier, !actionSelectable else { return true }
    if !isApplyingProgrammaticSelection { onEvent?("tabActionPressed", nil) }
    return false
  }

  func tabBarController(
    _ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?
  ) {
    guard !isApplyingProgrammaticSelection else { return }
    if let index = tabIdentifiers.firstIndex(of: selectedTab.identifier) {
      onEvent?("tabSelected", ["index": index])
    } else if selectedTab.identifier == actionIdentifier {
      onEvent?("tabSelected", ["index": tabIdentifiers.count])
    }
  }
}

/// Reports layout so the overlay can forward the bar's height to Flutter.
@available(iOS 26.0, *)
final class ChromeTabBarController: UITabBarController {
  var onLayout: (() -> Void)?

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    onLayout?()
  }
}

/// Empty tab content: clear, and invisible to hit testing, so Flutter
/// underneath keeps receiving every touch outside the bar.
@available(iOS 26.0, *)
final class PassthroughTabContentController: UIViewController {
  override func loadView() {
    let view = UIView()
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    self.view = view
  }
}
