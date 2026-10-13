import Flutter
import UIKit

/// Platform views for `GlassBackground`: Liquid Glass *under* Flutter
/// content (a dock, a field, a pill holding Flutter text), where the
/// overlay's shapes, which always draw above Flutter, can't go.
final class GlassBackgroundFactory: NSObject, FlutterPlatformViewFactory {
  static let viewType = "veneer/glass_background"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    guard #available(iOS 26.0, *) else { return PlainPlatformView(frame: frame) }
    return GlassBackgroundPlatformView(
      frame: frame, viewId: viewId, args: args as? [String: Any] ?? [:], messenger: messenger)
  }
}

/// Dart only asks for glass on iOS 26; anything older gets an empty view.
private final class PlainPlatformView: NSObject, FlutterPlatformView {
  private let host: UIView

  init(frame: CGRect) {
    host = UIView(frame: frame)
    host.isUserInteractionEnabled = false
  }

  func view() -> UIView { host }
}

/// `{style: regular|clear, tint?, cornerRadius? (nil: capsule), tappable}`.
/// A tappable background is interactive glass (UIKit's press response) and
/// reports `tap` on `veneer/glass_background_<id>`; otherwise it takes no
/// touches.
@available(iOS 26.0, *)
private final class GlassBackgroundPlatformView: NSObject, FlutterPlatformView {
  private let glassView: UIVisualEffectView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "veneer/glass_background_\(viewId)", binaryMessenger: messenger)
    let tappable = (args["tappable"] as? Bool) == true
    let glass = UIGlassEffect(style: (args["style"] as? String) == "clear" ? .clear : .regular)
    glass.tintColor = (args["tint"] as? NSNumber).map(UIColor.init(argb:))
    glass.isInteractive = tappable
    glassView = UIVisualEffectView(effect: glass)
    glassView.frame = frame
    if let radius = (args["cornerRadius"] as? NSNumber).map({ CGFloat($0.doubleValue) }) {
      glassView.cornerConfiguration = .corners(radius: .fixed(radius))
    } else {
      glassView.cornerConfiguration = .capsule()
    }
    glassView.isUserInteractionEnabled = tappable
    super.init()
    if tappable {
      glassView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
  }

  func view() -> UIView { glassView }

  @objc private func tapped() {
    channel.invokeMethod("tap", arguments: nil)
  }
}
