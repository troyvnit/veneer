import UIKit

/// Long-press context menus on Flutter content, run by UIKit: the press
/// shrink, the lift of a preview over a blurred backdrop, the menu and its
/// dismissal are all `UIContextMenuInteraction`'s own.
///
/// UIKit only presents a context menu for a touch it recognizes itself, so
/// the interaction sits on the `FlutterView` and asks, synchronously, which
/// region is under the finger. Regions are Flutter widgets
/// (`NativeContextMenu`) whose frames, visibility and clips arrive with the
/// glass geometry every frame, so the answer needs no round trip to Dart.
/// A touch outside every region gets no menu and stays Flutter's.
///
/// The preview is a snapshot of the region's pixels; while the menu is up
/// Dart hides the widget itself, so only the lifted copy is seen.
@available(iOS 26.0, *)
final class ContextMenuRegions: NSObject, UIContextMenuInteractionDelegate {
  private struct Region {
    var frame: CGRect = .zero
    var visible = false
    var clip: CGPath?
    var radii: [CGFloat] = [0, 0, 0, 0]
    var menu: Any?
  }

  var onEvent: ((String, Any?) -> Void)?

  private var regions: [Int: Region] = [:]
  private weak var hostView: UIView?
  private var interaction: UIContextMenuInteraction?
  /// The lifted snapshot, reused for the dismissal so it lands back in place
  /// even though the widget under it is hidden by then.
  private var snapshot: (id: Int, view: UIView)?

  func attach(to view: UIView) {
    guard hostView !== view else { return }
    detach()
    let interaction = UIContextMenuInteraction(delegate: self)
    view.addInteraction(interaction)
    self.interaction = interaction
    hostView = view
  }

  func detach() {
    if let interaction { interaction.view?.removeInteraction(interaction) }
    interaction = nil
    hostView = nil
  }

  func has(_ id: Int) -> Bool { regions[id] != nil }

  /// `{id, menu, radii: [TL, TR, BR, BL]}`.
  func configure(_ args: [String: Any]) {
    guard let id = (args["id"] as? NSNumber)?.intValue else { return }
    var region = regions[id] ?? Region()
    region.menu = args["menu"]
    if let radii = args["radii"] as? [NSNumber], radii.count == 4 {
      region.radii = radii.map { CGFloat($0.doubleValue) }
    }
    regions[id] = region
  }

  func remove(id: Int) {
    regions.removeValue(forKey: id)
  }

  /// From the frame buffer; runs inside the Flutter frame, so it only stores.
  func update(id: Int, frame: CGRect, visible: Bool, clip: CGPath?) {
    guard var region = regions[id] else { return }
    region.frame = frame
    region.visible = visible && frame.width > 0 && frame.height > 0
    region.clip = clip
    regions[id] = region
  }

  /// The innermost visible region under `point`: a menu inside a larger one
  /// (a chip in a bubble) wins.
  private func region(at point: CGPoint) -> (Int, Region)? {
    var best: (Int, Region)?
    for (id, region) in regions where region.visible && region.frame.contains(point) {
      if let clip = region.clip, !clip.contains(point) { continue }
      let area = region.frame.width * region.frame.height
      if let current = best, current.1.frame.width * current.1.frame.height <= area { continue }
      best = (id, region)
    }
    return best
  }

  // MARK: - UIContextMenuInteractionDelegate

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint
  ) -> UIContextMenuConfiguration? {
    guard let (id, region) = self.region(at: location) else { return nil }
    let menu = NativeMenu.make(region.menu, id: "\(id)") { [weak self] itemId in
      guard let index = Int(itemId.components(separatedBy: ".menu").last ?? "") else { return }
      self?.onEvent?("contextMenuItem", ["id": id, "index": index])
    }
    guard let menu else { return nil }
    snapshot = nil
    return UIContextMenuConfiguration(identifier: NSNumber(value: id), previewProvider: nil) { _ in menu }
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configuration: UIContextMenuConfiguration,
    highlightPreviewForItemWithIdentifier identifier: any NSCopying
  ) -> UITargetedPreview? {
    preview(for: configuration)
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configuration: UIContextMenuConfiguration,
    dismissalPreviewForItemWithIdentifier identifier: any NSCopying
  ) -> UITargetedPreview? {
    preview(for: configuration)
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willDisplayMenuFor configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    guard let id = (configuration.identifier as? NSNumber)?.intValue else { return }
    onEvent?("contextMenuShown", ["id": id])
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    guard let id = (configuration.identifier as? NSNumber)?.intValue else { return }
    let finish = { [weak self] in
      guard let self else { return }
      self.onEvent?("contextMenuHidden", ["id": id])
      if self.snapshot?.id == id { self.snapshot = nil }
    }
    if let animator { animator.addCompletion(finish) } else { finish() }
  }

  private func preview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    guard let id = (configuration.identifier as? NSNumber)?.intValue,
      let region = regions[id], let host = hostView
    else { return nil }
    let view: UIView
    if let snapshot, snapshot.id == id {
      view = snapshot.view
    } else {
      guard let captured = host.resizableSnapshotView(
        from: region.frame, afterScreenUpdates: false, withCapInsets: .zero)
      else { return nil }
      captured.frame = CGRect(origin: .zero, size: region.frame.size)
      snapshot = (id, captured)
      view = captured
    }
    let parameters = UIPreviewParameters()
    parameters.backgroundColor = .clear
    parameters.visiblePath = UIBezierPath(
      cgPath: ShapeClip.roundedPath(CGRect(origin: .zero, size: region.frame.size), region.radii))
    let target = UIPreviewTarget(container: host, center: CGPoint(x: region.frame.midX, y: region.frame.midY))
    return UITargetedPreview(view: view, parameters: parameters, target: target)
  }
}
