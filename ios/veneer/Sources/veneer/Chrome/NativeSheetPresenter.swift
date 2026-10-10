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
  /// The group's first engine, which every sheet's engine is spawned from.
  /// `FlutterEngineGroup` spawns from its oldest living engine, and a
  /// finished sheet's engine can outlive its context (plugins hold on to
  /// it), so spawning from one aborts. This one idles in an empty Dart
  /// entrypoint for the app's lifetime and is never handed to a sheet.
  private lazy var anchor: FlutterEngine = {
    let options = FlutterEngineGroupOptions()
    options.entrypoint = "veneerSheetAnchor"
    options.libraryURI = "package:veneer/src/chrome/native_sheet.dart"
    return group.makeEngine(with: options)
  }()
  private var prewarmed: [String: FlutterEngine] = [:]
  /// Kept-alive sheets (`retain`) while hidden: the engine keeps running and
  /// the view controller keeps its overlay, so the next presentation at the
  /// same entrypoint shows the same app, chrome and all.
  private var retained: [String: (engine: FlutterEngine, controller: FlutterViewController)] = [:]
  /// Kept-alive entrypoints to free once their showing sheet closes.
  private var releaseAfterClose: Set<String> = []
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
    _ = anchor
    let engine = group.makeEngine(with: options)
    Self.muteStatusBarStyle(of: engine)
    Self.registerPlugins(with: engine, entrypoint: entrypoint)
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

  /// `VeneerPlugin.sheetEntrypointPluginRegistrant` or
  /// `sheetPluginRegistrant` when the app sets one; otherwise the app's
  /// `GeneratedPluginRegistrant`, found at runtime so apps need no extra
  /// setup for plugins to work inside sheets.
  private static func registerPlugins(with engine: FlutterEngine, entrypoint: String) {
    let registrant: ((FlutterPluginRegistry) -> Void)?
    if let byEntrypoint = VeneerPlugin.sheetEntrypointPluginRegistrant {
      registrant = { byEntrypoint($0, entrypoint) }
    } else {
      registrant = VeneerPlugin.sheetPluginRegistrant
    }
    if let registrant {
      registrant(engine)
      let key = "VeneerPlugin"
      if !engine.hasPlugin(key), let registrar = engine.registrar(forPlugin: key) {
        VeneerPlugin.register(with: registrar)
      }
      return
    }
    guard let registrant = NSClassFromString("GeneratedPluginRegistrant") as? NSObject.Type else { return }
    let selector = NSSelectorFromString("registerWithRegistry:")
    if registrant.responds(to: selector) { registrant.perform(selector, with: engine) }
  }

  /// Starts an engine at [entrypoint] ahead of time, for the next sheet.
  func prewarm(entrypoint: String, libraryURI: String?) {
    let key = Self.key(entrypoint, libraryURI)
    guard prewarmed[key] == nil, retained[key] == nil else { return }
    prewarmed[key] = makeEngine(entrypoint: entrypoint, libraryURI: libraryURI, arguments: [])
  }

  /// Frees the kept-alive engine at [entrypoint]: now if it's hidden, or
  /// when its sheet closes.
  func release(entrypoint: String, libraryURI: String?) {
    let key = Self.key(entrypoint, libraryURI)
    if let kept = retained.removeValue(forKey: key) {
      Self.destroy(kept.engine, showing: kept.controller)
    } else if sessions.values.contains(where: { $0.retainKey == key }) {
      releaseAfterClose.insert(key)
    }
  }

  private func keep(_ key: String, engine: FlutterEngine, controller: FlutterViewController) {
    if releaseAfterClose.remove(key) != nil {
      Self.destroy(engine, showing: controller)
    } else {
      retained[key] = (engine, controller)
    }
  }

  static func destroy(_ engine: FlutterEngine, showing controller: UIViewController) {
    VeneerPlugin.tearDownSheet(controller)
    // Free it now rather than whenever the last reference to the controller
    // goes.
    DispatchQueue.main.async { engine.destroyContext() }
  }

  /// `{id, entrypoint, libraryUri, arguments, detents: [{type, value}],
  ///   initialDetent, grabber, largestUndimmedDetent, dismissible,
  ///   expandsOnScroll, cornerRadius, retain, fullScreen}`, from the engine
  ///   of plugin [owner].
  func present(
    _ args: [String: Any], owner: Int, from presenter: UIViewController?,
    onRequest: @escaping (Any?, @escaping FlutterResult) -> Void,
    onEvent: @escaping (String, [String: Any]) -> Void
  ) -> Bool {
    guard let presenter = presenter.map(Self.topmost), let id = (args["id"] as? NSNumber)?.intValue,
      let entrypoint = args["entrypoint"] as? String
    else { return false }
    let libraryURI = args["libraryUri"] as? String
    let arguments = args["arguments"] as? [String] ?? []
    let key = Self.key(entrypoint, libraryURI)
    let sessionKey = SessionKey(owner: owner, id: id)
    let retain = ((args["retain"] as? Bool) ?? false) && arguments.isEmpty
    // A second presentation while the kept-alive one is still showing gets
    // an engine of its own.
    let showingKept = sessions.values.contains { $0.retainKey == key }

    let engine: FlutterEngine
    let controller: FlutterViewController
    if retain, let kept = retained.removeValue(forKey: key) {
      engine = kept.engine
      controller = kept.controller
    } else {
      if arguments.isEmpty, let warm = prewarmed.removeValue(forKey: key) {
        engine = warm
      } else {
        engine = makeEngine(entrypoint: entrypoint, libraryURI: libraryURI, arguments: arguments)
      }
      controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
      controller.isViewOpaque = false
      controller.view.backgroundColor = .clear
    }
    // A kept-alive controller may have gone full screen last time.
    controller.modalPresentationStyle = (args["fullScreen"] as? Bool) == true ? .fullScreen : .pageSheet
    controller.additionalSafeAreaInsets.top = 0
    let keeps = retain && !showingKept

    let session = NativeSheetSession(
      id: id, engine: engine, controller: controller, onRequest: onRequest, onEvent: onEvent)
    session.retainKey = keeps ? key : nil
    // A sheet presented over another sheet goes away with it.
    session.parent = sessions.values.first { $0.controller === presenter }
    session.parent?.children.append(session)
    session.onFinish = { [weak self] in
      guard let self else { return }
      self.sessions[sessionKey] = nil
      if keeps {
        self.keep(key, engine: engine, controller: controller)
      } else if arguments.isEmpty {
        self.prewarm(entrypoint: entrypoint, libraryURI: libraryURI)
      }
    }
    session.configure(args)
    session.payload = args["payload"] is NSNull ? nil : args["payload"]
    sessions[sessionKey] = session
    VeneerPlugin.deliverSheetPayload(to: controller, session.payload)
    VeneerPlugin.deliverSheetPresented(to: controller, session.payload)

    // The next sheet (one over this, or after it) starts warm too; a kept
    // one is its own next sheet. Its engine starts once this sheet is up, so
    // it never competes with the measuring and the slide.
    let warmNext = { [weak self] in
      guard let self, arguments.isEmpty, !keeps else { return }
      self.prewarm(entrypoint: entrypoint, libraryURI: libraryURI)
    }
    let show = { [weak self, weak presenter, weak controller, weak session] in
      guard let presenter, let controller, controller.presentingViewController == nil,
        self?.sessions[sessionKey] === session
      else { return }
      presenter.present(controller, animated: true) {
        VeneerPlugin.deliverSheetAppeared(to: controller)
        session?.presentationDidComplete()
        warmNext()
      }
    }
    if session.sizesToContent {
      // Let the content measure itself before the sheet comes up; it slides
      // up at that height (or at large, if it's slow to report). Flutter
      // lays a view out only once it's in a window, so it's attached beside
      // the presenter, off screen, until then.
      session.onFirstContentHeight = { [weak controller] in
        if let controller { NativeSheetSession.detachMeasuring(controller) }
        show()
      }
      controller.loadViewIfNeeded()
      presenter.addChild(controller)
      controller.view.frame = presenter.view.bounds.offsetBy(dx: presenter.view.bounds.width * 2, dy: 0)
      presenter.view.addSubview(controller.view)
      controller.didMove(toParent: presenter)
      controller.view.setNeedsLayout()
      controller.view.layoutIfNeeded()
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.contentTimeout) { [weak session] in
        session?.presentPending()
      }
    } else {
      show()
    }
    return true
  }

  /// Where a presentation aimed at [controller] should go instead: the
  /// topmost view controller over a native sheet [controller] presents, or
  /// nil when [controller] isn't presenting one.
  func presentationTarget(for controller: UIViewController) -> UIViewController? {
    guard let presented = controller.presentedViewController, !presented.isBeingDismissed,
      sessions.values.contains(where: { $0.controller === presented })
    else { return nil }
    return Self.topmost(presented)
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
  /// Set for a kept-alive sheet: closing hides it, and its engine and
  /// controller go back to the presenter instead of being torn down.
  var retainKey: String?
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
  /// Forwards the sheet engine's `NativeSheet.request`s to the engine that
  /// presented it, whose answer (or error) goes back as the reply.
  private let onRequest: (Any?, @escaping FlutterResult) -> Void
  private var detentIds: [UISheetPresentationController.Detent.Identifier] = []
  private var result: Any?
  private var finished = false

  /// Distance from the sheet's top and side edges to header controls.
  static let edgeInset: CGFloat = 16

  init(
    id: Int, engine: FlutterEngine, controller: FlutterViewController,
    onRequest: @escaping (Any?, @escaping FlutterResult) -> Void,
    onEvent: @escaping (String, [String: Any]) -> Void
  ) {
    self.id = id
    self.engine = engine
    self.controller = controller
    self.onRequest = onRequest
    self.onEvent = onEvent
    super.init()
  }

  /// A request from this sheet's engine, for the engine that presented it.
  func request(_ arguments: Any?, reply: @escaping FlutterResult) {
    guard !finished else {
      return reply(FlutterError(code: "not_shown", message: "The sheet is no longer showing", details: nil))
    }
    onRequest(arguments, reply)
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

  /// Takes a content-sized sheet's view off the screen it measured on.
  static func detachMeasuring(_ controller: UIViewController) {
    guard controller.parent != nil else { return }
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
  }

  /// Presents a content-sized sheet still waiting for its measurement.
  func presentPending() {
    let show = onFirstContentHeight
    onFirstContentHeight = nil
    controller.sheetPresentationController?.invalidateDetents()
    show?()
  }

  /// Moves the sheet to a full-screen presentation, keeping its controller
  /// and engine: UIKit can't restyle a presented controller, so it's taken
  /// down and presented again without animation, under a snapshot of the
  /// sheet that then fades away. While the sheet is still coming up, or
  /// something is presented over it, it tries again shortly. False once the
  /// sheet is full screen or closed.
  func enterFullScreen() -> Bool {
    guard !finished, !dismissalPending, controller.modalPresentationStyle != .fullScreen else { return false }
    guard let presenter = controller.presentingViewController, controller.presentedViewController == nil,
      !controller.isBeingPresented, !controller.isBeingDismissed
    else {
      fullScreenPending = true
      scheduleFullScreenRetry()
      return true
    }
    fullScreenPending = false
    movingToFullScreen = true
    let window = controller.view.window
    let snapshot = window?.snapshotView(afterScreenUpdates: false)
    if let window, let snapshot {
      snapshot.frame = window.bounds
      window.addSubview(snapshot)
    }
    let controller = self.controller
    presenter.dismiss(animated: false) { [weak self] in
      // Ended while it was off screen (a close that gave up waiting): stay
      // down rather than bring back a sheet with no session.
      guard let self, !self.finished else {
        self?.movingToFullScreen = false
        snapshot?.removeFromSuperview()
        return
      }
      controller.modalPresentationStyle = .fullScreen
      controller.additionalSafeAreaInsets.top = 0
      presenter.present(controller, animated: false) { [weak self] in
        self?.movingToFullScreen = false
        if let snapshot {
          snapshot.superview?.bringSubviewToFront(snapshot)
          // A frame for Flutter to lay out at the new size, then the fade.
          UIView.animate(
            withDuration: 0.35, delay: 0.05, options: [.curveEaseInOut],
            animations: { snapshot.alpha = 0 },
            completion: { _ in snapshot.removeFromSuperview() })
        }
        self?.presentationDidComplete()
      }
    }
    return true
  }

  static let fullScreenRetryDelay: TimeInterval = 0.25
  static let fullScreenRetryLimit = 20
  static let dismissRetryDelay: TimeInterval = 0.1
  static let dismissRetryLimit = 30

  /// Between taking the sheet down and presenting it again full screen: it
  /// has no presenting controller then, but it hasn't closed.
  private var movingToFullScreen = false

  /// A close asked for while the sheet couldn't be dismissed (coming up, or
  /// moving to full screen): carried out once it's up.
  private var dismissalPending = false
  private var dismissRetries = 0

  /// A move to full screen that's waiting for the sheet to finish coming up
  /// or for what's presented over it to go: retried on those events, and
  /// polled a few times for presentations Veneer doesn't see end.
  private var fullScreenPending = false
  private var fullScreenRetries = 0

  private func scheduleFullScreenRetry() {
    guard fullScreenRetries < Self.fullScreenRetryLimit else { return }
    fullScreenRetries += 1
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.fullScreenRetryDelay) { [weak self] in
      guard let self, self.fullScreenPending else { return }
      _ = self.enterFullScreen()
    }
  }

  /// The sheet finished coming up (presented, or moved to full screen):
  /// what waited for that goes ahead — a close first.
  func presentationDidComplete() {
    if dismissalPending {
      dismissRetries = 0
      dismiss(result: result)
    } else {
      retryPendingFullScreen()
    }
  }

  /// The sheet came up, or a sheet over it went: a pending move to full
  /// screen can go ahead.
  func retryPendingFullScreen() {
    guard fullScreenPending else { return }
    fullScreenRetries = 0
    DispatchQueue.main.async { [weak self] in _ = self?.enterFullScreen() }
  }

  /// Dismisses with a result for the presenting app.
  func dismiss(result: Any?) {
    guard !finished else { return }
    self.result = result
    // UIKit drops a dismissal asked for mid-presentation, and a sheet moving
    // to full screen is briefly down: close it once it's up (or after a
    // while, regardless). One that never came up (still measuring) just ends.
    if movingToFullScreen || controller.isBeingPresented {
      dismissalPending = true
      scheduleDismissRetry()
      return
    }
    dismissalPending = false
    guard let presenter = controller.presentingViewController else { return finish() }
    presenter.dismiss(animated: true) { [weak self] in self?.finish() }
  }

  private func scheduleDismissRetry() {
    guard dismissRetries < Self.dismissRetryLimit else {
      dismissalPending = false
      controller.presentingViewController?.dismiss(animated: false)
      return finish()
    }
    dismissRetries += 1
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissRetryDelay) { [weak self] in
      guard let self, self.dismissalPending else { return }
      self.dismiss(result: self.result)
    }
  }

  private func finish() {
    guard !finished else { return }
    finished = true
    // UIKit took the sheets over this one down with it, without telling
    // their delegates: finish them first, while this engine still runs.
    for child in children { child.finish() }
    children = []
    parent?.children.removeAll { $0 === self }
    parent?.retryPendingFullScreen()
    onFirstContentHeight = nil
    Self.detachMeasuring(controller)
    onEvent("sheetDismissed", ["id": id, "result": result ?? NSNull()])
    if retainKey != nil {
      VeneerPlugin.deliverSheetHidden(to: controller)
      onFinish?()
      return
    }
    onFinish?()
    // The engine is single-use: free it once its app has cleaned up, rather
    // than whenever the last reference to the controller goes.
    let engine = self.engine
    let controller = self.controller
    VeneerPlugin.deliverSheetClosing(to: controller, timeout: Self.closingTimeout) {
      VeneerPlugin.tearDownSheet(controller)
      DispatchQueue.main.async { engine.destroyContext() }
    }
  }

  /// The longest a closed sheet's engine waits for its app's cleanup.
  static let closingTimeout: TimeInterval = 3

  // MARK: - UISheetPresentationControllerDelegate

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }

  func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheet: UISheetPresentationController) {
    guard let selected = sheet.selectedDetentIdentifier, let index = detentIds.firstIndex(of: selected) else { return }
    onEvent("sheetDetentChanged", ["id": id, "detent": index])
  }
}
