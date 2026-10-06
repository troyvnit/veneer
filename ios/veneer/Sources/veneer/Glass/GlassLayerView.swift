import UIKit

@available(iOS 26.0, *)
struct GlassShapeConfig {
  var id: Int
  var group: Int
  var clear: Bool
  var tint: UIColor?
  var interactive: Bool
  /// `nil` means capsule.
  var cornerRadius: CGFloat?
  var icon: NativeIconDescriptor?
  var iconSize: CGFloat?
  var label: String?
  var foreground: UIColor?
  /// Dart menu items (`NativeMenu`); tapping opens a `UIMenu`.
  var menu: Any?
  /// Turns the shape into a search field on its glass.
  var search: GlassSearchConfig?
  /// Turns the shape into a row of tappable segments with a highlight.
  var segments: GlassSegmentsConfig?

  init(_ args: [String: Any]) {
    id = (args["id"] as? NSNumber)?.intValue ?? -1
    group = (args["group"] as? NSNumber)?.intValue ?? 0
    clear = (args["style"] as? String) == "clear"
    tint = (args["tint"] as? NSNumber).map(UIColor.init(argb:))
    interactive = (args["interactive"] as? Bool) ?? false
    cornerRadius = (args["cornerRadius"] as? NSNumber).map { CGFloat($0.doubleValue) }
    icon = NativeIconDescriptor(args["icon"])
    iconSize = (args["iconSize"] as? NSNumber).map { CGFloat($0.doubleValue) }
    label = args["label"] as? String
    foreground = (args["foreground"] as? NSNumber).map(UIColor.init(argb:))
    menu = args["menu"]
    search = (args["search"] as? [String: Any]).map(GlassSearchConfig.init)
    segments = (args["segments"] as? [String: Any]).map(GlassSegmentsConfig.init)
  }
}

@available(iOS 26.0, *)
struct GlassSegmentsConfig {
  struct Item {
    var icon: NativeIconDescriptor?
    var label: String?
  }

  var items: [Item]
  var selected: Int
  var iconSize: CGFloat
  var padding: CGFloat
  var foreground: UIColor?
  var selectedForeground: UIColor?
  var selectionColor: UIColor?
  /// Identifies the item contents, so buttons are rebuilt only when they change.
  var signature: String

  init(_ args: [String: Any]) {
    let raw = args["items"] as? [[String: Any]] ?? []
    items = raw.map { Item(icon: NativeIconDescriptor($0["icon"]), label: $0["label"] as? String) }
    selected = (args["selected"] as? NSNumber)?.intValue ?? -1
    iconSize = CGFloat((args["iconSize"] as? NSNumber)?.doubleValue ?? 20)
    padding = CGFloat((args["padding"] as? NSNumber)?.doubleValue ?? 4)
    foreground = (args["foreground"] as? NSNumber).map(UIColor.init(argb:))
    selectedForeground = (args["selectedForeground"] as? NSNumber).map(UIColor.init(argb:))
    selectionColor = (args["selectionColor"] as? NSNumber).map(UIColor.init(argb:))
    signature = raw.map { "\($0["icon"] ?? "")|\($0["label"] ?? "")" }.joined(separator: ";")
      + "|\(iconSize)"
  }
}

@available(iOS 26.0, *)
struct GlassSearchConfig {
  var placeholder: String
  var text: String

  init(_ args: [String: Any]) {
    placeholder = args["placeholder"] as? String ?? ""
    text = args["text"] as? String ?? ""
  }
}

@available(iOS 26.0, *)
struct GlassGroupConfig {
  var id: Int
  /// `nil` follows the layer's default spacing.
  var spacing: CGFloat?
  var zIndex: Int

  init(_ args: [String: Any]) {
    id = (args["id"] as? NSNumber)?.intValue ?? 0
    spacing = (args["spacing"] as? NSNumber).map { CGFloat($0.doubleValue) }
    zIndex = (args["zIndex"] as? NSNumber)?.intValue ?? 0
  }
}

/// Owns every glass shape on screen, organised into groups and, within a
/// group, into clip scopes.
///
/// ```
/// GlassLayerView
/// └─ GlassGroupView (zIndex order)          merge boundary, stacking
///    └─ GlassClipScopeView (one per clip)   UIGlassContainerEffect + mask
///       └─ GlassShapeView                   UIGlassEffect
/// ```
///
/// A group is the unit Dart controls (`GlassGroup`, or a route's default):
/// glass in different groups never merges, and groups stack by `zIndex`,
/// then creation order.
///
/// A clip scope is the unit Flutter clipping forces. A glass container
/// renders its shapes together, so a per-shape `mask` is ignored; the mask
/// has to sit on the container. Shapes under the same Flutter clip share a
/// scope — and so still merge — while shapes under different clips can't.
///
/// Groups are either explicit (removed by Dart) or automatic (created on
/// first reference, dropped once empty). Scopes are always automatic.
@available(iOS 26.0, *)
final class GlassLayerView: UIView {
  var onShapeTapped: ((Int) -> Void)?
  /// A shape's menu item was picked: shape id, item index.
  var onShapeMenu: ((Int, Int) -> Void)?
  /// A search shape's field changed: shape id, `text` / `submit` / `focus`, value.
  var onShapeSearch: ((Int, String, Any) -> Void)?
  /// A segment of a segment bar was tapped: shape id, segment index.
  var onShapeSegment: ((Int, Int) -> Void)?
  /// Context-menu regions ride the same frames as shapes.
  weak var contextMenus: ContextMenuRegions?

  private var shapes: [Int: GlassShapeView] = [:]
  private var groups: [Int: GlassGroupView] = [:]
  private var nextGroupSequence = 0

  /// Spacing for groups that don't set their own.
  var defaultSpacing: CGFloat = 16 {
    didSet {
      for group in groups.values where group.config.spacing == nil { group.spacing = defaultSpacing }
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  // MARK: - Groups

  func configureGroup(_ config: GlassGroupConfig) {
    let group = group(for: config.id)
    group.isExplicit = true
    let zChanged = group.config.zIndex != config.zIndex
    group.config = config
    group.spacing = config.spacing ?? defaultSpacing
    if zChanged { sortGroups() }
  }

  /// The Dart group is gone; the native group lingers until its shapes
  /// finish dematerializing, then is dropped like an automatic group.
  func removeGroup(id: Int) {
    guard let group = groups[id] else { return }
    group.isExplicit = false
    dropIfEmpty(group)
  }

  private func group(for id: Int) -> GlassGroupView {
    if let existing = groups[id] { return existing }
    var config = GlassGroupConfig([:])
    config.id = id
    let group = GlassGroupView(config: config, sequence: nextGroupSequence)
    nextGroupSequence += 1
    group.spacing = defaultSpacing
    group.frame = bounds
    group.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    groups[id] = group
    addSubview(group)
    sortGroups()
    return group
  }

  private func sortGroups() {
    let ordered = groups.values.sorted { ($0.config.zIndex, $0.sequence) < ($1.config.zIndex, $1.sequence) }
    for group in ordered { bringSubviewToFront(group) }
  }

  private func dropIfEmpty(_ group: GlassGroupView) {
    guard !group.isExplicit, group.isEmpty, groups[group.config.id] === group else { return }
    groups.removeValue(forKey: group.config.id)
    group.removeFromSuperview()
  }

  // MARK: - Shapes

  func configure(_ config: GlassShapeConfig) {
    let shape = shapes[config.id] ?? {
      let view = GlassShapeView(id: config.id)
      view.onTap = { [weak self] id in self?.onShapeTapped?(id) }
      view.onMenu = { [weak self] id, index in self?.onShapeMenu?(id, index) }
      view.onSearch = { [weak self] id, kind, value in self?.onShapeSearch?(id, kind, value) }
      view.onSegment = { [weak self] id, index in self?.onShapeSegment?(id, index) }
      shapes[config.id] = view
      return view
    }()
    place(shape, group: config.group, clip: shape.clipId)
    shape.apply(config)
  }

  func searchCommand(id: Int, command: String) {
    shapes[id]?.searchCommand(command)
  }

  func remove(id: Int) {
    guard let shape = shapes.removeValue(forKey: id) else { return }
    shape.dematerialize { [weak self] in self?.detach(shape) }
  }

  /// Moves `shape` into the scope for (`group`, `clip`), creating it if
  /// needed, and drops the scope/group it leaves if that empties them.
  /// Only adds/removes subviews — safe inside the FFI call.
  private func place(_ shape: GlassShapeView, group groupId: Int, clip clipId: Int) {
    let scope = group(for: groupId).scope(for: clipId)
    guard shape.superview !== scope.contentView else { return }
    let wasPlaced = shape.superview != nil
    let previousGroup = wasPlaced ? groups[shape.groupId] : nil
    let previousScope = previousGroup?.scopes[shape.clipId]
    scope.contentView.addSubview(shape)
    shape.groupId = groupId
    shape.clipId = clipId
    if let previousScope, previousScope !== scope { previousGroup?.dropIfEmpty(previousScope) }
    if let previousGroup, previousGroup.config.id != groupId { dropIfEmpty(previousGroup) }
  }

  private func detach(_ shape: GlassShapeView) {
    let group = groups[shape.groupId]
    let scope = group?.scopes[shape.clipId]
    shape.removeFromSuperview()
    if let group, let scope { group.dropIfEmpty(scope) }
    if let group { dropIfEmpty(group) }
  }

  /// `[frameNumber, count, shape * count]`, in Flutter logical pixels ==
  /// UIKit points, relative to the FlutterView. Groups and scopes span this
  /// view's bounds, so frames and clips need no conversion. Each shape
  /// (stride `Self.stride`):
  ///   0 id · 1–4 rect · 5 visible · 6 clip id · 7 clip flags (1 rect, 2 rrect)
  ///   8–11 clip rect · 12–15 clip rrect · 16–19 radii TL TR BR BL
  ///
  /// Runs synchronously inside the Flutter frame (via FFI), so it must only
  /// *mark* UIKit state. Anything that forces a layout pass — an explicit
  /// top-level `CATransaction.commit()`, `UIView.animate`, `layoutIfNeeded`
  /// — reaches `FlutterViewController.viewDidLayoutSubviews`, which
  /// re-enters Dart mid-frame. Frame, path and subview writes are safe:
  /// UIView-backed layers never implicitly animate outside an animation
  /// block, and they commit with the run loop's implicit transaction.
  /// Visibility changes animate, so they are deferred to the next turn.
  static let stride = FrameLayout.stride

  func apply(_ buf: UnsafeBufferPointer<Double>) {
    let count = Int(buf[1])
    guard buf.count >= 2 + count * Self.stride else { return }
    var visibilityChanges: [(GlassShapeView, Bool)] = []
    for i in 0..<count {
      let o = 2 + i * Self.stride
      let id = Int(buf[o])
      if let contextMenus, contextMenus.has(id) {
        let frame = CGRect(x: buf[o + 1], y: buf[o + 2], width: buf[o + 3], height: buf[o + 4])
        let clip = Int(buf[o + 6]) != 0 ? ShapeClip(buf, at: o + 7).path : nil
        contextMenus.update(id: id, frame: frame, visible: buf[o + 5] > 0.5, clip: clip)
        continue
      }
      guard let shape = shapes[id], shape.superview != nil else { continue }
      let clipId = Int(buf[o + 6])
      if clipId != shape.clipId { place(shape, group: shape.groupId, clip: clipId) }
      if clipId != 0 { groups[shape.groupId]?.scopes[clipId]?.setClip(ShapeClip(buf, at: o + 7)) }

      let frame = CGRect(x: buf[o + 1], y: buf[o + 2], width: buf[o + 3], height: buf[o + 4])
      if shape.frame != frame { shape.frame = frame }
      let visible = buf[o + 5] > 0.5 && frame.width > 0 && frame.height > 0
      if visible != shape.targetVisible {
        shape.targetVisible = visible
        visibilityChanges.append((shape, visible))
      }
    }
    if !visibilityChanges.isEmpty {
      DispatchQueue.main.async {
        for (shape, visible) in visibilityChanges where shape.targetVisible == visible {
          shape.setVisible(visible)
        }
      }
    }
  }

  var diagnostics: [String: Any] {
    [
      "shapes": shapes.count,
      "shownShapes": shapes.values.filter(\.isShown).count,
      "shapesWithFrame": shapes.values.filter { $0.frame.width > 0 }.count,
      "groups": groups.count,
      "explicitGroups": groups.values.filter(\.isExplicit).count,
      "clipScopes": groups.values.reduce(0) { $0 + $1.scopes.keys.filter { $0 != 0 }.count },
    ]
  }

  // MARK: - Hit testing

  /// Only interactive, visible shapes take touches; everything else —
  /// this view, groups, scopes, content views — is transparent, so a layer
  /// stacked above can't swallow touches meant for one below.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit.flatMap(isInteractiveHit) == true ? hit : nil
  }

  func isInteractiveHit(_ view: UIView) -> Bool {
    var v: UIView? = view
    while let current = v, current !== self {
      if let shape = current as? GlassShapeView { return shape.isInteractive && shape.isShown }
      v = current.superview
    }
    return false
  }
}

/// One glass group: a merge boundary holding one clip scope per distinct
/// Flutter clip among its shapes (scope 0 = unclipped).
@available(iOS 26.0, *)
final class GlassGroupView: UIView {
  var config: GlassGroupConfig
  let sequence: Int
  var isExplicit = false
  private(set) var scopes: [Int: GlassClipScopeView] = [:]

  var spacing: CGFloat = 16 {
    didSet { for scope in scopes.values { scope.spacing = spacing } }
  }

  var isEmpty: Bool { scopes.isEmpty }

  init(config: GlassGroupConfig, sequence: Int) {
    self.config = config
    self.sequence = sequence
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func scope(for clipId: Int) -> GlassClipScopeView {
    if let existing = scopes[clipId] { return existing }
    let scope = GlassClipScopeView(clipId: clipId)
    scope.spacing = spacing
    scope.frame = bounds
    scope.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    scopes[clipId] = scope
    addSubview(scope)
    return scope
  }

  func dropIfEmpty(_ scope: GlassClipScopeView) {
    guard scope.contentView.subviews.isEmpty, scopes[scope.clipId] === scope else { return }
    scopes.removeValue(forKey: scope.clipId)
    scope.removeFromSuperview()
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self ? nil : hit
  }
}

/// One Flutter clip scope: a full-screen `UIGlassContainerEffect` whose
/// shapes merge with each other, wrapped in a plain view that carries the
/// clip mask. Masking the visual-effect view itself (per shape or on the
/// container) is ignored by glass rendering; an ordinary ancestor's mask
/// is not.
@available(iOS 26.0, *)
final class GlassClipScopeView: UIView {
  let clipId: Int
  private let container = UIVisualEffectView(effect: nil)
  private let containerEffect = UIGlassContainerEffect()
  private var clip = ShapeClip.none
  private var clipPath: CGPath?
  private lazy var clipMask = ClipMaskView()

  /// Shapes live here.
  var contentView: UIView { container.contentView }

  var spacing: CGFloat {
    get { containerEffect.spacing }
    set {
      guard newValue != containerEffect.spacing else { return }
      containerEffect.spacing = newValue
      container.effect = containerEffect
    }
  }

  init(clipId: Int) {
    self.clipId = clipId
    super.init(frame: .zero)
    container.effect = containerEffect
    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(container)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var frame: CGRect {
    didSet { container.frame = bounds }
  }

  /// Called for every shape in the scope every frame; rebuilds only on change.
  func setClip(_ newClip: ShapeClip) {
    guard newClip != clip else { return }
    clip = newClip
    clipPath = newClip.path
    guard let clipPath else {
      mask = nil
      return
    }
    clipMask.frame = bounds
    clipMask.shapeLayer.path = clipPath
    if mask !== clipMask { mask = clipMask }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    container.frame = bounds
    if mask != nil { clipMask.frame = bounds }
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    if let clipPath, !clipPath.contains(point) { return nil }
    let hit = super.hitTest(point, with: event)
    return hit === self || hit === container || hit === contentView ? nil : hit
  }
}
