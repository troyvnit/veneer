import UIKit

/// The region of the overlay a piece of native chrome lives in. A split
/// layout gives each column its own pane, so each gets its own navigation
/// bar and edge effects, and a tab bar or composer stays inside its column.
/// Without one, chrome spans the whole overlay as before.
struct ChromePane: Equatable {
  static let full = ChromePane(id: "", left: nil, width: nil)

  let id: String
  let left: CGFloat?
  let width: CGFloat?

  private init(id: String, left: CGFloat?, width: CGFloat?) {
    self.id = id
    self.left = left
    self.width = width
  }

  /// `{id, left, width}` from Dart, or nil for the whole overlay.
  init(_ raw: Any?) {
    guard let map = raw as? [String: Any], let id = map["id"] as? String, !id.isEmpty,
      let left = (map["left"] as? NSNumber).map({ CGFloat($0.doubleValue) }),
      let width = (map["width"] as? NSNumber).map({ CGFloat($0.doubleValue) })
    else {
      self = .full
      return
    }
    self.init(id: id, left: left, width: width)
  }

  var isFull: Bool { left == nil || width == nil }

  func frame(in bounds: CGRect) -> CGRect {
    guard let left, let width else { return bounds }
    let x = min(max(0, left), bounds.width)
    return CGRect(x: x, y: 0, width: max(0, min(width, bounds.width - x)), height: bounds.height)
  }
}
