import UIKit

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
