import Flutter
import UIKit

/// Plugin entry point, one instance per Flutter engine (the app's, and one
/// per native sheet).
///
/// Two transports reach the native side:
///   * `veneer` method channel — config, chrome, events (async).
///   * `veneer_apply_frame` C function called through `dart:ffi` — per-frame
///     glass geometry. On iOS the Dart UI isolate runs on the platform
///     thread (merged threads), so this call lands synchronously on the main
///     thread inside the same run-loop turn as the Flutter frame. The
///     function address is handed to Dart by `attach`, so no `dlsym` lookup
///     and no dead-stripping concerns.
///
/// The package installs on iOS 15+, but the native layer needs iOS 26
/// (Liquid Glass, `UITab`, scroll edge effects). Below that, `attach` answers
/// `unsupported` and the Dart widgets render their Flutter fallbacks.
public class VeneerPlugin: NSObject, FlutterPlugin {
  /// Live instances by id, for the FFI entry point to route each engine's
  /// frames to its own overlay.
  private static var instances: [Int: WeakPlugin] = [:]
  private static var nextId = 1

  static func instance(_ id: Int) -> VeneerPlugin? { instances[id]?.plugin }

  /// Geometry buffer shared with this engine's Dart isolate, which writes into
  /// it through an `asTypedList` view and then calls `veneer_apply_frame` —
  /// no copy, no allocation per frame.
  static let frameBufferCapacity = 2 + FrameLayout.stride * 512
  let frameBuffer: UnsafeMutablePointer<Double> = {
    let p = UnsafeMutablePointer<Double>.allocate(capacity: VeneerPlugin.frameBufferCapacity)
    p.initialize(repeating: 0, count: VeneerPlugin.frameBufferCapacity)
    return p
  }()
  let id: Int

  private let registrar: FlutterPluginRegistrar
  /// A sheet engine's request for its payload, made before it was presented.
  private var pendingPayload: FlutterResult?
  private let channel: FlutterMethodChannel
  /// Type-erased: `VeneerOverlayView` exists only on iOS 26+.
  private var overlayRef: AnyObject?
  let stats = GlassStats()

  @available(iOS 26.0, *)
  var overlay: VeneerOverlayView? { overlayRef as? VeneerOverlayView }

  init(registrar: FlutterPluginRegistrar, channel: FlutterMethodChannel) {
    self.registrar = registrar
    self.channel = channel
    id = Self.nextId
    Self.nextId += 1
    super.init()
    Self.instances[id] = WeakPlugin(plugin: self)
  }

  deinit {
    Self.instances[id] = nil
    frameBuffer.deallocate()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "veneer", binaryMessenger: registrar.messenger())
    let instance = VeneerPlugin(registrar: registrar, channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    guard #available(iOS 26.0, *) else { return }
    // Engine independent: sheet engines come and go, the app's assets stay.
    NativeIconRenderer.shared.assetPath = { asset, package in
      let key = package.map { FlutterDartProject.lookupKey(forAsset: asset, fromPackage: $0) }
        ?? FlutterDartProject.lookupKey(forAsset: asset)
      return Bundle.main.path(forResource: key, ofType: nil)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 26.0, *) else {
      // Dart checks the OS version itself; this is the backstop.
      result(
        call.method == "attach"
          ? FlutterError(code: "unsupported", message: "The native layer needs iOS 26", details: nil) : nil)
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "attach":
      guard let overlay = ensureOverlay() else {
        result(FlutterError(code: "no_view", message: "FlutterViewController not available yet", details: nil))
        return
      }
      overlay.glassLayer.defaultSpacing = CGFloat((args["spacing"] as? NSNumber)?.doubleValue ?? 16)
      // A new isolate (hot restart) attaches to the same overlay; a composer
      // the old one showed has no Dart owner left to remove it.
      overlay.setComposer(nil)
      DispatchQueue.main.async { overlay.resendLayout() }
      let fn: @convention(c) (UnsafePointer<Double>?, Int32, Int32) -> Void = veneer_apply_frame
      result([
        "applyFrameAddress": Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self)),
        "bufferAddress": Int(bitPattern: UnsafeRawPointer(frameBuffer)),
        "bufferCapacity": Self.frameBufferCapacity,
        "pluginId": id,
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

    case "configureContextMenu":
      overlay?.contextMenus.configure(args)
      result(nil)

    case "removeContextMenu":
      if let id = (args["id"] as? NSNumber)?.intValue { overlay?.contextMenus.remove(id: id) }
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

    case "setNavigationBar":
      overlay?.setNavigationBar(args)
      result(nil)

    case "navigationBarScrolled":
      overlay?.setNavigationBarScrolled((args["scrolled"] as? Bool) ?? false)
      result(nil)

    case "removeNavigationBar":
      overlay?.setNavigationBar(nil)
      result(nil)

    case "setComposer":
      overlay?.setComposer(args)
      result(nil)

    case "removeComposer":
      overlay?.setComposer(nil)
      result(nil)

    case "composerCommand":
      overlay?.composerCommand(args)
      result(nil)

    case "setChromeHidden":
      overlay?.setChromeHidden((args["hidden"] as? Bool) ?? false)
      result(nil)

    case "prewarmSheet":
      if let entrypoint = args["entrypoint"] as? String {
        NativeSheetPresenter.shared.prewarm(entrypoint: entrypoint, libraryURI: args["libraryUri"] as? String)
      }
      result(nil)

    case "presentSheet":
      let presented = NativeSheetPresenter.shared.present(args, owner: id, from: registrar.viewController) {
        [weak self] method, payload in
        self?.channel.invokeMethod(method, arguments: payload)
      }
      result(presented)

    case "sheetContentAtTop":
      overlay?.setSheetContentAtTop((args["atTop"] as? Bool) ?? true)
      result(nil)

    case "sheetContentHeight":
      if let height = (args["height"] as? NSNumber).map({ CGFloat($0.doubleValue) }) {
        NativeSheetPresenter.shared.session(showing: registrar.viewController)?.setContentHeight(height)
      }
      result(nil)

    case "sheetPayload":
      if let session = NativeSheetPresenter.shared.session(showing: registrar.viewController) {
        result(session.payload)
      } else {
        pendingPayload?(nil)
        pendingPayload = result
      }

    case "dismissSheet":
      // From inside a sheet: dismiss the sheet showing this engine.
      let session = (args["id"] as? NSNumber).flatMap { NativeSheetPresenter.shared.session(owner: id, id: $0.intValue) }
        ?? NativeSheetPresenter.shared.session(showing: registrar.viewController)
      session?.dismiss(result: args["result"])
      result(session != nil)

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

  /// A sheet showing [controller] was dismissed: its engine's overlay goes.
  @available(iOS 26.0, *)
  static func tearDownSheet(_ controller: UIViewController) {
    for plugin in instances.values.compactMap({ $0.plugin }) where plugin.registrar.viewController === controller {
      plugin.pendingPayload?(nil)
      plugin.pendingPayload = nil
      plugin.overlay?.tearDown()
      plugin.overlayRef = nil
    }
  }

  /// Answers a sheet engine that asked for its payload before [controller]
  /// was presented.
  static func deliverSheetMaximumHeight(to controller: UIViewController, _ height: CGFloat) {
    for plugin in instances.values.compactMap({ $0.plugin }) where plugin.registrar.viewController === controller {
      plugin.channel.invokeMethod("sheetMaximumHeight", arguments: ["height": Double(height)])
    }
  }

  static func deliverSheetPayload(to controller: UIViewController, _ payload: Any?) {
    for plugin in instances.values.compactMap({ $0.plugin }) where plugin.registrar.viewController === controller {
      plugin.pendingPayload?(payload)
      plugin.pendingPayload = nil
    }
  }

  // MARK: - Overlay

  @available(iOS 26.0, *)
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
    overlayRef = overlay
    return overlay
  }

  // MARK: - Frame application

  enum Transport { case ffi, channel }

  @available(iOS 26.0, *)
  func applyFrame(_ ptr: UnsafePointer<Double>?, count: Int, transport: Transport) {
    guard let ptr, count >= 2, let overlay else { return }
    let start = CACurrentMediaTime()
    let buffer = UnsafeBufferPointer(start: ptr, count: count)
    overlay.glassLayer.apply(buffer)
    overlay.setComposerOffset(FrameLayout.composerOffset(in: buffer))
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
func veneer_apply_frame(_ ptr: UnsafePointer<Double>?, _ count: Int32, _ pluginId: Int32) {
  guard #available(iOS 26.0, *), let plugin = VeneerPlugin.instance(Int(pluginId)) else { return }
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

private struct WeakPlugin {
  weak var plugin: VeneerPlugin?
}

/// Per-shape layout of the frame buffer, shared by Dart's `GlassCoordinator`
/// and `GlassLayerView.apply`.
enum FrameLayout {
  static let stride = 20
  /// Entry id carrying the active composer's page displacement (dx, dy)
  /// instead of a shape.
  static let composerHostId = -1

  static func composerOffset(in buf: UnsafeBufferPointer<Double>) -> CGPoint {
    guard buf.count >= 2 else { return .zero }
    let count = Int(buf[1])
    guard buf.count >= 2 + count * stride else { return .zero }
    for i in 0..<count {
      let o = 2 + i * stride
      if Int(buf[o]) == composerHostId { return CGPoint(x: buf[o + 1], y: buf[o + 2]) }
    }
    return .zero
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
