import Flutter
import UIKit

/// Real UIKit sheets for Flutter content.
///
/// A sheet is a `FlutterViewController` presented with `.pageSheet`, so
/// `UISheetPresentationController` drives everything: detents, the grabber,
/// the drag, dimming, the Liquid Glass background and the page behind
/// receding. The view is transparent, so the sheet's glass shows through
/// Flutter's content.
///
/// A Flutter engine renders into one view at a time, so each sheet runs its
/// own engine, spawned from a shared `FlutterEngineGroup` (which shares the
/// compiled code and GPU context, so a spawn is cheap) at a Dart entrypoint.
/// Engines can be pre-warmed so content is ready the moment the sheet slides
/// up. Veneer registers in the sheet's engine like in the app's, so native
/// bars, composers and glass work inside the sheet.
@available(iOS 26.0, *)
final class NativeSheetPresenter {
  static let shared = NativeSheetPresenter()

  private lazy var group = FlutterEngineGroup(name: "veneer.sheets", project: nil)
  private var prewarmed: [String: FlutterEngine] = [:]
  /// Keyed by the presenting engine's plugin as well as the sheet id: each
  /// engine numbers its own sheets, so a sheet presented from inside a sheet
  /// reuses ids the app already holds.
  private var sessions: [SessionKey: NativeSheetSession] = [:]

  struct SessionKey: Hashable {
    let owner: Int
    let id: Int
  }

  /// How long a content-sized sheet waits for its first measurement before
  /// presenting anyway.
  private static let contentTimeout: TimeInterval = 0.35

  private static func key(_ entrypoint: String, _ libraryURI: String?) -> String {
    "\(libraryURI ?? "")#\(entrypoint)"
  }

  private func makeEngine(entrypoint: String, libraryURI: String?, arguments: [String]) -> FlutterEngine {
    let options = FlutterEngineGroupOptions()
    options.entrypoint = entrypoint
    options.libraryURI = libraryURI
    options.entrypointArgs = arguments
    let engine = group.makeEngine(with: options)
    Self.muteStatusBarStyle(of: engine)
    Self.registerPlugins(with: engine)
    return engine
  }

  /// iOS delivers every engine's `SystemChrome.setSystemUIOverlayStyle` to
  /// every Flutter view controller, and `MaterialApp` sends one whenever it
  /// resolves its theme — so a sheet engine (even a pre-warmed one, before
  /// its preferences load) would restyle the app's status bar. A sheet never
  /// sits under the status bar: its engine's requests are dropped, and every
  /// other platform call goes to Flutter's own handler.
  private static func muteStatusBarStyle(of engine: FlutterEngine) {
    let pluginKey = "platformPlugin"
    let handle = NSSelectorFromString("handleMethodCall:result:")
    guard engine.responds(to: NSSelectorFromString(pluginKey)),
      let plugin = engine.value(forKey: pluginKey) as? NSObject, plugin.responds(to: handle)
    else { return }
    engine.platformChannel.setMethodCallHandler { [weak plugin] call, result in
      if call.method == "SystemChrome.setSystemUIOverlayStyle" { return result(nil) }
      guard let plugin else { return result(FlutterMethodNotImplemented) }
      let block: @convention(block) (Any?) -> Void = { result($0) }
      _ = plugin.perform(handle, with: call, with: block)
    }
  }

  /// The app's `GeneratedPluginRegistrant`, found at runtime so apps need no
  /// extra setup for plugins to work inside sheets.
  private static func registerPlugins(with engine: FlutterEngine) {
    guard let registrant = NSClassFromString("GeneratedPluginRegistrant") as? NSObject.Type else { return }
    let selector = NSSelectorFromString("registerWithRegistry:")
    if registrant.responds(to: selector) { registrant.perform(selector, with: engine) }
  }

  /// Starts an engine at [entrypoint] ahead of time, for the next sheet.
  func prewarm(entrypoint: String, libraryURI: String?) {
    let key = Self.key(entrypoint, libraryURI)
    guard prewarmed[key] == nil else { return }
    prewarmed[key] = makeEngine(entrypoint: entrypoint, libraryURI: libraryURI, arguments: [])
  }

  /// `{id, entrypoint, libraryUri, arguments, detents: [{type, value}],
  ///   initialDetent, grabber, largestUndimmedDetent, dismissible,
  ///   expandsOnScroll, cornerRadius}`, from the engine of plugin [owner].
  func present(
    _ args: [String: Any], owner: Int, from presenter: UIViewController?,
    onEvent: @escaping (String, [String: Any]) -> Void
  ) -> Bool {
    guard let presenter = presenter.map(Self.topmost), let id = (args["id"] as? NSNumber)?.intValue,
      let entrypoint = args["entrypoint"] as? String
    else { return false }
    let libraryURI = args["libraryUri"] as? String
    let arguments = args["arguments"] as? [String] ?? []
    let key = Self.key(entrypoint, libraryURI)
    let sessionKey = SessionKey(owner: owner, id: id)

    let engine: FlutterEngine
    if arguments.isEmpty, let warm = prewarmed.removeValue(forKey: key) {
      engine = warm
    } else {
      engine = makeEngine(entrypoint: entrypoint, libraryURI: libraryURI, arguments: arguments)
    }

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    controller.isViewOpaque = false
    controller.view.backgroundColor = .clear
    controller.modalPresentationStyle = .pageSheet

    let session = NativeSheetSession(id: id, engine: engine, controller: controller, onEvent: onEvent)
    // A sheet presented over another sheet goes away with it.
    session.parent = sessions.values.first { $0.controller === presenter }
    session.parent?.children.append(session)
    session.onFinish = { [weak self] in
      self?.sessions[sessionKey] = nil
      if arguments.isEmpty { self?.prewarm(entrypoint: entrypoint, libraryURI: libraryURI) }
    }
    session.configure(args)
    session.payload = args["payload"] is NSNull ? nil : args["payload"]
    sessions[sessionKey] = session
    VeneerPlugin.deliverSheetPayload(to: controller, session.payload)

    let show = { [weak presenter, weak controller] in
      guard let presenter, let controller, controller.presentingViewController == nil else { return }
      presenter.present(controller, animated: true)
    }
    if session.sizesToContent {
      // Lay the sheet out off screen so its content can measure itself;
      // it slides up at that height (or at large, if it's slow to report).
      session.onFirstContentHeight = show
      controller.loadViewIfNeeded()
      controller.view.frame = presenter.view.bounds
      controller.view.setNeedsLayout()
      controller.view.layoutIfNeeded()
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.contentTimeout) { [weak session] in
        session?.presentPending()
      }
    } else {
      show()
    }
    // The next sheet (one over this, or after it) starts warm too.
    if arguments.isEmpty { prewarm(entrypoint: entrypoint, libraryURI: libraryURI) }
    return true
  }

  /// The session whose sheet shows [controller] (called from the sheet's own
  /// engine, to dismiss itself).
  func session(showing controller: UIViewController?) -> NativeSheetSession? {
    sessions.values.first { $0.controller === controller }
  }

  func session(owner: Int, id: Int) -> NativeSheetSession? { sessions[SessionKey(owner: owner, id: id)] }

  private static func topmost(_ controller: UIViewController) -> UIViewController {
    var top = controller
    while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
    return top
  }
}

/// One presented sheet: its engine, controller and delegate callbacks.
@available(iOS 26.0, *)
final class NativeSheetSession: NSObject, UISheetPresentationControllerDelegate {
  let id: Int
  let engine: FlutterEngine
  let controller: FlutterViewController
  var onFinish: (() -> Void)?
  /// Handed to the sheet's Flutter app (`NativeSheet.payload`).
  var payload: Any?
  /// The sheet this one was presented over, and those presented over it.
  weak var parent: NativeSheetSession?
  var children: [NativeSheetSession] = []
  /// Whether a detent follows the content's height, and that height (the
  /// sheet above the bottom safe area), as the sheet's engine measures it.
  private(set) var sizesToContent = false
  private var contentHeight: CGFloat?
  var onFirstContentHeight: (() -> Void)?
  private let onEvent: (String, [String: Any]) -> Void
  private var detentIds: [UISheetPresentationController.Detent.Identifier] = []
  private var result: Any?
  private var finished = false

  /// Distance from the sheet's top and side edges to header controls.
  static let edgeInset: CGFloat = 16

  init(id: Int, engine: FlutterEngine, controller: FlutterViewController, onEvent: @escaping (String, [String: Any]) -> Void) {
    self.id = id
    self.engine = engine
    self.controller = controller
    self.onEvent = onEvent
    super.init()
  }

  func configure(_ args: [String: Any]) {
    guard let sheet = controller.sheetPresentationController else { return }
    let specs = args["detents"] as? [[String: Any]] ?? [["type": "large"]]
    var detents: [UISheetPresentationController.Detent] = []
    detentIds = []
    for (i, spec) in specs.enumerated() {
      let value = (spec["value"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
      let detent: UISheetPresentationController.Detent
      switch spec["type"] as? String {
      case "medium": detent = .medium()
      case "fraction":
        detent = .custom(identifier: .init("veneer.\(i)")) { $0.maximumDetentValue * value }
      case "height":
        detent = .custom(identifier: .init("veneer.\(i)")) { min($0.maximumDetentValue, value) }
      case "content":
        sizesToContent = true
        detent = .custom(identifier: .init("veneer.\(i)")) { [weak self] context in
          self?.noteMaximumHeight(context.maximumDetentValue)
          return min(context.maximumDetentValue, self?.contentHeight ?? context.maximumDetentValue)
        }
      default: detent = .large()
      }
      detents.append(detent)
      detentIds.append(detent.identifier)
    }
    sheet.detents = detents
    if let initial = (args["initialDetent"] as? NSNumber)?.intValue, detentIds.indices.contains(initial) {
      sheet.selectedDetentIdentifier = detentIds[initial]
    }
    sheet.prefersGrabberVisible = (args["grabber"] as? Bool) ?? (detents.count > 1)
    // Header controls sit 16 pt from the sheet's top edge, concentric with
    // its corners (Apple's sheet templates); content starts below that.
    controller.additionalSafeAreaInsets.top = NativeSheetSession.edgeInset
    if let undimmed = (args["largestUndimmedDetent"] as? NSNumber)?.intValue, detentIds.indices.contains(undimmed) {
      sheet.largestUndimmedDetentIdentifier = detentIds[undimmed]
    }
    sheet.prefersScrollingExpandsWhenScrolledToEdge = (args["expandsOnScroll"] as? Bool) ?? true
    sheet.prefersEdgeAttachedInCompactHeight = true
    if let radius = (args["cornerRadius"] as? NSNumber).map({ CGFloat($0.doubleValue) }) {
      sheet.preferredCornerRadius = radius
    }
    sheet.delegate = self
    controller.isModalInPresentation = !((args["dismissible"] as? Bool) ?? true)
  }

  /// The tallest the sheet can get, for its engine: content shorter than
  /// that is growing the sheet to fit, content that reaches it scrolls.
  private var maximumHeight: CGFloat?

  private func noteMaximumHeight(_ height: CGFloat) {
    guard abs((maximumHeight ?? -1) - height) > 0.5 else { return }
    maximumHeight = height
    // Detents resolve during layout: tell the engine afterwards.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      VeneerPlugin.deliverSheetMaximumHeight(to: self.controller, height)
    }
  }

  /// The content measured [height]: the sheet follows it, animated once
  /// it's on screen.
  func setContentHeight(_ height: CGFloat) {
    guard sizesToContent, height > 0 else { return }
    let first = contentHeight == nil
    guard first || abs((contentHeight ?? 0) - height) > 0.5 else { return }
    contentHeight = height
    if first {
      presentPending()
    } else if let sheet = controller.sheetPresentationController {
      sheet.animateChanges { sheet.invalidateDetents() }
    }
  }

  /// Presents a content-sized sheet still waiting for its measurement.
  func presentPending() {
    let show = onFirstContentHeight
    onFirstContentHeight = nil
    controller.sheetPresentationController?.invalidateDetents()
    show?()
  }

  /// Dismisses with a result for the presenting app.
  func dismiss(result: Any?) {
    self.result = result
    controller.presentingViewController?.dismiss(animated: true) { [weak self] in self?.finish() }
  }

  private func finish() {
    guard !finished else { return }
    finished = true
    // UIKit took the sheets over this one down with it, without telling
    // their delegates: finish them first, while this engine still runs.
    for child in children { child.finish() }
    children = []
    parent?.children.removeAll { $0 === self }
    onFirstContentHeight = nil
    onEvent("sheetDismissed", ["id": id, "result": result ?? NSNull()])
    VeneerPlugin.tearDownSheet(controller)
    onFinish?()
    // The engine is single-use: free it now rather than whenever the last
    // reference to the controller goes.
    let engine = self.engine
    DispatchQueue.main.async { engine.destroyContext() }
  }

  // MARK: - UISheetPresentationControllerDelegate

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }

  func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheet: UISheetPresentationController) {
    guard let selected = sheet.selectedDetentIdentifier, let index = detentIds.firstIndex(of: selected) else { return }
    onEvent("sheetDetentChanged", ["id": id, "detent": index])
  }
}
