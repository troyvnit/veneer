import UIKit

/// A Flutter clip in global coordinates (== the overlay's), as sent per
/// shape in the frame buffer: flags, rect, rrect, four corner radii.
struct ShapeClip: Equatable {
  var rect: CGRect?
  var rrect: CGRect?
  /// Top-left, top-right, bottom-right, bottom-left.
  var radii: [CGFloat] = []

  static let none = ShapeClip()

  init() {}

  /// Reads `[flags, rect LTWH, rrect LTWH, radii TL TR BR BL]` at `o`.
  init(_ buf: UnsafeBufferPointer<Double>, at o: Int) {
    let flags = Int(buf[o])
    if flags & 1 != 0 { rect = CGRect(x: buf[o + 1], y: buf[o + 2], width: buf[o + 3], height: buf[o + 4]) }
    if flags & 2 != 0 {
      rrect = CGRect(x: buf[o + 5], y: buf[o + 6], width: buf[o + 7], height: buf[o + 8])
      radii = (9...12).map { CGFloat(buf[o + $0]) }
    }
  }

  var path: CGPath? {
    let rectPath = rect.map { CGPath(rect: $0, transform: nil) }
    let rrectPath = rrect.map { Self.roundedPath($0, radii) }
    switch (rectPath, rrectPath) {
    case let (r?, rr?): return rr.intersection(r)
    case let (r?, nil): return r
    case let (nil, rr?): return rr
    default: return nil
    }
  }

  /// Rounded rect with independent circular corners, matching Flutter's RRect.
  static func roundedPath(_ r: CGRect, _ radii: [CGFloat]) -> CGPath {
    let limit = min(r.width, r.height) / 2
    let tl = min(radii[0], limit), tr = min(radii[1], limit)
    let br = min(radii[2], limit), bl = min(radii[3], limit)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + tr), radius: tr)
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - br, y: r.maxY), radius: br)
    p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bl), radius: bl)
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + tl, y: r.minY), radius: tl)
    p.closeSubpath()
    return p
  }
}

/// Mask view whose backing layer is the clip path.
final class ClipMaskView: UIView {
  override class var layerClass: AnyClass { CAShapeLayer.self }
  var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }
}
