import UIKit

extension UIViewController {
  /// Swaps in `veneer_present` once: a presentation aimed at a view
  /// controller that already presents a native sheet goes to the topmost
  /// sheet instead. UIKit refuses those presentations, and plugins usually
  /// present from the window's root view controller (contact pickers,
  /// calendar editors, share sheets), so without this they never appear
  /// while a sheet is up. Presentations UIKit would accept are untouched.
  static let veneerForwardPresentations: Void = {
    guard
      let original = class_getInstanceMethod(
        UIViewController.self, #selector(UIViewController.present(_:animated:completion:))),
      let forwarding = class_getInstanceMethod(
        UIViewController.self, #selector(UIViewController.veneer_present(_:animated:completion:)))
    else { return }
    method_exchangeImplementations(original, forwarding)
  }()

  // After the swap, calling `veneer_present` runs UIKit's own `present`.
  @objc private func veneer_present(
    _ viewController: UIViewController, animated: Bool, completion: (() -> Void)?
  ) {
    if VeneerPlugin.forwardsPresentationsOverSheets, #available(iOS 26.0, *),
      let target = NativeSheetPresenter.shared.presentationTarget(for: self), target !== self
    {
      target.veneer_present(viewController, animated: animated, completion: completion)
      return
    }
    veneer_present(viewController, animated: animated, completion: completion)
  }
}
