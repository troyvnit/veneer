import CoreText
import UIKit

/// A native SVG renderer: `XMLParser` builds the document tree, CoreGraphics
/// and CoreText draw it.
///
/// Structure: `svg` (nested, with viewports), `g`, `a`, `switch`, `defs`,
/// `symbol`, `use` (with `href`/`xlink:href`), `style`.
/// Shapes: `path` (full grammar), `rect` (rx/ry), `circle`, `ellipse`, `line`,
/// `polyline`, `polygon`; `text`/`tspan` (CoreText); `image` (`data:` URIs).
/// Paint: colours (hex, rgb/rgba, hsl/hsla, 148 CSS names, `currentColor`),
/// linear/radial gradients (units, transform, `href` inheritance, pad/
/// reflect/repeat), fill/stroke opacities, fill/clip rules, caps, joins,
/// miter limit, dashes.
/// Compositing: group `opacity` (transparency layers), `clip-path`, luminance
/// `mask`, `display`, `visibility`, `overflow`.
/// Styling: presentation attributes, `<style>` CSS (type/class/id/universal,
/// compound and descendant selectors, specificity, `@media` bodies), inline
/// `style`, inheritance, `inherit`.
/// Layout: `viewBox`, `preserveAspectRatio` (align + meet/slice/none), units
/// (px, pt, pc, in, cm, mm, em, ex, %).
///
/// Not rendered: filters, patterns (their fallback colour is used), markers,
/// `textPath`, `foreignObject`, animation, external `href`s.
final class SVGIcon {
  let root: SVGNode
  let viewBox: CGRect
  let aspect: SVGAspectRatio
  fileprivate let ids: [String: SVGNode]
  fileprivate let css: [CSSRule]
  fileprivate var propertyCache: [ObjectIdentifier: [String: String]] = [:]

  init?(data: Data) {
    let builder = SVGTreeBuilder()
    let parser = XMLParser(data: data)
    parser.delegate = builder
    guard parser.parse(), let svg = builder.document.children.first(where: { $0.name == "svg" }) else { return nil }
    root = svg
    var ids: [String: SVGNode] = [:]
    svg.walk { if let id = $0.attributes["id"] { ids[id] = $0 } }
    self.ids = ids
    css = builder.styleSheets.flatMap { CSSParser.rules(from: $0) }
    aspect = SVGAspectRatio(svg.attributes["preserveAspectRatio"])

    if let vb = svg.attributes["viewBox"].map(SVGNumbers.list), vb.count == 4, vb[2] > 0, vb[3] > 0 {
      viewBox = CGRect(x: vb[0], y: vb[1], width: vb[2], height: vb[3])
    } else if let w = SVGNumbers.length(svg.attributes["width"]), let h = SVGNumbers.length(svg.attributes["height"]),
      w > 0, h > 0
    {
      viewBox = CGRect(x: 0, y: 0, width: w, height: h)
    } else {
      viewBox = CGRect(x: 0, y: 0, width: 24, height: 24)
    }
  }

  /// Renders into a `size`×`size` image. `template` paints every colour as
  /// black (keeping alpha) and returns a template image that UIKit tints like
  /// an SF Symbol; otherwise colours are kept and `currentColor` resolves to
  /// `currentColor`.
  func image(size: CGFloat, template: Bool, currentColor: UIColor = .black) -> UIImage {
    let format = UIGraphicsImageRendererFormat.preferred()
    let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
      let r = SVGRenderer(icon: self, ctx: ctx.cgContext, template: template, currentColor: currentColor)
      ctx.cgContext.concatenate(aspect.transform(viewBox: viewBox, into: CGSize(width: size, height: size)))
      // The root's own presentation attributes (fill="none", stroke, color…) apply to everything.
      let rootProps = properties(of: root)
      if let t = rootProps["transform"] { ctx.cgContext.concatenate(SVGTransform.parse(t)) }
      r.renderChildren(of: root, style: SVGStyle().inheriting(rootProps, viewport: viewBox.size), viewport: viewBox.size, depth: 0)
    }
    return image.withRenderingMode(template ? .alwaysTemplate : .alwaysOriginal)
  }

  /// Computed, non-inherited declaration map for `node`: presentation
  /// attributes < stylesheet rules (by specificity, then order) < `style`.
  fileprivate func properties(of node: SVGNode) -> [String: String] {
    let key = ObjectIdentifier(node)
    if let cached = propertyCache[key] { return cached }
    var p: [String: String] = [:]
    for (k, v) in node.attributes where Self.presentationAttributes.contains(k) { p[k] = v }
    let matching = css.filter { $0.selector.matches(node) }.sorted { a, b in
      a.selector.specificity == b.selector.specificity
        ? a.order < b.order
        : a.selector.specificity.lexicographicallyPrecedes(b.selector.specificity)
    }
    for rule in matching {
      p.merge(rule.declarations) { $1 }
    }
    if let inline = node.attributes["style"] { p.merge(CSSParser.declarations(inline)) { $1 } }
    propertyCache[key] = p
    return p
  }

  fileprivate static let presentationAttributes: Set<String> = [
    "fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-opacity", "stroke-linecap",
    "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset", "opacity", "color",
    "display", "visibility", "clip-path", "clip-rule", "mask", "stop-color", "stop-opacity", "font-size",
    "font-family", "font-weight", "font-style", "text-anchor", "overflow", "transform",
  ]
}

// MARK: - Document tree

final class SVGNode {
  /// Local element name, or `#text` for character data.
  let name: String
  let attributes: [String: String]
  var children: [SVGNode] = []
  weak var parent: SVGNode?
  var text = ""

  init(name: String, attributes: [String: String]) {
    self.name = name
    self.attributes = attributes
  }

  lazy var classes: Set<String> = Set((attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))

  var href: String? { attributes["href"] ?? attributes["xlink:href"] }

  func walk(_ visit: (SVGNode) -> Void) {
    visit(self)
    for child in children { child.walk(visit) }
  }
}

private final class SVGTreeBuilder: NSObject, XMLParserDelegate {
  let document = SVGNode(name: "#document", attributes: [:])
  var styleSheets: [String] = []
  private lazy var current = document

  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
    attributes: [String: String]
  ) {
    let local = name.split(separator: ":").last.map(String.init) ?? name
    let node = SVGNode(name: local, attributes: attributes)
    node.parent = current
    current.children.append(node)
    current = node
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) { appendText(string) }

  func parser(_ parser: XMLParser, foundCDATA block: Data) {
    if let s = String(data: block, encoding: .utf8) { appendText(s) }
  }

  private func appendText(_ s: String) {
    if current.name == "style" {
      current.text += s
    } else if let last = current.children.last, last.name == "#text" {
      last.text += s
    } else {
      let t = SVGNode(name: "#text", attributes: [:])
      t.text = s
      t.parent = current
      current.children.append(t)
    }
  }

  func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    if current.name == "style" { styleSheets.append(current.text) }
    current = current.parent ?? document
  }
}

// MARK: - CSS

struct CSSRule {
  let selector: CSSSelector
  let declarations: [String: String]
  let order: Int
}

struct CSSSelector {
  struct Compound {
    var tag: String?
    var id: String?
    var classes: [String] = []
    /// Pseudo-classes and attribute selectors: never match statically.
    var unsupported = false

    func matches(_ n: SVGNode) -> Bool {
      guard !unsupported, n.name != "#text" else { return false }
      if let tag, tag != n.name { return false }
      if let id, id != n.attributes["id"] { return false }
      return classes.allSatisfy(n.classes.contains)
    }
  }

  /// Descendant chain; the last compound is the subject.
  let compounds: [Compound]

  var specificity: [Int] {
    [
      compounds.filter { $0.id != nil }.count,
      compounds.reduce(0) { $0 + $1.classes.count },
      compounds.filter { $0.tag != nil }.count,
    ]
  }

  func matches(_ node: SVGNode) -> Bool {
    guard let subject = compounds.last, subject.matches(node) else { return false }
    var ancestor = node.parent
    for compound in compounds.dropLast().reversed() {
      while let a = ancestor, !compound.matches(a) { ancestor = a.parent }
      guard ancestor != nil else { return false }
      ancestor = ancestor?.parent
    }
    return true
  }
}

enum CSSParser {
  static func rules(from sheet: String) -> [CSSRule] {
    var order = 0
    var rules: [CSSRule] = []
    parseBlock(stripComments(sheet), into: &rules, order: &order)
    return rules
  }

  private static func parseBlock(_ s: String, into rules: inout [CSSRule], order: inout Int) {
    var i = s.startIndex
    while i < s.endIndex {
      guard let open = s[i...].firstIndex(of: "{") else { return }
      let prelude = s[i..<open].trimmingCharacters(in: .whitespacesAndNewlines)
      // Find the matching close brace (at-rules nest).
      var depth = 0
      var close = open
      var j = open
      while j < s.endIndex {
        if s[j] == "{" { depth += 1 }
        if s[j] == "}" {
          depth -= 1
          if depth == 0 {
            close = j
            break
          }
        }
        j = s.index(after: j)
      }
      guard close > open else { return }
      let body = String(s[s.index(after: open)..<close])
      if prelude.hasPrefix("@") {
        if prelude.hasPrefix("@media") || prelude.hasPrefix("@supports") { parseBlock(body, into: &rules, order: &order) }
      } else {
        let decls = declarations(body)
        for sel in prelude.split(separator: ",") {
          rules.append(CSSRule(selector: selector(String(sel)), declarations: decls, order: order))
          order += 1
        }
      }
      i = s.index(after: close)
    }
  }

  static func declarations(_ body: String) -> [String: String] {
    var out: [String: String] = [:]
    for decl in body.split(separator: ";") {
      let kv = decl.split(separator: ":", maxSplits: 1)
      guard kv.count == 2 else { continue }
      let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let value = kv[1].replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
      out[key] = value
    }
    return out
  }

  private static func selector(_ raw: String) -> CSSSelector {
    let parts = raw.replacingOccurrences(of: ">", with: " ").replacingOccurrences(of: "+", with: " ")
      .split(whereSeparator: \.isWhitespace)
    return CSSSelector(compounds: parts.map { compound(String($0)) })
  }

  private static func compound(_ s: String) -> CSSSelector.Compound {
    var c = CSSSelector.Compound()
    if s.contains(":") || s.contains("[") || s.contains("~") { c.unsupported = true }
    var token = ""
    var kind: Character = "t"
    func flush() {
      guard !token.isEmpty else { return }
      switch kind {
      case "#": c.id = token
      case ".": c.classes.append(token)
      default: if token != "*" { c.tag = token.split(separator: "|").last.map(String.init) }
      }
      token = ""
    }
    for ch in s {
      if ch == "." || ch == "#" {
        flush()
        kind = ch
      } else {
        token.append(ch)
      }
    }
    flush()
    return c
  }

  private static func stripComments(_ s: String) -> String {
    var out = ""
    var rest = Substring(s)
    while let start = rest.range(of: "/*") {
      out += rest[..<start.lowerBound]
      guard let end = rest[start.upperBound...].range(of: "*/") else { return out }
      rest = rest[end.upperBound...]
    }
    return out + rest
  }
}

// MARK: - Style

indirect enum SVGPaint {
  case none
  case currentColor
  case color(UIColor)
  case server(id: String, fallback: SVGPaint?)

  static func parse(_ raw: String) -> SVGPaint? {
    let v = raw.trimmingCharacters(in: .whitespaces)
    switch v.lowercased() {
    case "none": return SVGPaint.none
    case "currentcolor": return .currentColor
    case "", "inherit": return nil
    default: break
    }
    if v.hasPrefix("url(") , let close = v.firstIndex(of: ")") {
      let inner = v[v.index(v.startIndex, offsetBy: 4)..<close].trimmingCharacters(in: CharacterSet(charactersIn: " '\"#"))
      let rest = v[v.index(after: close)...].trimmingCharacters(in: .whitespaces)
      return .server(id: inner, fallback: rest.isEmpty ? nil : parse(rest))
    }
    return SVGColor.parse(v).map(SVGPaint.color)
  }
}

struct SVGStyle {
  var fill: SVGPaint = .color(.black)
  var fillOpacity: CGFloat = 1
  var fillEvenOdd = false
  var stroke: SVGPaint = .none
  var strokeWidth: CGFloat = 1
  var strokeOpacity: CGFloat = 1
  var lineCap: CGLineCap = .butt
  var lineJoin: CGLineJoin = .miter
  var miterLimit: CGFloat = 4
  var dashes: [CGFloat] = []
  var dashOffset: CGFloat = 0
  /// CSS `color`, the value of `currentColor`; nil = the renderer's default.
  var color: UIColor?
  var visible = true
  var clipEvenOdd = false
  var fontSize: CGFloat = 16
  var fontFamily = "sans-serif"
  var fontWeight: CGFloat = 400
  var italic = false
  var textAnchor = "start"

  /// Applies the inherited properties among `p` to a copy of this style.
  func inheriting(_ p: [String: String], viewport: CGSize) -> SVGStyle {
    var s = self
    func value(_ key: String) -> String? {
      guard let v = p[key], v != "inherit" else { return nil }
      return v
    }
    if let v = value("font-size") { s.fontSize = SVGNumbers.length(v, viewport: viewport, fontSize: fontSize) ?? s.fontSize }
    if let v = value("color"), let c = SVGColor.parse(v) { s.color = c }
    if let v = value("fill"), let paint = SVGPaint.parse(v) { s.fill = paint }
    if let v = value("stroke"), let paint = SVGPaint.parse(v) { s.stroke = paint }
    if let v = value("fill-opacity").flatMap(SVGNumbers.fraction) { s.fillOpacity = v }
    if let v = value("stroke-opacity").flatMap(SVGNumbers.fraction) { s.strokeOpacity = v }
    if let v = value("fill-rule") { s.fillEvenOdd = v == "evenodd" }
    if let v = value("clip-rule") { s.clipEvenOdd = v == "evenodd" }
    if let v = value("stroke-width") { s.strokeWidth = SVGNumbers.length(v, viewport: viewport, fontSize: s.fontSize) ?? s.strokeWidth }
    if let v = value("stroke-miterlimit").flatMap({ SVGNumbers.length($0) }) { s.miterLimit = v }
    if let v = value("stroke-dasharray") {
      let d = v == "none" ? [] : SVGNumbers.list(v).map { max(0, $0) }
      s.dashes = d.allSatisfy({ $0 == 0 }) ? [] : (d.count % 2 == 1 ? d + d : d)
    }
    if let v = value("stroke-dashoffset") { s.dashOffset = SVGNumbers.length(v, viewport: viewport) ?? 0 }
    if let v = value("visibility") { s.visible = v == "visible" }
    if let v = value("font-family") { s.fontFamily = v }
    if let v = value("font-style") { s.italic = v == "italic" || v == "oblique" }
    if let v = value("text-anchor") { s.textAnchor = v }
    if let v = value("font-weight") {
      switch v {
      case "normal": s.fontWeight = 400
      case "bold": s.fontWeight = 700
      case "bolder": s.fontWeight = min(900, s.fontWeight + 300)
      case "lighter": s.fontWeight = max(100, s.fontWeight - 300)
      default: s.fontWeight = Double(v).map { CGFloat($0) } ?? s.fontWeight
      }
    }
    switch value("stroke-linecap") {
    case "round": s.lineCap = .round
    case "square": s.lineCap = .square
    case "butt": s.lineCap = .butt
    default: break
    }
    switch value("stroke-linejoin") {
    case "round": s.lineJoin = .round
    case "bevel": s.lineJoin = .bevel
    case "miter", "miter-clip", "arcs": s.lineJoin = .miter
    default: break
    }
    return s
  }
}

struct SVGAspectRatio {
  /// nil = `none` (stretch).
  var align: CGPoint? = CGPoint(x: 0.5, y: 0.5)
  var slice = false

  init(_ raw: String?) {
    let parts = (raw ?? "").split(whereSeparator: \.isWhitespace).map(String.init).filter { $0 != "defer" }
    guard let a = parts.first else { return }
    if a == "none" {
      align = nil
      return
    }
    func axis(_ s: Substring) -> CGFloat { s == "Min" ? 0 : s == "Max" ? 1 : 0.5 }
    if a.count == 8 {
      align = CGPoint(x: axis(a.dropFirst(1).prefix(3)), y: axis(a.dropFirst(5).prefix(3)))
    }
    slice = parts.dropFirst().first == "slice"
  }

  func transform(viewBox vb: CGRect, into size: CGSize) -> CGAffineTransform {
    let sx = size.width / vb.width, sy = size.height / vb.height
    guard let align else {
      return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: -vb.minX * sx, ty: -vb.minY * sy)
    }
    let s = slice ? max(sx, sy) : min(sx, sy)
    let tx = (size.width - vb.width * s) * align.x - vb.minX * s
    let ty = (size.height - vb.height * s) * align.y - vb.minY * s
    return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: ty)
  }
}

// MARK: - Rendering

private struct SVGRenderer {
  let icon: SVGIcon
  let ctx: CGContext
  /// Paint every colour black (alpha kept) for template images.
  let template: Bool
  let currentColor: UIColor

  private static let maxDepth = 48
  /// Everything else (defs, symbol, clipPath, mask, gradients, style,
  /// metadata, unsupported elements) only renders by reference, or not at all.
  private static let renderable: Set<String> = [
    "g", "a", "switch", "svg", "use", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "image",
  ]

  func renderChildren(of node: SVGNode, style: SVGStyle, viewport: CGSize, depth: Int) {
    if node.name == "switch" {
      // First child that we can render wins; conditional attributes are
      // ignored, so that's the first element.
      if let first = node.children.first(where: { $0.name != "#text" }) {
        render(first, inherited: style, viewport: viewport, depth: depth + 1)
      }
      return
    }
    for child in node.children { render(child, inherited: style, viewport: viewport, depth: depth + 1) }
  }

  func render(_ node: SVGNode, inherited: SVGStyle, viewport: CGSize, depth: Int) {
    guard depth < Self.maxDepth, Self.renderable.contains(node.name) else { return }
    let p = icon.properties(of: node)
    if p["display"] == "none" { return }
    let style = inherited.inheriting(p, viewport: viewport)
    let opacity = SVGNumbers.fraction(p["opacity"]).map { max(0, min(1, $0)) } ?? 1
    guard opacity > 0 else { return }

    ctx.saveGState()
    defer { ctx.restoreGState() }
    if let t = p["transform"] { ctx.concatenate(SVGTransform.parse(t)) }

    let bbox = { [icon] in SVGGeometry.bounds(of: node, icon: icon, viewport: viewport) }
    if let id = Self.reference(p["clip-path"]) { applyClip(id, bbox: bbox, style: style, viewport: viewport) }
    if let id = Self.reference(p["mask"]) { applyMask(id, bbox: bbox, style: style, viewport: viewport, depth: depth) }

    let layered = opacity < 1
    if layered {
      ctx.setAlpha(opacity)
      ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    }
    defer { if layered { ctx.endTransparencyLayer() } }

    switch node.name {
    case "g", "a", "switch":
      renderChildren(of: node, style: style, viewport: viewport, depth: depth)
    case "svg":
      let a = node.attributes
      let rect = CGRect(
        x: SVGNumbers.length(a["x"], axis: .x, viewport: viewport) ?? 0,
        y: SVGNumbers.length(a["y"], axis: .y, viewport: viewport) ?? 0,
        width: SVGNumbers.length(a["width"] ?? "100%", axis: .x, viewport: viewport) ?? viewport.width,
        height: SVGNumbers.length(a["height"] ?? "100%", axis: .y, viewport: viewport) ?? viewport.height)
      renderViewport(node, content: node, rect: rect, style: style, depth: depth, overflow: p["overflow"])
    case "use":
      renderUse(node, style: style, viewport: viewport, depth: depth)
    case "text":
      guard style.visible else { break }
      SVGText.draw(node, style: style, viewport: viewport, renderer: self)
    case "image":
      guard style.visible else { break }
      drawImage(node, viewport: viewport)
    default:
      guard style.visible, let path = SVGGeometry.path(of: node, viewport: viewport, fontSize: style.fontSize) else { break }
      fill(path, style: style, viewport: viewport)
      stroke(path, style: style, viewport: viewport)
    }
  }

  // MARK: Viewports, use

  private func renderViewport(
    _ node: SVGNode, content: SVGNode, rect: CGRect, style: SVGStyle, depth: Int, overflow: String?
  ) {
    guard rect.width > 0, rect.height > 0 else { return }
    ctx.saveGState()
    defer { ctx.restoreGState() }
    if overflow != "visible" && overflow != "auto" { ctx.clip(to: rect) }
    ctx.translateBy(x: rect.minX, y: rect.minY)
    var inner = rect.size
    if let vb = content.attributes["viewBox"].map(SVGNumbers.list), vb.count == 4, vb[2] > 0, vb[3] > 0 {
      let viewBox = CGRect(x: vb[0], y: vb[1], width: vb[2], height: vb[3])
      ctx.concatenate(SVGAspectRatio(content.attributes["preserveAspectRatio"]).transform(viewBox: viewBox, into: rect.size))
      inner = viewBox.size
    }
    renderChildren(of: content, style: style, viewport: inner, depth: depth)
  }

  private func renderUse(_ node: SVGNode, style: SVGStyle, viewport: CGSize, depth: Int) {
    guard let id = node.href.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }),
      let target = icon.ids[id], !Self.isAncestor(target, of: node)
    else { return }
    let a = node.attributes
    let x = SVGNumbers.length(a["x"], axis: .x, viewport: viewport) ?? 0
    let y = SVGNumbers.length(a["y"], axis: .y, viewport: viewport) ?? 0
    if target.name == "symbol" || target.name == "svg" {
      let rect = CGRect(
        x: x, y: y,
        width: SVGNumbers.length(a["width"] ?? target.attributes["width"] ?? "100%", axis: .x, viewport: viewport) ?? viewport.width,
        height: SVGNumbers.length(a["height"] ?? target.attributes["height"] ?? "100%", axis: .y, viewport: viewport) ?? viewport.height)
      let targetStyle = style.inheriting(icon.properties(of: target), viewport: viewport)
      renderViewport(target, content: target, rect: rect, style: targetStyle, depth: depth + 1, overflow: icon.properties(of: target)["overflow"])
    } else {
      ctx.saveGState()
      ctx.translateBy(x: x, y: y)
      render(target, inherited: style, viewport: viewport, depth: depth + 1)
      ctx.restoreGState()
    }
  }

  private static func isAncestor(_ a: SVGNode, of node: SVGNode) -> Bool {
    var n: SVGNode? = node
    while let cur = n {
      if cur === a { return true }
      n = cur.parent
    }
    return false
  }

  static func reference(_ raw: String?) -> String? {
    guard let raw, raw.hasPrefix("url("), let close = raw.firstIndex(of: ")") else { return nil }
    return raw[raw.index(raw.startIndex, offsetBy: 4)..<close].trimmingCharacters(in: CharacterSet(charactersIn: " '\"#"))
  }

  // MARK: Paint

  func color(_ c: UIColor, opacity: CGFloat) -> CGColor {
    var alpha: CGFloat = 1
    c.getRed(nil, green: nil, blue: nil, alpha: &alpha)
    return (template ? UIColor.black : c).withAlphaComponent(alpha * opacity).cgColor
  }

  enum Resolved {
    case none
    case color(UIColor)
    case gradient(SVGGradient)
  }

  func resolve(_ paint: SVGPaint, style: SVGStyle) -> Resolved {
    switch paint {
    case .none: return .none
    case .currentColor: return .color(style.color ?? currentColor)
    case .color(let c): return .color(c)
    case let .server(id, fallback):
      if let node = icon.ids[id], let g = SVGGradient(node, icon: icon) { return .gradient(g) }
      return fallback.map { resolve($0, style: style) } ?? .none
    }
  }

  func fill(_ path: CGPath, style: SVGStyle, viewport: CGSize) {
    let rule: CGPathFillRule = style.fillEvenOdd ? .evenOdd : .winding
    switch resolve(style.fill, style: style) {
    case .none:
      return
    case .color(let c):
      ctx.addPath(path)
      ctx.setFillColor(color(c, opacity: style.fillOpacity))
      ctx.fillPath(using: rule)
    case .gradient(let g):
      ctx.saveGState()
      ctx.addPath(path)
      ctx.clip(using: rule)
      g.draw(in: ctx, bbox: path.boundingBoxOfPath, viewport: viewport, opacity: style.fillOpacity, renderer: self)
      ctx.restoreGState()
    }
  }

  func stroke(_ path: CGPath, style: SVGStyle, viewport: CGSize) {
    guard style.strokeWidth > 0 else { return }
    let paint = resolve(style.stroke, style: style)
    if case .none = paint { return }
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.setLineWidth(style.strokeWidth)
    ctx.setLineCap(style.lineCap)
    ctx.setLineJoin(style.lineJoin)
    ctx.setMiterLimit(style.miterLimit)
    if !style.dashes.isEmpty { ctx.setLineDash(phase: style.dashOffset, lengths: style.dashes) }
    ctx.addPath(path)
    switch paint {
    case .none:
      return
    case .color(let c):
      ctx.setStrokeColor(color(c, opacity: style.strokeOpacity))
      ctx.strokePath()
    case .gradient(let g):
      ctx.replacePathWithStrokedPath()
      ctx.clip()
      g.draw(in: ctx, bbox: path.boundingBoxOfPath, viewport: viewport, opacity: style.strokeOpacity, renderer: self)
    }
  }

  // MARK: Clip, mask

  private func applyClip(_ id: String, bbox: () -> CGRect, style: SVGStyle, viewport: CGSize) {
    guard let clip = icon.ids[id], clip.name == "clipPath" else { return }
    var combined: CGPath?
    for child in clip.children where child.name != "#text" {
      let cp = icon.properties(of: child)
      if cp["display"] == "none" { continue }
      var geometry: CGPath?
      if child.name == "use", let ref = child.href.flatMap({ icon.ids[$0.trimmingCharacters(in: CharacterSet(charactersIn: "#"))] }) {
        let x = SVGNumbers.length(child.attributes["x"], axis: .x, viewport: viewport) ?? 0
        let y = SVGNumbers.length(child.attributes["y"], axis: .y, viewport: viewport) ?? 0
        var t = CGAffineTransform(translationX: x, y: y)
        geometry = SVGGeometry.path(of: ref, viewport: viewport, fontSize: style.fontSize)?.copy(using: &t)
      } else {
        geometry = SVGGeometry.path(of: child, viewport: viewport, fontSize: style.fontSize)
      }
      guard var g = geometry else { continue }
      if let t = cp["transform"] {
        var m = SVGTransform.parse(t)
        g = g.copy(using: &m) ?? g
      }
      let evenOdd = style.inheriting(cp, viewport: viewport).clipEvenOdd
      combined = combined.map { $0.union(g, using: evenOdd ? .evenOdd : .winding) } ?? (evenOdd ? g.normalized(using: .evenOdd) : g)
    }
    guard var path = combined else {
      ctx.clip(to: .zero)  // an empty clip path hides the element
      return
    }
    let cp = icon.properties(of: clip)
    var t = (cp["transform"] ?? clip.attributes["transform"]).map(SVGTransform.parse) ?? .identity
    if clip.attributes["clipPathUnits"] == "objectBoundingBox" {
      let b = bbox()
      t = t.concatenating(CGAffineTransform(a: b.width, b: 0, c: 0, d: b.height, tx: b.minX, ty: b.minY))
    }
    path = path.copy(using: &t) ?? path
    ctx.addPath(path)
    ctx.clip()
  }

  /// Luminance mask: the mask content is drawn into a greyscale bitmap over
  /// black (so grey = luminance × alpha) at device resolution, covering the
  /// current clip, then used as a clip mask. Sized from the clip box in
  /// device space, so it works for any context, not only bitmap ones.
  private func applyMask(_ id: String, bbox: () -> CGRect, style: SVGStyle, viewport: CGSize, depth: Int) {
    let toDevice = ctx.userSpaceToDeviceSpaceTransform
    let device = ctx.boundingBoxOfClipPath.applying(toDevice).integral
    guard let mask = icon.ids[id], mask.name == "mask", device.width > 0, device.height > 0,
      device.width * device.height < 16_000_000,
      let gray = CGContext(
        data: nil, width: Int(device.width), height: Int(device.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return }
    gray.setFillColor(gray: 0, alpha: 1)
    gray.fill(CGRect(origin: .zero, size: device.size))
    gray.translateBy(x: -device.minX, y: -device.minY)
    gray.concatenate(toDevice)

    let a = mask.attributes
    let b = bbox()
    let region: CGRect
    if a["maskUnits"] == "userSpaceOnUse" {
      region = CGRect(
        x: SVGNumbers.length(a["x"] ?? "-10%", axis: .x, viewport: viewport) ?? 0,
        y: SVGNumbers.length(a["y"] ?? "-10%", axis: .y, viewport: viewport) ?? 0,
        width: SVGNumbers.length(a["width"] ?? "120%", axis: .x, viewport: viewport) ?? viewport.width,
        height: SVGNumbers.length(a["height"] ?? "120%", axis: .y, viewport: viewport) ?? viewport.height)
    } else {
      region = CGRect(
        x: b.minX + (SVGNumbers.fraction(a["x"]) ?? -0.1) * b.width,
        y: b.minY + (SVGNumbers.fraction(a["y"]) ?? -0.1) * b.height,
        width: (SVGNumbers.fraction(a["width"]) ?? 1.2) * b.width,
        height: (SVGNumbers.fraction(a["height"]) ?? 1.2) * b.height)
    }
    gray.clip(to: region)
    if a["maskContentUnits"] == "objectBoundingBox" {
      gray.concatenate(CGAffineTransform(a: b.width, b: 0, c: 0, d: b.height, tx: b.minX, ty: b.minY))
    }
    // Mask content keeps its real colours: luminance is the point.
    let maskRenderer = SVGRenderer(icon: icon, ctx: gray, template: false, currentColor: currentColor)
    maskRenderer.renderChildren(of: mask, style: SVGStyle(), viewport: viewport, depth: depth + 1)
    guard let image = gray.makeImage() else { return }

    ctx.concatenate(toDevice.inverted())
    ctx.clip(to: device, mask: image)
    ctx.concatenate(toDevice)
  }

  // MARK: Images

  private func drawImage(_ node: SVGNode, viewport: CGSize) {
    guard let href = node.href, href.hasPrefix("data:"), let comma = href.firstIndex(of: ",") else { return }
    let header = href[..<comma]
    let payload = String(href[href.index(after: comma)...])
    let data =
      header.contains(";base64")
      ? Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
      : payload.removingPercentEncoding?.data(using: .utf8)
    guard let data else { return }

    let a = node.attributes
    let x = SVGNumbers.length(a["x"], axis: .x, viewport: viewport) ?? 0
    let y = SVGNumbers.length(a["y"], axis: .y, viewport: viewport) ?? 0
    if header.contains("svg"), let nested = SVGIcon(data: data) {
      // Nested SVG image: render its tree into the image rect.
      let w = SVGNumbers.length(a["width"], axis: .x, viewport: viewport) ?? nested.viewBox.width
      let h = SVGNumbers.length(a["height"], axis: .y, viewport: viewport) ?? nested.viewBox.height
      ctx.saveGState()
      ctx.clip(to: CGRect(x: x, y: y, width: w, height: h))
      ctx.translateBy(x: x, y: y)
      ctx.concatenate(SVGAspectRatio(a["preserveAspectRatio"]).transform(viewBox: nested.viewBox, into: CGSize(width: w, height: h)))
      let r = SVGRenderer(icon: nested, ctx: ctx, template: template, currentColor: currentColor)
      r.renderChildren(of: nested.root, style: SVGStyle(), viewport: nested.viewBox.size, depth: 1)
      ctx.restoreGState()
      return
    }
    guard let cg = UIImage(data: data)?.cgImage else { return }
    let natural = CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: CGFloat(cg.height))
    let w = SVGNumbers.length(a["width"], axis: .x, viewport: viewport) ?? natural.width
    let h = SVGNumbers.length(a["height"], axis: .y, viewport: viewport) ?? natural.height
    ctx.saveGState()
    ctx.clip(to: CGRect(x: x, y: y, width: w, height: h))
    ctx.translateBy(x: x, y: y)
    ctx.concatenate(SVGAspectRatio(a["preserveAspectRatio"]).transform(viewBox: natural, into: CGSize(width: w, height: h)))
    // CGImage draws bottom-up; flip within the image's own box.
    ctx.translateBy(x: 0, y: natural.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(cg, in: natural)
    ctx.restoreGState()
  }
}

// MARK: - Gradients

struct SVGGradient {
  let linear: Bool
  let objectBoundingBox: Bool
  let transform: CGAffineTransform
  let attributes: [String: String]
  let stops: [(offset: CGFloat, color: UIColor)]
  let spread: String

  /// Resolves attributes and stops through the `href` chain.
  init?(_ node: SVGNode, icon: SVGIcon) {
    guard node.name == "linearGradient" || node.name == "radialGradient" else { return nil }
    var chain: [SVGNode] = [node]
    while chain.count < 8, let next = chain.last?.href.flatMap({ icon.ids[$0.trimmingCharacters(in: CharacterSet(charactersIn: "#"))] }),
      next.name.hasSuffix("Gradient"), !chain.contains(where: { $0 === next })
    {
      chain.append(next)
    }
    var attrs: [String: String] = [:]
    for n in chain.reversed() { attrs.merge(n.attributes) { $1 } }
    attributes = attrs
    linear = node.name == "linearGradient"
    objectBoundingBox = attrs["gradientUnits"] != "userSpaceOnUse"
    transform = attrs["gradientTransform"].map(SVGTransform.parse) ?? .identity
    spread = attrs["spreadMethod"] ?? "pad"

    let stopNodes = chain.first(where: { $0.children.contains { $0.name == "stop" } })?.children.filter { $0.name == "stop" } ?? []
    var last: CGFloat = 0
    var resolved: [(offset: CGFloat, color: UIColor)] = []
    for stop in stopNodes {
      let p = icon.properties(of: stop)
      let offset = max(last, min(1, max(0, SVGNumbers.fraction(stop.attributes["offset"]) ?? 0)))
      last = offset
      var color = p["stop-color"].flatMap(SVGColor.parse) ?? .black
      if p["stop-color"]?.lowercased() == "currentcolor" { color = .black }
      let opacity = SVGNumbers.fraction(p["stop-opacity"]) ?? 1
      var a: CGFloat = 1
      color.getRed(nil, green: nil, blue: nil, alpha: &a)
      resolved.append((offset, color.withAlphaComponent(a * opacity)))
    }
    guard !resolved.isEmpty else { return nil }
    stops = resolved
  }

  fileprivate func draw(in ctx: CGContext, bbox: CGRect, viewport: CGSize, opacity: CGFloat, renderer: SVGRenderer) {
    if stops.count == 1 {
      ctx.setFillColor(renderer.color(stops[0].color, opacity: opacity))
      ctx.fill(ctx.boundingBoxOfClipPath)
      return
    }
    if objectBoundingBox {
      guard bbox.width > 0, bbox.height > 0 else { return }
      ctx.concatenate(CGAffineTransform(a: bbox.width, b: 0, c: 0, d: bbox.height, tx: bbox.minX, ty: bbox.minY))
    }
    ctx.concatenate(transform)

    func coord(_ key: String, _ fallback: String, _ axis: SVGNumbers.Axis) -> CGFloat {
      let raw = attributes[key] ?? fallback
      return objectBoundingBox ? (SVGNumbers.fraction(raw) ?? 0) : (SVGNumbers.length(raw, axis: axis, viewport: viewport) ?? 0)
    }

    // Emulate reflect/repeat by tiling the stops over many periods.
    let periods = spread == "pad" ? 1 : 24
    var colors: [CGColor] = []
    var locations: [CGFloat] = []
    for k in 0..<periods {
      let reflect = spread == "reflect" && k % 2 == 1
      let ordered = reflect ? stops.reversed().map { (1 - $0.offset, $0.color) } : stops.map { ($0.offset, $0.color) }
      for (offset, c) in ordered {
        colors.append(renderer.color(c, opacity: opacity))
        locations.append((CGFloat(k) + offset) / CGFloat(periods))
      }
    }
    guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)
    else { return }
    let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

    if linear {
      let p1 = CGPoint(x: coord("x1", "0%", .x), y: coord("y1", "0%", .y))
      let p2 = CGPoint(x: coord("x2", "100%", .x), y: coord("y2", "0%", .y))
      let end = CGPoint(x: p1.x + (p2.x - p1.x) * CGFloat(periods), y: p1.y + (p2.y - p1.y) * CGFloat(periods))
      if spread == "pad" {
        ctx.drawLinearGradient(gradient, start: p1, end: p2, options: options)
      } else {
        // Centre the tiled range on the original vector.
        let back = CGFloat(periods / 2)
        let start = CGPoint(x: p1.x - (p2.x - p1.x) * back, y: p1.y - (p2.y - p1.y) * back)
        let shifted = CGPoint(x: end.x - (p2.x - p1.x) * back, y: end.y - (p2.y - p1.y) * back)
        ctx.drawLinearGradient(gradient, start: start, end: shifted, options: options)
      }
    } else {
      let c = CGPoint(x: coord("cx", "50%", .x), y: coord("cy", "50%", .y))
      let r = coord("r", "50%", .other)
      let f = CGPoint(x: attributes["fx"] != nil ? coord("fx", "50%", .x) : c.x, y: attributes["fy"] != nil ? coord("fy", "50%", .y) : c.y)
      let fr = attributes["fr"] != nil ? coord("fr", "0%", .other) : 0
      ctx.drawRadialGradient(
        gradient, startCenter: f, startRadius: fr, endCenter: c, endRadius: r * CGFloat(periods), options: options)
    }
  }
}

// MARK: - Geometry

enum SVGGeometry {
  static func path(of node: SVGNode, viewport: CGSize, fontSize: CGFloat) -> CGPath? {
    let a = node.attributes
    func x(_ k: String) -> CGFloat { SVGNumbers.length(a[k], axis: .x, viewport: viewport, fontSize: fontSize) ?? 0 }
    func y(_ k: String) -> CGFloat { SVGNumbers.length(a[k], axis: .y, viewport: viewport, fontSize: fontSize) ?? 0 }
    func o(_ k: String) -> CGFloat { SVGNumbers.length(a[k], axis: .other, viewport: viewport, fontSize: fontSize) ?? 0 }
    switch node.name {
    case "path":
      return a["d"].map(SVGPathParser.parse)
    case "rect":
      let rect = CGRect(x: x("x"), y: y("y"), width: x("width"), height: y("height"))
      guard rect.width > 0, rect.height > 0 else { return nil }
      var rx = SVGNumbers.length(a["rx"], axis: .x, viewport: viewport)
      var ry = SVGNumbers.length(a["ry"], axis: .y, viewport: viewport)
      if rx == nil { rx = ry }
      if ry == nil { ry = rx }
      let cw = min(rx ?? 0, rect.width / 2), ch = min(ry ?? 0, rect.height / 2)
      return cw > 0 && ch > 0
        ? CGPath(roundedRect: rect, cornerWidth: cw, cornerHeight: ch, transform: nil)
        : CGPath(rect: rect, transform: nil)
    case "circle":
      let r = o("r")
      guard r > 0 else { return nil }
      return CGPath(ellipseIn: CGRect(x: x("cx") - r, y: y("cy") - r, width: 2 * r, height: 2 * r), transform: nil)
    case "ellipse":
      let rx = x("rx"), ry = y("ry")
      guard rx > 0, ry > 0 else { return nil }
      return CGPath(ellipseIn: CGRect(x: x("cx") - rx, y: y("cy") - ry, width: 2 * rx, height: 2 * ry), transform: nil)
    case "line":
      let p = CGMutablePath()
      p.move(to: CGPoint(x: x("x1"), y: y("y1")))
      p.addLine(to: CGPoint(x: x("x2"), y: y("y2")))
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
      if node.name == "polygon" { p.closeSubpath() }
      return p
    default:
      return nil
    }
  }

  /// Object bounding box in the node's own user space (geometry only, no
  /// stroke), for `objectBoundingBox` gradients, clips and masks.
  static func bounds(of node: SVGNode, icon: SVGIcon, viewport: CGSize, depth: Int = 0) -> CGRect {
    guard depth < 16 else { return .null }
    if let p = path(of: node, viewport: viewport, fontSize: 16) { return p.boundingBoxOfPath }
    if node.name == "text" {
      return SVGText.bounds(node, style: SVGStyle().inheriting(icon.properties(of: node), viewport: viewport), viewport: viewport)
    }
    if node.name == "use", let id = node.href?.trimmingCharacters(in: CharacterSet(charactersIn: "#")), let ref = icon.ids[id] {
      let x = SVGNumbers.length(node.attributes["x"], axis: .x, viewport: viewport) ?? 0
      let y = SVGNumbers.length(node.attributes["y"], axis: .y, viewport: viewport) ?? 0
      return bounds(of: ref, icon: icon, viewport: viewport, depth: depth + 1).offsetBy(dx: x, dy: y)
    }
    var box = CGRect.null
    for child in node.children where child.name != "#text" {
      var b = bounds(of: child, icon: icon, viewport: viewport, depth: depth + 1)
      if let t = icon.properties(of: child)["transform"] { b = b.applying(SVGTransform.parse(t)) }
      box = box.union(b)
    }
    return box.isNull ? .zero : box
  }
}

// MARK: - Text

enum SVGText {
  struct Run {
    let text: String
    let style: SVGStyle
    var x: CGFloat?
    var y: CGFloat?
    var dx: CGFloat = 0
    var dy: CGFloat = 0
  }

  /// Flattens `text`/`tspan` into runs, collapsing whitespace as
  /// `xml:space="default"` does.
  static func runs(_ node: SVGNode, style: SVGStyle, viewport: CGSize, icon: SVGIcon) -> [Run] {
    var out: [Run] = []
    func visit(_ n: SVGNode, _ s: SVGStyle) {
      var pending = positions(n, viewport: viewport, fontSize: s.fontSize)
      for child in n.children {
        if child.name == "#text" {
          let collapsed = child.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
          guard !collapsed.isEmpty else { continue }
          var run = Run(text: collapsed, style: s)
          run.x = pending.x
          run.y = pending.y
          run.dx = pending.dx
          run.dy = pending.dy
          pending = (nil, nil, 0, 0)
          out.append(run)
        } else if child.name == "tspan" {
          let p = icon.properties(of: child)
          if p["display"] == "none" { continue }
          visit(child, s.inheriting(p, viewport: viewport))
        }
      }
    }
    visit(node, style)
    // Trim the outer edges of the whole text.
    if !out.isEmpty {
      out[0] = Run(text: String(out[0].text.drop(while: { $0 == " " })), style: out[0].style, x: out[0].x, y: out[0].y, dx: out[0].dx, dy: out[0].dy)
      let l = out.count - 1
      var trimmed = out[l].text
      while trimmed.hasSuffix(" ") { trimmed.removeLast() }
      out[l] = Run(text: trimmed, style: out[l].style, x: out[l].x, y: out[l].y, dx: out[l].dx, dy: out[l].dy)
    }
    return out
  }

  private static func positions(_ n: SVGNode, viewport: CGSize, fontSize: CGFloat) -> (x: CGFloat?, y: CGFloat?, dx: CGFloat, dy: CGFloat) {
    let a = n.attributes
    func first(_ k: String) -> CGFloat? { a[k].flatMap { SVGNumbers.list($0).first } }
    return (first("x"), first("y"), first("dx") ?? 0, first("dy") ?? 0)
  }

  static func font(_ style: SVGStyle) -> CTFont {
    let weight: UIFont.Weight = {
      switch style.fontWeight {
      case ..<150: return .ultraLight
      case ..<250: return .thin
      case ..<350: return .light
      case ..<450: return .regular
      case ..<550: return .medium
      case ..<650: return .semibold
      case ..<750: return .bold
      case ..<850: return .heavy
      default: return .black
      }
    }()
    let size = max(1, style.fontSize)
    var font = UIFont.systemFont(ofSize: size, weight: weight)
    let generic = ["serif": "Times New Roman", "monospace": "Menlo", "cursive": "Snell Roundhand", "fantasy": "Papyrus"]
    for raw in style.fontFamily.split(separator: ",") {
      let name = raw.trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
      if ["sans-serif", "system-ui", "-apple-system", "ui-sans-serif"].contains(name) { break }
      let family = generic[name] ?? name
      if UIFont.familyNames.contains(family) {
        let d = UIFontDescriptor(fontAttributes: [.family: family])
          .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        font = UIFont(descriptor: d, size: size)
        break
      }
      if let byName = UIFont(name: name, size: size) {
        font = byName
        break
      }
    }
    if style.italic, let d = font.fontDescriptor.withSymbolicTraits(.traitItalic) { font = UIFont(descriptor: d, size: size) }
    return font as CTFont
  }

  private static func line(_ run: Run) -> CTLine {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font(run.style),
      NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: run.text, attributes: attrs))
  }

  static func bounds(_ node: SVGNode, style: SVGStyle, viewport: CGSize) -> CGRect {
    let a = node.attributes
    let x = a["x"].flatMap { SVGNumbers.list($0).first } ?? 0
    let y = a["y"].flatMap { SVGNumbers.list($0).first } ?? 0
    let text = node.children.filter { $0.name == "#text" }.map(\.text).joined()
    let l = line(Run(text: text.trimmingCharacters(in: .whitespacesAndNewlines), style: style))
    var ascent: CGFloat = 0, descent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(l, &ascent, &descent, nil))
    return CGRect(x: x, y: y - ascent, width: width, height: ascent + descent)
  }

  fileprivate static func draw(_ node: SVGNode, style: SVGStyle, viewport: CGSize, renderer: SVGRenderer) {
    let ctx = renderer.ctx
    let runs = runs(node, style: style, viewport: viewport, icon: renderer.icon)
    guard !runs.isEmpty else { return }

    // Split into chunks at absolute x positions; text-anchor applies per chunk.
    var chunks: [[Run]] = []
    for run in runs {
      if run.x != nil || chunks.isEmpty { chunks.append([run]) } else { chunks[chunks.count - 1].append(run) }
    }
    var pen = CGPoint.zero
    for chunk in chunks {
      let lines = chunk.map(line)
      let width = lines.reduce(CGFloat(0)) { $0 + CGFloat(CTLineGetTypographicBounds($1, nil, nil, nil)) } +
        chunk.reduce(CGFloat(0)) { $0 + $1.dx } - (chunk.first?.dx ?? 0)
      if let x = chunk.first?.x { pen.x = x }
      let anchor = chunk.first?.style.textAnchor ?? "start"
      pen.x -= anchor == "middle" ? width / 2 : anchor == "end" ? width : 0
      for (run, l) in zip(chunk, lines) {
        if let y = run.y { pen.y = y }
        pen.x += run.dx
        pen.y += run.dy
        drawLine(l, at: pen, style: run.style, ctx: ctx, viewport: viewport, renderer: renderer)
        pen.x += CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
      }
    }
  }

  fileprivate static func drawLine(_ l: CTLine, at p: CGPoint, style: SVGStyle, ctx: CGContext, viewport: CGSize, renderer: SVGRenderer) {
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = p
    var ascent: CGFloat = 0, descent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(l, &ascent, &descent, nil))
    let box = CGRect(x: p.x, y: p.y - ascent, width: width, height: ascent + descent)

    switch renderer.resolve(style.fill, style: style) {
    case .none:
      break
    case .color(let c):
      ctx.setFillColor(renderer.color(c, opacity: style.fillOpacity))
      ctx.setTextDrawingMode(.fill)
      CTLineDraw(l, ctx)
    case .gradient(let g):
      ctx.saveGState()
      ctx.setTextDrawingMode(.clip)
      CTLineDraw(l, ctx)
      g.draw(in: ctx, bbox: box, viewport: viewport, opacity: style.fillOpacity, renderer: renderer)
      ctx.restoreGState()
    }
    if style.strokeWidth > 0, case .color(let c) = renderer.resolve(style.stroke, style: style) {
      ctx.textPosition = p
      ctx.setStrokeColor(renderer.color(c, opacity: style.strokeOpacity))
      ctx.setLineWidth(style.strokeWidth)
      ctx.setLineJoin(style.lineJoin)
      ctx.setTextDrawingMode(.stroke)
      CTLineDraw(l, ctx)
    }
  }
}
