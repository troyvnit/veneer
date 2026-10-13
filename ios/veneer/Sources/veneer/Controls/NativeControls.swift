import Flutter
import UIKit

/// Platform views for leaf UIKit controls — `UISwitch`, `UISlider`,
/// `UISegmentedControl`, a menu button — laid out by Flutter like any widget. Each view
/// talks on `veneer/<kind>_<id>`: Dart sends `update` with the full
/// configuration, the control reports user changes back.
final class NativeControlFactory: NSObject, FlutterPlatformViewFactory {
  enum Kind: String, CaseIterable {
    case `switch`, slider, segmented, menu, navbar

    var viewType: String { "veneer/\(rawValue)" }
  }

  private let kind: Kind
  private let messenger: FlutterBinaryMessenger

  init(kind: Kind, messenger: FlutterBinaryMessenger) {
    self.kind = kind
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let channel = FlutterMethodChannel(name: "\(kind.viewType)_\(viewId)", binaryMessenger: messenger)
    let config = args as? [String: Any] ?? [:]
    switch kind {
    case .switch: return NativeSwitchView(frame: frame, channel: channel, config: config)
    case .slider: return NativeSliderView(frame: frame, channel: channel, config: config)
    case .segmented: return NativeSegmentedView(frame: frame, channel: channel, config: config)
    case .menu:
      guard #available(iOS 26.0, *) else { return EmptyControlView(frame: frame) }
      return NativeMenuButtonView(frame: frame, channel: channel, config: config)
    case .navbar:
      guard #available(iOS 26.0, *) else { return EmptyControlView(frame: frame) }
      // Platform views are always created on the main thread.
      return MainActor.assumeIsolated { NativeNavigationBarView(frame: frame, channel: channel, config: config) }
    }
  }
}

/// Dart only asks for the menu button on iOS 26; anything older gets an empty view.
private final class EmptyControlView: NSObject, FlutterPlatformView {
  private let host: UIView

  init(frame: CGRect) {
    host = UIView(frame: frame)
    host.isUserInteractionEnabled = false
  }

  func view() -> UIView { host }
}

/// Centres a control of fixed intrinsic size in the frame Flutter gives it.
private final class ControlHost: UIView {
  let control: UIView
  var stretches = false

  init(frame: CGRect, control: UIView) {
    self.control = control
    super.init(frame: frame)
    backgroundColor = .clear
    addSubview(control)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layoutSubviews() {
    super.layoutSubviews()
    if stretches {
      control.frame = bounds
    } else {
      let size = control.intrinsicContentSize
      control.frame = CGRect(
        x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
        width: size.width, height: size.height)
    }
  }
}

private extension Dictionary where Key == String, Value == Any {
  func color(_ key: String) -> UIColor? { (self[key] as? NSNumber).map(UIColor.init(argb:)) }
  func double(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
}

private final class NativeSwitchView: NSObject, FlutterPlatformView {
  private let control = UISwitch()
  private let host: ControlHost
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, config: [String: Any]) {
    self.channel = channel
    host = ControlHost(frame: frame, control: control)
    super.init()
    apply(config, animated: false)
    control.addTarget(self, action: #selector(changed), for: .valueChanged)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update", let config = call.arguments as? [String: Any] { self?.apply(config, animated: true) }
      result(nil)
    }
  }

  func view() -> UIView { host }

  private func apply(_ config: [String: Any], animated: Bool) {
    let on = (config["value"] as? Bool) ?? false
    if control.isOn != on { control.setOn(on, animated: animated) }
    control.isEnabled = (config["enabled"] as? Bool) ?? true
    control.onTintColor = config.color("activeColor")
    control.thumbTintColor = config.color("thumbColor")
  }

  @objc private func changed() {
    channel.invokeMethod("valueChanged", arguments: ["value": control.isOn])
  }
}

private final class NativeSliderView: NSObject, FlutterPlatformView {
  private let control = UISlider()
  private let host: ControlHost
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, config: [String: Any]) {
    self.channel = channel
    host = ControlHost(frame: frame, control: control)
    host.stretches = true
    super.init()
    apply(config)
    control.addTarget(self, action: #selector(changed), for: .valueChanged)
    control.addTarget(self, action: #selector(began), for: .touchDown)
    control.addTarget(self, action: #selector(ended), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update", let config = call.arguments as? [String: Any] { self?.apply(config) }
      result(nil)
    }
  }

  func view() -> UIView { host }

  private func apply(_ config: [String: Any]) {
    control.minimumValue = Float(config.double("min") ?? 0)
    control.maximumValue = Float(config.double("max") ?? 1)
    // Never fight the finger: Dart echoes values back while it drags.
    if !control.isTracking { control.value = Float(config.double("value") ?? 0) }
    control.isEnabled = (config["enabled"] as? Bool) ?? true
    control.minimumTrackTintColor = config.color("activeColor")
    control.thumbTintColor = config.color("thumbColor")
  }

  private func send(_ method: String) {
    channel.invokeMethod(method, arguments: ["value": Double(control.value)])
  }

  @objc private func changed() { send("valueChanged") }
  @objc private func began() { send("changeStart") }
  @objc private func ended() { send("changeEnd") }
}

private final class NativeSegmentedView: NSObject, FlutterPlatformView {
  private let control = UISegmentedControl()
  private let host: ControlHost
  private let channel: FlutterMethodChannel
  private var labels: [String] = []

  init(frame: CGRect, channel: FlutterMethodChannel, config: [String: Any]) {
    self.channel = channel
    host = ControlHost(frame: frame, control: control)
    host.stretches = true
    super.init()
    apply(config)
    control.addTarget(self, action: #selector(changed), for: .valueChanged)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update", let config = call.arguments as? [String: Any] { self?.apply(config) }
      result(nil)
    }
  }

  func view() -> UIView { host }

  private func apply(_ config: [String: Any]) {
    let labels = config["labels"] as? [String] ?? []
    if labels != self.labels {
      self.labels = labels
      control.removeAllSegments()
      for (i, label) in labels.enumerated() { control.insertSegment(withTitle: label, at: i, animated: false) }
    }
    let selected = (config["selectedIndex"] as? NSNumber)?.intValue ?? UISegmentedControl.noSegment
    if control.selectedSegmentIndex != selected { control.selectedSegmentIndex = selected }
    control.isEnabled = (config["enabled"] as? Bool) ?? true
    control.selectedSegmentTintColor = config.color("selectedColor")
    var normal: [NSAttributedString.Key: Any] = [:]
    var selectedText: [NSAttributedString.Key: Any] = [:]
    if let color = config.color("textColor") { normal[.foregroundColor] = color }
    if let color = config.color("selectedTextColor") { selectedText[.foregroundColor] = color }
    control.setTitleTextAttributes(normal, for: .normal)
    control.setTitleTextAttributes(selectedText, for: .selected)
  }

  @objc private func changed() {
    channel.invokeMethod("valueChanged", arguments: ["index": control.selectedSegmentIndex])
  }
}

/// An invisible button over Flutter content that opens a `UIMenu` on tap:
/// `{menu, menuTitle?}`, reporting `menuItem {index}`. For menus inside
/// content the overlay can't follow, such as a Flutter-drawn sheet.
@available(iOS 26.0, *)
private final class NativeMenuButtonView: NSObject, FlutterPlatformView {
  private let button = UIButton(type: .custom)
  private let host: ControlHost
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, config: [String: Any]) {
    self.channel = channel
    host = ControlHost(frame: frame, control: button)
    host.stretches = true
    super.init()
    button.showsMenuAsPrimaryAction = true
    // Keep the Dart order even when the menu opens upward.
    button.preferredMenuElementOrder = .fixed
    apply(config)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update", let config = call.arguments as? [String: Any] { self?.apply(config) }
      result(nil)
    }
  }

  func view() -> UIView { host }

  private func apply(_ config: [String: Any]) {
    button.menu = NativeMenu.make(config["menu"], id: "menu", title: config["menuTitle"] as? String) {
      [weak self] item in
      guard let index = Int(item.components(separatedBy: ".menu").last ?? "") else { return }
      self?.channel.invokeMethod("menuItem", arguments: ["index": index])
    }
  }
}

/// The overlay's `UINavigationBar` (`NativeNavigationBarHost`) in a
/// platform view, for bars inside content the overlay can't follow, such as
/// a Flutter-drawn sheet. Takes the same configuration and reports the same
/// `navItemPressed {id}` events.
@available(iOS 26.0, *)
@MainActor
private final class NativeNavigationBarView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let host = NativeNavigationBarHost()
  private let channel: FlutterMethodChannel

  init(frame: CGRect, channel: FlutterMethodChannel, config: [String: Any]) {
    self.channel = channel
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    super.init()
    host.attach(to: container)
    host.onEvent = { [weak self] method, payload in self?.channel.invokeMethod(method, arguments: payload) }
    host.update(config)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update", let config = call.arguments as? [String: Any] { self?.host.update(config) }
      result(nil)
    }
  }

  func view() -> UIView { container }
}

/// `UIAlertController` alerts: `{title, message?, tint?, actions: [{title,
/// style: normal|cancel|destructive, preferred?}]}`, answering with the
/// picked action's index.
@available(iOS 26.0, *)
enum NativeAlert {
  static func present(_ args: [String: Any], from root: UIViewController?, result: @escaping FlutterResult) {
    guard var presenter = root else {
      result(nil)
      return
    }
    while let presented = presenter.presentedViewController, !presented.isBeingDismissed { presenter = presented }
    let alert = UIAlertController(
      title: args["title"] as? String, message: args["message"] as? String, preferredStyle: .alert)
    var hasCancel = false
    for (index, item) in (args["actions"] as? [[String: Any]] ?? []).enumerated() {
      var style: UIAlertAction.Style
      switch item["style"] as? String {
      case "cancel": style = .cancel
      case "destructive": style = .destructive
      default: style = .default
      }
      // UIKit allows one cancel action; a second would throw.
      if style == .cancel {
        if hasCancel { style = .default }
        hasCancel = true
      }
      let action = UIAlertAction(title: item["title"] as? String, style: style) { _ in result(index) }
      alert.addAction(action)
      if (item["preferred"] as? Bool) == true { alert.preferredAction = action }
    }
    if let tint = (args["tint"] as? NSNumber).map(UIColor.init(argb:)) { alert.view.tintColor = tint }
    presenter.present(alert, animated: true)
  }
}
