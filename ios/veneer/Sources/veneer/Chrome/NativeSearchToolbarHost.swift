import UIKit

/// UIKit's own search, integrated into the bottom toolbar the way Settings
/// and Passwords show it on iOS 26: a real `UISearchController` on a
/// navigation item with `.integrated` placement, in a
/// `UINavigationController` whose toolbar is the only thing drawn. The
/// field, its dictation microphone, the clear and close buttons and the ride
/// on the keyboard are all UIKit's.
///
/// Like the tab bar, the controller is a child of the `FlutterViewController`
/// with its view in the Veneer overlay. Its content is empty and
/// touch-transparent: Flutter keeps drawing the page underneath and receives
/// every touch outside the bar.
@available(iOS 26.0, *)
final class NativeSearchToolbarHost: NSObject, UISearchBarDelegate, UISearchControllerDelegate {
  var onEvent: ((String, Any?) -> Void)?
  /// Called when the bar's frame may have changed.
  var onLayout: (() -> Void)?

  let navigation: ChromeNavigationController
  private let content = PassthroughTabContentController()
  private let search = UISearchController(searchResultsController: nil)
  /// Set while veneer itself deactivates the search, so that isn't reported
  /// as the user closing it.
  private var deactivating = false

  override init() {
    navigation = ChromeNavigationController(rootViewController: content)
    super.init()
    navigation.view.backgroundColor = .clear
    navigation.view.isOpaque = false
    navigation.setNavigationBarHidden(true, animated: false)
    navigation.setToolbarHidden(false, animated: false)
    navigation.onLayout = { [weak self] in self?.onLayout?() }
    search.obscuresBackgroundDuringPresentation = false
    search.hidesNavigationBarDuringPresentation = false
    search.delegate = self
    search.searchBar.delegate = self
    search.searchBar.autocorrectionType = .no
    content.navigationItem.searchController = search
    content.navigationItem.preferredSearchBarPlacement = .integrated
    content.toolbarItems = [content.navigationItem.searchBarPlacementBarButtonItem]
  }

  var searchBar: UISearchBar { search.searchBar }

  func attach(to container: UIView, host: UIViewController?) {
    guard navigation.view.superview !== container else { return }
    host?.addChild(navigation)
    navigation.view.frame = container.bounds
    navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(navigation.view)
    navigation.didMove(toParent: host)
  }

  func detach() {
    deactivating = true
    searchBar.resignFirstResponder()
    search.isActive = false
    deactivating = false
    navigation.willMove(toParent: nil)
    navigation.view.removeFromSuperview()
    navigation.removeFromParent()
  }

  func update(_ args: [String: Any]) {
    let placeholder = args["placeholder"] as? String
    if searchBar.placeholder != placeholder { searchBar.placeholder = placeholder }
    if let text = args["text"] as? String, searchBar.text != text { searchBar.text = text }
    setHidden((args["hidden"] as? Bool) ?? false)
  }

  func command(_ args: [String: Any]) {
    switch args["command"] as? String {
    case "focus":
      focus(attempts: Self.focusAttempts)
    case "unfocus":
      searchBar.resignFirstResponder()
    case "setText":
      searchBar.text = args["text"] as? String ?? ""
    default: break
    }
  }

  private static let focusAttempts = 10

  /// Puts the bar in search mode, its close button showing, with the
  /// keyboard. UIKit only moves the field into its floating bar once the
  /// controller is on screen; until then it can't take the keyboard, so keep
  /// trying briefly.
  private func focus(attempts: Int) {
    search.isActive = true
    let field = searchBar.searchTextField
    if field.window != nil, field.isFirstResponder || field.becomeFirstResponder() { return }
    guard attempts > 1 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.focus(attempts: attempts - 1) }
  }

  /// While its page is covered the bar keeps its state, hidden: it comes
  /// back as it was left, in search mode and without the keyboard.
  private(set) var isHidden = false

  private func setHidden(_ hidden: Bool) {
    guard hidden != isHidden else { return }
    isHidden = hidden
    if hidden { searchBar.resignFirstResponder() }
    navigation.view.isHidden = hidden
  }

  /// The top of the bar, in `container`'s coordinates: the floating bar UIKit
  /// hosts the field in, above the keyboard while it's up.
  func chromeTop(in container: UIView) -> CGFloat? {
    guard navigation.view.superview === container, !isHidden, searchBar.searchTextField.window != nil else { return nil }
    var bar: UIView = searchBar.searchTextField
    while let parent = bar.superview, parent !== navigation.view, !covers(parent, container) { bar = parent }
    return bar.convert(bar.bounds, to: container).minY
  }

  /// UIKit draws the integrated bar in a floating container of its own, not
  /// in the toolbar; everything it hosts there is smaller than the screen,
  /// while its full-screen containers must let touches through to Flutter.
  func hitTest(_ point: CGPoint, in container: UIView, with event: UIEvent?) -> UIView? {
    guard navigation.view.superview === container, !isHidden,
      let hit = navigation.view.hitTest(container.convert(point, to: navigation.view), with: event)
    else { return nil }
    return covers(hit, container) ? nil : hit
  }

  private func covers(_ view: UIView, _ container: UIView) -> Bool {
    view.convert(view.bounds, to: container).height >= container.bounds.height - 1
  }

  // MARK: - UISearchBarDelegate

  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    onEvent?("searchToolbar", ["kind": "text", "value": searchText])
  }

  func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
    onEvent?("searchToolbar", ["kind": "focus", "value": true])
  }

  func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
    onEvent?("searchToolbar", ["kind": "focus", "value": false])
  }

  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    onEvent?("searchToolbar", ["kind": "submit", "value": searchBar.text ?? ""])
    searchBar.resignFirstResponder()
  }

  // MARK: - UISearchControllerDelegate

  func willDismissSearchController(_ searchController: UISearchController) {
    guard !deactivating else { return }
    onEvent?("searchToolbar", ["kind": "close", "value": true])
  }
}

/// Reports layout so the overlay can forward the search bar's height to
/// Flutter.
@available(iOS 26.0, *)
final class ChromeNavigationController: UINavigationController {
  var onLayout: (() -> Void)?

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    onLayout?()
  }
}
