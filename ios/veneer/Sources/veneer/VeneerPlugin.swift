import Flutter
import UIKit

/// Plugin entry point.
///
/// Two transports reach the native side:
///   * `veneer` method channel — config, chrome, events (async).
///   * `veneer_apply_frame` C function called through `dart:ffi` — per-frame
///     glass geometry. On iOS the Dart UI isolate runs on the platform
///     thread (merged threads), so this call lands synchronously on the main
///     thread inside the same run-loop turn as the Flutter frame. The
///     function address is handed to Dart by `attach`, so no `dlsym` lookup
///     and no dead-stripping concerns.
public class VeneerPlugin: NSObject, FlutterPlugin {
  static var shared: VeneerPlugin?

  /// Geometry buffer shared with Dart, which writes into it through an
  /// `asTypedList` view and then calls `veneer_apply_frame` — no copy, no
  /// allocation per frame. Lives for the process lifetime.
  static let frameBufferCapacity = 2 + GlassLayerView.stride * 512
  static let frameBuffer: UnsafeMutablePointer<Double> = {
    let p = UnsafeMutablePointer<Double>.allocate(capacity: frameBufferCapacity)
    p.initialize(repeating: 0, count: frameBufferCapacity)
    return p
  }()

  private let registrar: FlutterPluginRegistrar
  private let channel: FlutterMethodChannel
  private(set) var overlay: VeneerOverlayView?
  let stats = GlassStats()

  init(registrar: FlutterPluginRegistrar, channel: FlutterMethodChannel) {
    self.registrar = registrar
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "veneer", binaryMessenger: registrar.messenger())
    let instance = VeneerPlugin(registrar: registrar, channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    shared = instance
    NativeIconRenderer.shared.assetPath = { [weak registrar] asset, package in
      guard let registrar else { return nil }
      let key = package.map { registrar.lookupKey(forAsset: asset, fromPackage: $0) } ?? registrar.lookupKey(forAsset: asset)
      return Bundle.main.path(forResource: key, ofType: nil)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "attach":
      guard let overlay = ensureOverlay() else {
        result(FlutterError(code: "no_view", message: "FlutterViewController not available yet", details: nil))
        return
      }
      overlay.glassLayer.defaultSpacing = CGFloat((args["spacing"] as? NSNumber)?.doubleValue ?? 16)
      let fn: @convention(c) (UnsafePointer<Double>?, Int32) -> Void = veneer_apply_frame
      result([
        "applyFrameAddress": Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self)),
        "bufferAddress": Int(bitPattern: UnsafeRawPointer(Self.frameBuffer)),
        "bufferCapacity": Self.frameBufferCapacity,
      ])

    case "applyFrame":
      // Async transport, kept for A/B comparison against FFI.
      guard let data = call.arguments as? FlutterStandardTypedData else { return result(nil) }
      data.data.withUnsafeBytes { raw in
        let buf = raw.bindMemory(to: Double.self)
        applyFrame(buf.baseAddress, count: buf.count, transport: .channel)
      }
      result(nil)

    case "configureShape":
      overlay?.glassLayer.configure(GlassShapeConfig(args))
      result(nil)

    case "removeShape":
      if let id = (args["id"] as? NSNumber)?.intValue { overlay?.glassLayer.remove(id: id) }
      result(nil)

    case "setSpacing":
      overlay?.glassLayer.defaultSpacing = CGFloat((args["spacing"] as? NSNumber)?.doubleValue ?? 16)
      result(nil)

    case "configureGroup":
      overlay?.glassLayer.configureGroup(GlassGroupConfig(args))
      result(nil)

    case "removeGroup":
      if let id = (args["id"] as? NSNumber)?.intValue { overlay?.glassLayer.removeGroup(id: id) }
      result(nil)

    case "setTabBar":
      overlay?.setTabBar(args)
      result(nil)

    case "removeTabBar":
      overlay?.setTabBar(nil)
      result(nil)

    case "setChromeHidden":
      overlay?.setChromeHidden((args["hidden"] as? Bool) ?? false)
      result(nil)

    case "getStats":
      var snapshot = stats.snapshot()
      overlay?.glassLayer.diagnostics.forEach { snapshot[$0.key] = $0.value }
      snapshot["overlayInWindow"] = overlay?.window != nil
      result(snapshot)

    case "resetStats":
      stats.reset()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Overlay

  private func ensureOverlay() -> VeneerOverlayView? {
    if let overlay, overlay.superview != nil { return overlay }
    guard let flutterView = registrar.viewController?.view else { return nil }
    let overlay = VeneerOverlayView(frame: flutterView.bounds)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.hostViewController = registrar.viewController
    overlay.onEvent = { [weak self] method, payload in
      self?.channel.invokeMethod(method, arguments: payload)
    }
    flutterView.addSubview(overlay)
    self.overlay = overlay
    return overlay
  }

  // MARK: - Frame application

  enum Transport { case ffi, channel }

  func applyFrame(_ ptr: UnsafePointer<Double>?, count: Int, transport: Transport) {
    guard let ptr, count >= 2, let overlay else { return }
    let start = CACurrentMediaTime()
    overlay.glassLayer.apply(UnsafeBufferPointer(start: ptr, count: count))
    // Reordering subviews can trigger layout; never do it inside the frame.
    DispatchQueue.main.async { overlay.keepOnTop() }
    stats.record(
      transport: transport,
      onMain: Thread.isMainThread,
      durationMs: (CACurrentMediaTime() - start) * 1000
    )
  }
}

/// FFI entry point. Buffer layout: see `GlassLayerView.apply`.
///
/// Called as a non-leaf FFI call: UIKit may re-enter Dart (e.g. viewport
/// metrics from `viewDidLayoutSubviews`), which deadlocks under a leaf call.
/// `GlassLayerView.apply` still avoids forcing layout, to keep the Flutter
/// frame from being re-entered.
@_cdecl("veneer_apply_frame")
func veneer_apply_frame(_ ptr: UnsafePointer<Double>?, _ count: Int32) {
  guard let plugin = VeneerPlugin.shared else { return }
  if Thread.isMainThread {
    MainActor.assumeIsolated {
      plugin.applyFrame(ptr, count: Int(count), transport: .ffi)
    }
  } else {
    // Unmerged threads: copy and hop. This reintroduces the async lag the
    // FFI path exists to avoid, and shows up as `offMainApplies` in stats.
    let copy = Array(UnsafeBufferPointer(start: ptr, count: Int(count)))
    DispatchQueue.main.async {
      copy.withUnsafeBufferPointer { plugin.applyFrame($0.baseAddress, count: $0.count, transport: .ffi) }
    }
  }
}

/// Counters exposed to the example app's diagnostics panel.
final class GlassStats {
  private var ffiApplies = 0
  private var channelApplies = 0
  private var offMainApplies = 0
  private var totalMs = 0.0
  private var maxMs = 0.0

  func record(transport: VeneerPlugin.Transport, onMain: Bool, durationMs: Double) {
    switch transport {
    case .ffi: ffiApplies += 1
    case .channel: channelApplies += 1
    }
    if !onMain { offMainApplies += 1 }
    totalMs += durationMs
    maxMs = max(maxMs, durationMs)
  }

  func reset() {
    ffiApplies = 0; channelApplies = 0; offMainApplies = 0; totalMs = 0; maxMs = 0
  }

  func snapshot() -> [String: Any] {
    let n = ffiApplies + channelApplies
    return [
      "ffiApplies": ffiApplies,
      "channelApplies": channelApplies,
      "offMainApplies": offMainApplies,
      "avgApplyMs": n == 0 ? 0 : totalMs / Double(n),
      "maxApplyMs": maxMs,
    ]
  }
}
