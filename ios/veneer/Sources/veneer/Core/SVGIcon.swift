import UIKit

/// A small, native SVG renderer for icons: parsed with `XMLParser`, drawn
/// with CoreGraphics.
///
/// Supported: `svg` (viewBox, width/height), `g`, `path` (full path grammar,
/// arcs included), `rect` (rx/ry), `circle`, `ellipse`, `line`, `polyline`,
/// `polygon`; `transform` (matrix, translate, scale, rotate, skewX/Y);
/// `fill`, `stroke`, `stroke-width`, `stroke-linecap`, `stroke-linejoin`,
/// `stroke-miterlimit`, `fill-rule`, `opacity`, `fill-opacity`,
/// `stroke-opacity`, both as attributes and in `style`, inherited through
/// groups; colours as `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`,
/// basic names and `currentColor`.
///
/// Not supported (skipped): gradients, patterns, `clipPath`, `mask`,
/// `use`/`defs`, text, filters, CSS stylesheets. That covers typical icon
/// sets; artwork with those features should ship as an image asset instead.
final class SVGIcon {
  enum Paint: Equatable {
    case none
    case currentColor
    case color(UIColor)
  }

  struct Style {
    var fill: Paint = .color(.black)
    var stroke: Paint = .none
    var strokeWidth: CGFloat = 1
    var lineCap: CGLineCap = .butt
    var lineJoin: CGLineJoin = .miter
    var miterLimit: CGFloat = 4
    var evenOdd = false
    var fillOpacity: CGFloat = 1
    var strokeOpacity: CGFloat = 1
    var opacity: CGFloat = 1
  }

  struct Shape {
    let path: CGPath
    let style: Style
  }

  let viewBox: CGRect
  let shapes: [Shape]

  init?(data: Data) {
    let builder = SVGBuilder()
    let parser = XMLParser(data: data)
    parser.delegate = builder
    guard parser.parse(), let viewBox = builder.viewBox, viewBox.width > 0, viewBox.height > 0 else { return nil }
    self.viewBox = viewBox
    shapes = builder.shapes
  }

  /// Renders into a `size`×`size` image, scaled to fit (xMidYMid meet).
  /// `template` paints everything black and returns a template image, so
  /// UIKit tints it like an SF Symbol.
  func image(size: CGFloat, template: Bool) -> UIImage {
    let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
      let cg = ctx.cgContext
      let scale = min(size / viewBox.width, size / viewBox.height)
      cg.translateBy(x: (size - viewBox.width * scale) / 2, y: (size - viewBox.height * scale) / 2)
      cg.scaleBy(x: scale, y: scale)
      cg.translateBy(x: -viewBox.minX, y: -viewBox.minY)

      for shape in shapes {
        let s = shape.style
        if let color = resolve(s.fill, opacity: s.fillOpacity * s.opacity, template: template) {
          cg.addPath(shape.path)
          cg.setFillColor(color)
          cg.fillPath(using: s.evenOdd ? .evenOdd : .winding)
        }
        if s.strokeWidth > 0, let color = resolve(s.stroke, opacity: s.strokeOpacity * s.opacity, template: template) {
          cg.addPath(shape.path)
          cg.setStrokeColor(color)
          cg.setLineWidth(s.strokeWidth)
          cg.setLineCap(s.lineCap)
          cg.setLineJoin(s.lineJoin)
          cg.setMiterLimit(s.miterLimit)
          cg.strokePath()
        }
      }
    }
    return image.withRenderingMode(template ? .alwaysTemplate : .alwaysOriginal)
  }

  private func resolve(_ paint: Paint, opacity: CGFloat, template: Bool) -> CGColor? {
    switch paint {
    case .none:
      return nil
    case .currentColor:
      return (template ? UIColor.black : UIColor.label).withAlphaComponent(opacity).cgColor
    case .color(let c):
      var alpha: CGFloat = 1
      c.getRed(nil, green: nil, blue: nil, alpha: &alpha)
      let base = template ? UIColor.black : c
      return base.withAlphaComponent(alpha * opacity).cgColor
    }
  }
}

// MARK: - Parsing

private final class SVGBuilder: NSObject, XMLParserDelegate {
  var viewBox: CGRect?
  var shapes: [SVGIcon.Shape] = []

  private var stack: [(style: SVGIcon.Style, transform: CGAffineTransform)] = [(SVGIcon.Style(), .identity)]
  private var skipDepth = 0

  private static let containers: Set<String> = ["svg", "g", "a"]
  private static let skipped: Set<String> = [
    "defs", "clipPath", "mask", "linearGradient", "radialGradient", "pattern", "symbol", "style", "text", "filter",
    "title", "desc", "metadata",
  ]

  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
    attributes attrs: [String: String]
  ) {
    let name = name.split(separator: ":").last.map(String.init) ?? name
    if skipDepth > 0 || Self.skipped.contains(name) {
      skipDepth += 1
      return
    }
    let parent = stack.last!
    let props = Self.properties(attrs)
    let style = Self.apply(props, to: parent.style)
    var transform = parent.transform
    if let t = attrs["transform"] { transform = SVGTransform.parse(t).concatenating(transform) }

    if name == "svg", viewBox == nil {
      viewBox = Self.viewBox(attrs)
    }
    if Self.containers.contains(name) {
      stack.append((style, transform))
      return
    }
    // Leaf shapes still get a stack entry so didEnd pops symmetrically.
    stack.append((style, transform))
    guard let path = Self.path(for: name, attrs) else { return }
    var t = transform
    guard let transformed = path.copy(using: &t) else { return }
    shapes.append(.init(path: transformed, style: style))
  }

  func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    if skipDepth > 0 {
      skipDepth -= 1
      return
    }
    if stack.count > 1 { stack.removeLast() }
  }

  // MARK: Geometry

  private static func viewBox(_ attrs: [String: String]) -> CGRect? {
    if let vb = attrs["viewBox"] {
      let n = SVGNumbers.list(vb)
      if n.count == 4 { return CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) }
    }
    if let w = attrs["width"].flatMap(SVGNumbers.length), let h = attrs["height"].flatMap(SVGNumbers.length) {
      return CGRect(x: 0, y: 0, width: w, height: h)
    }
    return nil
  }

  private static func path(for name: String, _ a: [String: String]) -> CGPath? {
    func n(_ key: String) -> CGFloat { a[key].flatMap(SVGNumbers.length) ?? 0 }
    switch name {
    case "path":
      return a["d"].map(SVGPathParser.parse)
    case "rect":
      let rect = CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height"))
      guard rect.width > 0, rect.height > 0 else { return nil }
      var rx = a["rx"].flatMap(SVGNumbers.length)
      var ry = a["ry"].flatMap(SVGNumbers.length)
      if rx == nil { rx = ry }
      if ry == nil { ry = rx }
      let cw = min(rx ?? 0, rect.width / 2), ch = min(ry ?? 0, rect.height / 2)
      return cw > 0 && ch > 0
        ? CGPath(roundedRect: rect, cornerWidth: cw, cornerHeight: ch, transform: nil)
        : CGPath(rect: rect, transform: nil)
    case "circle":
      let r = n("r")
      guard r > 0 else { return nil }
      return CGPath(ellipseIn: CGRect(x: n("cx") - r, y: n("cy") - r, width: 2 * r, height: 2 * r), transform: nil)
    case "ellipse":
      let rx = n("rx"), ry = n("ry")
      guard rx > 0, ry > 0 else { return nil }
      return CGPath(ellipseIn: CGRect(x: n("cx") - rx, y: n("cy") - ry, width: 2 * rx, height: 2 * ry), transform: nil)
    case "line":
      let p = CGMutablePath()
      p.move(to: CGPoint(x: n("x1"), y: n("y1")))
      p.addLine(to: CGPoint(x: n("x2"), y: n("y2")))
      return p
    case "polyline", "polygon":
      let pts = SVGNumbers.list(a["points"] ?? "")
      guard pts.count >= 4 else { return nil }
      let p = CGMutablePath()
      p.move(to: CGPoint(x: pts[0], y: pts[1]))
      var i = 2
      while i + 1 < pts.count {
        p.addLine(to: CGPoint(x: pts[i], y: pts[i + 1]))
        i += 2
      }
      if name == "polygon" { p.closeSubpath() }
      return p
    default:
      return nil
    }
  }

  // MARK: Style

  /// Presentation attributes, overridden by `style="k: v; …"`.
  private static func properties(_ attrs: [String: String]) -> [String: String] {
    var props = attrs
    if let style = attrs["style"] {
      for decl in style.split(separator: ";") {
        let kv = decl.split(separator: ":", maxSplits: 1)
        guard kv.count == 2 else { continue }
        props[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces)
      }
    }
    return props
  }

  private static func apply(_ p: [String: String], to inherited: SVGIcon.Style) -> SVGIcon.Style {
    var s = inherited
    s.opacity = 1  // `opacity` isn't inherited; it multiplies per element
    if let v = p["fill"], let paint = SVGColor.paint(v) { s.fill = paint }
    if let v = p["stroke"], let paint = SVGColor.paint(v) { s.stroke = paint }
    if let v = p["stroke-width"].flatMap(SVGNumbers.length) { s.strokeWidth = v }
    if let v = p["stroke-miterlimit"].flatMap(SVGNumbers.length) { s.miterLimit = v }
    if let v = p["fill-opacity"].flatMap(SVGNumbers.length) { s.fillOpacity = v }
    if let v = p["stroke-opacity"].flatMap(SVGNumbers.length) { s.strokeOpacity = v }
    if let v = p["opacity"].flatMap(SVGNumbers.length) { s.opacity = inherited.opacity * v }
    if let v = p["fill-rule"] { s.evenOdd = v == "evenodd" }
    switch p["stroke-linecap"] {
    case "round": s.lineCap = .round
    case "square": s.lineCap = .square
    case "butt": s.lineCap = .butt
    default: break
    }
    switch p["stroke-linejoin"] {
    case "round": s.lineJoin = .round
    case "bevel": s.lineJoin = .bevel
    case "miter": s.lineJoin = .miter
    default: break
    }
    return s
  }
}

// MARK: - Numbers, colours, transforms

enum SVGNumbers {
  /// A length without units, or with `px` (the only unit icons use).
  static func length(_ s: String) -> CGFloat? {
    let trimmed = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "px", with: "")
    if trimmed.hasSuffix("%") { return nil }
    return Double(trimmed).map { CGFloat($0) }
  }

  static func list(_ s: String) -> [CGFloat] {
    var scanner = SVGScanner(s)
    var out: [CGFloat] = []
    while !scanner.atEnd {
      if let n = scanner.number() { out.append(n) } else { scanner.advance() }
    }
    return out
  }
}

enum SVGColor {
  static func paint(_ raw: String) -> SVGIcon.Paint? {
    let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
    switch v {
    case "none", "transparent": return SVGIcon.Paint.none
    case "currentcolor": return .currentColor
    case "": return nil
    default: break
    }
    if v.hasPrefix("url(") { return .currentColor }  // gradients unsupported: fall back to solid
    if v.hasPrefix("#") { return hex(String(v.dropFirst())).map(SVGIcon.Paint.color) }
    if v.hasPrefix("rgb") {
      let n = SVGNumbers.list(v.replacingOccurrences(of: "%", with: ""))
      guard n.count >= 3 else { return nil }
      return .color(UIColor(red: n[0] / 255, green: n[1] / 255, blue: n[2] / 255, alpha: n.count > 3 ? n[3] : 1))
    }
    let named: [String: UInt32] = [
      "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "blue": 0x0000FF,
      "gray": 0x808080, "grey": 0x808080, "yellow": 0xFFFF00, "orange": 0xFFA500, "purple": 0x800080,
    ]
    return named[v].map { .color(rgb($0)) }
  }

  private static func hex(_ h: String) -> UIColor? {
    let expanded = h.count == 3 || h.count == 4 ? h.map { "\($0)\($0)" }.joined() : h
    guard let value = UInt64(expanded, radix: 16) else { return nil }
    switch expanded.count {
    case 6: return rgb(UInt32(value))
    case 8:
      return UIColor(
        red: CGFloat((value >> 24) & 0xFF) / 255, green: CGFloat((value >> 16) & 0xFF) / 255,
        blue: CGFloat((value >> 8) & 0xFF) / 255, alpha: CGFloat(value & 0xFF) / 255)
    default: return nil
    }
  }

  private static func rgb(_ v: UInt32) -> UIColor {
    UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
  }
}

enum SVGTransform {
  /// `transform="A B C"` applies C first, then B, then A.
  static func parse(_ s: String) -> CGAffineTransform {
    var result = CGAffineTransform.identity
    var rest = Substring(s)
    while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
      let name = rest[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\t\n"))
      let n = SVGNumbers.list(String(rest[rest.index(after: open)..<close]))
      rest = rest[rest.index(after: close)...]
      let t: CGAffineTransform
      switch name {
      case "matrix" where n.count == 6:
        t = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
      case "translate" where !n.isEmpty:
        t = CGAffineTransform(translationX: n[0], y: n.count > 1 ? n[1] : 0)
      case "scale" where !n.isEmpty:
        t = CGAffineTransform(scaleX: n[0], y: n.count > 1 ? n[1] : n[0])
      case "rotate" where !n.isEmpty:
        let r = CGAffineTransform(rotationAngle: n[0] * .pi / 180)
        t = n.count == 3
          ? CGAffineTransform(translationX: -n[1], y: -n[2]).concatenating(r).concatenating(
            CGAffineTransform(translationX: n[1], y: n[2]))
          : r
      case "skewX" where !n.isEmpty:
        t = CGAffineTransform(a: 1, b: 0, c: tan(n[0] * .pi / 180), d: 1, tx: 0, ty: 0)
      case "skewY" where !n.isEmpty:
        t = CGAffineTransform(a: 1, b: tan(n[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
      default:
        continue
      }
      result = t.concatenating(result)
    }
    return result
  }
}

// MARK: - Path data

/// Number scanner for SVG's compact syntax: `1.5.5`, `-1-2`, `1e-3`, and
/// single-digit arc flags written without separators (`a1 1 0 00 1 1`).
struct SVGScanner {
  private let bytes: [UInt8]
  private(set) var i = 0

  init(_ s: String) { bytes = Array(s.utf8) }

  var atEnd: Bool {
    mutating get {
      skipSeparators()
      return i >= bytes.count
    }
  }

  /// Skips one unparseable byte (e.g. the letters in `rgb(`).
  mutating func advance() { i += 1 }

  mutating func skipSeparators() {
    while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x2C || bytes[i] == 0x09 || bytes[i] == 0x0A || bytes[i] == 0x0D {
      i += 1
    }
  }

  mutating func peekCommand() -> UInt8? {
    skipSeparators()
    guard i < bytes.count else { return nil }
    let c = bytes[i]
    return (c >= 0x41 && c <= 0x5A || c >= 0x61 && c <= 0x7A) && c != 0x65 && c != 0x45 ? c : nil
  }

  mutating func command() -> UInt8? {
    guard let c = peekCommand() else { return nil }
    i += 1
    return c
  }

  mutating func flag() -> Bool? {
    skipSeparators()
    guard i < bytes.count, bytes[i] == 0x30 || bytes[i] == 0x31 else { return nil }
    defer { i += 1 }
    return bytes[i] == 0x31
  }

  mutating func number() -> CGFloat? {
    skipSeparators()
    let start = i
    if i < bytes.count, bytes[i] == 0x2B || bytes[i] == 0x2D { i += 1 }
    var digits = 0, sawDot = false
    while i < bytes.count {
      let c = bytes[i]
      if c >= 0x30 && c <= 0x39 {
        digits += 1
      } else if c == 0x2E && !sawDot {
        sawDot = true
      } else {
        break
      }
      i += 1
    }
    guard digits > 0 else {
      i = start
      return nil
    }
    if i < bytes.count, bytes[i] == 0x65 || bytes[i] == 0x45 {
      let save = i
      i += 1
      if i < bytes.count, bytes[i] == 0x2B || bytes[i] == 0x2D { i += 1 }
      var expDigits = 0
      while i < bytes.count, bytes[i] >= 0x30 && bytes[i] <= 0x39 {
        i += 1
        expDigits += 1
      }
      if expDigits == 0 { i = save }
    }
    return String(bytes: bytes[start..<i], encoding: .ascii).flatMap(Double.init).map { CGFloat($0) }
  }
}

enum SVGPathParser {
  static func parse(_ d: String) -> CGPath {
    let path = CGMutablePath()
    var s = SVGScanner(d)
    var current = CGPoint.zero, start = CGPoint.zero
    var lastCubic: CGPoint?, lastQuad: CGPoint?
    var cmd: UInt8 = 0

    while !s.atEnd {
      if let c = s.command() {
        cmd = c
      } else if cmd == 0 {
        break  // numbers before any command
      }
      let rel = cmd >= 0x61
      func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y) }
      var nextCubic: CGPoint?, nextQuad: CGPoint?

      switch cmd | 0x20 {  // lowercase
      case 0x6D:  // m
        guard let x = s.number(), let y = s.number() else { return path }
        current = pt(x, y)
        start = current
        path.move(to: current)
        cmd = rel ? 0x6C : 0x4C  // following pairs are lineTo
      case 0x6C:  // l
        guard let x = s.number(), let y = s.number() else { return path }
        current = pt(x, y)
        path.addLine(to: current)
      case 0x68:  // h
        guard let x = s.number() else { return path }
        current = CGPoint(x: rel ? current.x + x : x, y: current.y)
        path.addLine(to: current)
      case 0x76:  // v
        guard let y = s.number() else { return path }
        current = CGPoint(x: current.x, y: rel ? current.y + y : y)
        path.addLine(to: current)
      case 0x63:  // c
        guard let x1 = s.number(), let y1 = s.number(), let x2 = s.number(), let y2 = s.number(),
          let x = s.number(), let y = s.number()
        else { return path }
        let c1 = pt(x1, y1), c2 = pt(x2, y2), end = pt(x, y)
        path.addCurve(to: end, control1: c1, control2: c2)
        nextCubic = c2
        current = end
      case 0x73:  // s
        guard let x2 = s.number(), let y2 = s.number(), let x = s.number(), let y = s.number() else { return path }
        let c1 = lastCubic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
        let c2 = pt(x2, y2), end = pt(x, y)
        path.addCurve(to: end, control1: c1, control2: c2)
        nextCubic = c2
        current = end
      case 0x71:  // q
        guard let x1 = s.number(), let y1 = s.number(), let x = s.number(), let y = s.number() else { return path }
        let c = pt(x1, y1), end = pt(x, y)
        path.addQuadCurve(to: end, control: c)
        nextQuad = c
        current = end
      case 0x74:  // t
        guard let x = s.number(), let y = s.number() else { return path }
        let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
        let end = pt(x, y)
        path.addQuadCurve(to: end, control: c)
        nextQuad = c
        current = end
      case 0x61:  // a
        guard let rx = s.number(), let ry = s.number(), let rot = s.number(), let large = s.flag(),
          let sweep = s.flag(), let x = s.number(), let y = s.number()
        else { return path }
        let end = pt(x, y)
        addArc(path, from: current, to: end, rx: rx, ry: ry, rotation: rot, largeArc: large, sweep: sweep)
        current = end
      case 0x7A:  // z
        path.closeSubpath()
        current = start
        cmd = 0  // bare numbers after z are invalid; stop rather than spin
      default:
        return path
      }
      lastCubic = nextCubic
      lastQuad = nextQuad
    }
    return path
  }

  /// SVG endpoint arc → centre parameterisation (SVG 1.1 §F.6.5), emitted as
  /// cubic Béziers of at most 90° each.
  static func addArc(
    _ path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
    rotation: CGFloat, largeArc: Bool, sweep: Bool
  ) {
    guard p0 != p1 else { return }
    var rx = abs(rxIn), ry = abs(ryIn)
    guard rx > 0, ry > 0 else {
      path.addLine(to: p1)
      return
    }
    let phi = rotation * .pi / 180
    let cosP = cos(phi), sinP = sin(phi)
    let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
    let x1 = cosP * dx + sinP * dy
    let y1 = -sinP * dx + cosP * dy

    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 {
      rx *= sqrt(lambda)
      ry *= sqrt(lambda)
    }
    let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    var coef = den == 0 ? 0 : sqrt(max(0, num / den))
    if largeArc == sweep { coef = -coef }
    let cxp = coef * rx * y1 / ry
    let cyp = -coef * ry * x1 / rx
    let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
    let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2

    func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
      atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    }
    let theta1 = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
    var delta = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
    if !sweep && delta > 0 { delta -= 2 * .pi }
    if sweep && delta < 0 { delta += 2 * .pi }

    let segments = max(1, Int(ceil(abs(delta) / (.pi / 2) - 1e-7)))
    let step = delta / CGFloat(segments)
    let k = 4 / 3 * tan(step / 4)
    func point(_ t: CGFloat) -> CGPoint {
      CGPoint(x: cx + rx * cos(t) * cosP - ry * sin(t) * sinP, y: cy + rx * cos(t) * sinP + ry * sin(t) * cosP)
    }
    func derivative(_ t: CGFloat) -> CGPoint {
      CGPoint(x: -rx * sin(t) * cosP - ry * cos(t) * sinP, y: -rx * sin(t) * sinP + ry * cos(t) * cosP)
    }
    var t = theta1
    for _ in 0..<segments {
      let t2 = t + step
      let a = point(t), b = point(t2), da = derivative(t), db = derivative(t2)
      path.addCurve(
        to: b,
        control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
        control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
      t = t2
    }
  }
}
