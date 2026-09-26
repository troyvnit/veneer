import UIKit
import XCTest

@testable import veneer

/// Native icon rendering: the SVG parser (path grammar, arcs, transforms,
/// styles) and IconData glyphs drawn from the app's bundled icon fonts.
/// Runs hosted in the example app, so Flutter assets and the plugin are live.
@available(iOS 26.0, *)
final class NativeIconTests: XCTestCase {

  // MARK: Path grammar

  func testAbsoluteAndShorthandLines() {
    let path = SVGPathParser.parse("M0 0h10v10H0z")
    XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 10, height: 10))
  }

  func testCompactNumbersAndRelativeCommands() {
    // "1.5.5" is two numbers, "-1-2" is two numbers.
    let path = SVGPathParser.parse("M1.5.5l-1-2")
    XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 0.5, y: -1.5, width: 1, height: 2))
  }

  func testImplicitLineToAfterMoveTo() {
    let path = SVGPathParser.parse("M0 0 10 0 10 10")
    XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 10, height: 10))
  }

  func testArcsFormACircle() {
    let path = SVGPathParser.parse("M12 2.5a9.5 9.5 0 1 0 0 19a9.5 9.5 0 1 0 0-19z")
    assertRect(path.boundingBoxOfPath, CGRect(x: 2.5, y: 2.5, width: 19, height: 19), accuracy: 0.05)
  }

  func testArcFlagsWithoutSeparators() {
    // "a5 5 0 105 5" → rx 5, ry 5, rot 0, large 1, sweep 0, end (5, 5).
    let path = SVGPathParser.parse("M0 0a5 5 0 105 5")
    XCTAssertEqual(path.currentPoint.x, 5, accuracy: 0.001)
    XCTAssertEqual(path.currentPoint.y, 5, accuracy: 0.001)
  }

  func testSmoothCurvesReflectControlPoints() {
    let path = SVGPathParser.parse("M0 0C0 10 10 10 10 0S20-10 20 0")
    XCTAssertEqual(path.currentPoint, CGPoint(x: 20, y: 0))
    XCTAssertLessThan(path.boundingBoxOfPath.minY, -5, "reflected control point should pull the curve up")
  }

  func testGarbageDoesNotHang() {
    _ = SVGPathParser.parse("M0 0z 1 2 3 x y")
    _ = SVGPathParser.parse("L L L")
    _ = SVGPathParser.parse("")
  }

  // MARK: Documents (rendered and sampled)

  func testTransformsComposeRightToLeft() {
    let px = render(#"<svg viewBox="0 0 24 24"><g transform="translate(10,0) scale(2)"><rect width="1" height="1"/></g></svg>"#)
    XCTAssertGreaterThan(px.alpha(11, 1), 0.9)
    XCTAssertEqual(px.alpha(9, 1), 0)
  }

  func testRootStylesInheritAndStyleAttributeWins() {
    let px = render(#"""
      <svg viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1">
        <circle cx="12" cy="12" r="8" style="stroke-width: 4"/>
      </svg>
      """#)
    XCTAssertGreaterThan(px.alpha(12, 4), 0.9, "thick ring")
    XCTAssertEqual(px.alpha(12, 12), 0, "fill=none inherited from the root")
  }

  func testColourSyntaxes() {
    let px = render(#"""
      <svg viewBox="0 0 30 10">
        <rect x="0" width="10" height="10" fill="hsl(120, 100%, 50%)"/>
        <rect x="10" width="10" height="10" fill="rebeccapurple"/>
        <rect x="20" width="10" height="10" fill="rgb(100% 0% 0% / 50%)"/>
      </svg>
      """#, size: 30)  // 30×10 viewBox, letterboxed to y 10…20
    px.assertColor(5, 15, r: 0, g: 1, b: 0)
    px.assertColor(15, 15, r: 0x66 / 255.0, g: 0x33 / 255.0, b: 0x99 / 255.0)
    px.assertColor(25, 15, r: 1, g: 0, b: 0)
    XCTAssertEqual(px.alpha(25, 15), 0.5, accuracy: 0.02)
  }

  func testStyleSheetSpecificityAndDescendants() {
    let px = render(#"""
      <svg viewBox="0 0 40 10">
        <style>
          /* comment */ rect { fill: green } .a { fill: red } #b { fill: blue }
          g .c { fill: #ff0 }
          @media (min-width: 1px) { .d { fill: black } }
        </style>
        <rect x="0" width="10" height="10" class="a"/>
        <rect x="10" width="10" height="10" class="a" id="b"/>
        <g><rect x="20" width="10" height="10" class="c"/></g>
        <rect x="30" width="10" height="10" class="d" fill="white"/>
      </svg>
      """#, size: 40)  // 40×10 viewBox, letterboxed to y 15…25
    px.assertColor(5, 20, r: 1, g: 0, b: 0)
    px.assertColor(15, 20, r: 0, g: 0, b: 1)
    px.assertColor(25, 20, r: 1, g: 1, b: 0)
    px.assertColor(35, 20, r: 0, g: 0, b: 0, "stylesheet beats presentation attribute")
  }

  func testUseDefsAndSymbol() {
    let px = render(#"""
      <svg viewBox="0 0 24 24" xmlns:xlink="http://www.w3.org/1999/xlink">
        <defs><rect id="r" width="4" height="4"/></defs>
        <symbol id="s" viewBox="0 0 2 2"><rect width="1" height="1"/></symbol>
        <use xlink:href="#r" x="10" y="0"/>
        <use href="#s" x="0" y="12" width="12" height="12"/>
      </svg>
      """#)
    XCTAssertEqual(px.alpha(2, 2), 0, "defs don't render directly")
    XCTAssertGreaterThan(px.alpha(12, 2), 0.9)
    XCTAssertGreaterThan(px.alpha(3, 15), 0.9, "symbol scaled: top-left quarter of 12×12")
    XCTAssertEqual(px.alpha(9, 21), 0)
  }

  func testLinearAndRadialGradients() {
    let linear = render(#"""
      <svg viewBox="0 0 24 24">
        <linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>
        <rect width="24" height="24" fill="url(#g)"/>
      </svg>
      """#)
    XCTAssertGreaterThan(linear.rgb(1, 12).r, 0.8)
    XCTAssertGreaterThan(linear.rgb(23, 12).b, 0.8)

    let radial = render(#"""
      <svg viewBox="0 0 24 24">
        <radialGradient id="base"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></radialGradient>
        <radialGradient id="g" href="#base"/>
        <rect width="24" height="24" fill="url(#g)"/>
      </svg>
      """#)
    XCTAssertGreaterThan(radial.rgb(12, 12).r, 0.9, "stops inherited through href")
    XCTAssertLessThan(radial.rgb(12, 1).r, 0.2)
  }

  func testClipPathAndLuminanceMask() {
    let clip = render(#"""
      <svg viewBox="0 0 24 24">
        <clipPath id="c"><circle cx="12" cy="12" r="6"/></clipPath>
        <rect width="24" height="24" clip-path="url(#c)"/>
      </svg>
      """#)
    XCTAssertGreaterThan(clip.alpha(12, 12), 0.9)
    XCTAssertEqual(clip.alpha(2, 2), 0)

    let mask = render(#"""
      <svg viewBox="0 0 24 24">
        <mask id="m"><rect width="24" height="24" fill="black"/><rect width="12" height="24" fill="white"/></mask>
        <rect width="24" height="24" mask="url(#m)"/>
      </svg>
      """#)
    XCTAssertGreaterThan(mask.alpha(6, 12), 0.9, "white mask shows")
    XCTAssertEqual(mask.alpha(18, 12), 0, accuracy: 0.02, "black mask hides")
  }

  func testGroupOpacityCompositesAsOneLayer() {
    let px = render(#"""
      <svg viewBox="0 0 24 24"><g opacity="0.5">
        <rect width="16" height="16"/><rect x="8" y="8" width="16" height="16"/>
      </g></svg>
      """#)
    // Overlap stays 0.5, not 0.75: the group is flattened before fading.
    XCTAssertEqual(px.alpha(12, 12), 0.5, accuracy: 0.03)
  }

  func testDashesDisplayAndVisibility() {
    let px = render(#"""
      <svg viewBox="0 0 24 24">
        <line x1="0" y1="2" x2="24" y2="2" stroke="#000" stroke-width="2" stroke-dasharray="4 4"/>
        <rect y="10" width="24" height="4" display="none"/>
        <g visibility="hidden"><rect y="16" width="24" height="4"/><rect y="20" width="4" height="4" visibility="visible"/></g>
      </svg>
      """#)
    XCTAssertGreaterThan(px.alpha(2, 2), 0.9)
    XCTAssertEqual(px.alpha(6, 2), 0)
    XCTAssertEqual(px.alpha(12, 12), 0)
    XCTAssertEqual(px.alpha(12, 18), 0)
    XCTAssertGreaterThan(px.alpha(2, 22), 0.9, "visibility can be re-enabled on a child")
  }

  func testPreserveAspectRatioAndNestedViewports() {
    let meet = render(#"<svg viewBox="0 0 48 24"><rect width="48" height="24"/></svg>"#)
    XCTAssertEqual(meet.alpha(12, 2), 0, "meet letterboxes a wide viewBox")
    XCTAssertGreaterThan(meet.alpha(12, 12), 0.9)
    let slice = render(#"<svg viewBox="0 0 48 24" preserveAspectRatio="xMidYMid slice"><rect width="48" height="24"/></svg>"#)
    XCTAssertGreaterThan(slice.alpha(12, 2), 0.9, "slice fills")
    let nested = render(#"<svg viewBox="0 0 24 24"><svg width="12" height="12"><rect width="24" height="24"/></svg></svg>"#)
    XCTAssertGreaterThan(nested.alpha(6, 6), 0.9)
    XCTAssertEqual(nested.alpha(18, 18), 0, "nested viewport clips")
  }

  func testTextAndEmbeddedImages() throws {
    let text = render(#"<svg viewBox="0 0 24 24"><text x="12" y="20" font-size="20" font-weight="bold" text-anchor="middle">M</text></svg>"#)
    let inked = (0..<24).flatMap { x in (0..<24).map { y in text.alpha(CGFloat(x), CGFloat(y)) } }.filter { $0 > 0.5 }.count
    XCTAssertGreaterThan(inked, 40, "glyph drawn")
    XCTAssertEqual(text.alpha(1, 12), 0, "anchored to the middle")

    let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { ctx in
      UIColor.red.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
    }
    let image = render(#"<svg viewBox="0 0 24 24"><image width="24" height="24" href="data:image/png;base64,\#(png.base64EncodedString())"/></svg>"#)
    image.assertColor(12, 4, r: 1, g: 0, b: 0, "top half of the PNG, upright")
    XCTAssertEqual(image.alpha(12, 20), 0)
  }

  func testPatternFallsBackToItsColour() {
    let px = render(#"<svg viewBox="0 0 24 24"><pattern id="p"/><rect width="24" height="24" fill="url(#p) #00f"/></svg>"#)
    px.assertColor(12, 12, r: 0, g: 0, b: 1)
  }

  func testTemplateRenderingKeepsOnlyCoverage() throws {
    let svg = #"<svg viewBox="0 0 24 24"><polygon points="12,2.5 21.5,9.4 17.9,20.5 6.1,20.5 2.5,9.4" fill="red"/></svg>"#
    let image = try XCTUnwrap(SVGIcon(data: Data(svg.utf8))).image(size: 24, template: true)
    XCTAssertEqual(image.renderingMode, .alwaysTemplate)
    let px = Pixels(image)
    XCTAssertGreaterThan(px.alpha(12, 13), 0.9)
    XCTAssertEqual(px.alpha(1, 1), 0)
  }

  func testUntintedSVGFollowsDarkMode() throws {
    let svg = #"<svg viewBox="0 0 24 24"><rect width="24" height="24" fill="currentColor"/></svg>"#
    let descriptor = try XCTUnwrap(NativeIconDescriptor(["type": "svg", "data": svg, "tinted": false]))
    let image = try XCTUnwrap(NativeIconRenderer.shared.image(for: descriptor, pointSize: 24))
    let light = try XCTUnwrap(image.imageAsset?.image(with: UITraitCollection(userInterfaceStyle: .light)))
    let dark = try XCTUnwrap(image.imageAsset?.image(with: UITraitCollection(userInterfaceStyle: .dark)))
    XCTAssertLessThan(Pixels(light).rgb(12, 12).r, 0.2, "label is dark in light mode")
    XCTAssertGreaterThan(Pixels(dark).rgb(12, 12).r, 0.8, "and light in dark mode")
  }

  func testSVGFileSource() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("veneer-test.svg")
    try #"<svg viewBox="0 0 24 24"><rect width="24" height="24"/></svg>"#.write(to: url, atomically: true, encoding: .utf8)
    let descriptor = try XCTUnwrap(NativeIconDescriptor(["type": "svgFile", "path": url.path]))
    XCTAssertNotNil(NativeIconRenderer.shared.image(for: descriptor, pointSize: 24))
  }

  // MARK: IconData

  func testMaterialIconDataRendersFromTheBundledFont() throws {
    // Icons.add (U+E047) from the app's own MaterialIcons font.
    let descriptor = try XCTUnwrap(NativeIconDescriptor(["type": "glyph", "codePoint": 0xE047, "family": "MaterialIcons"]))
    let image = try XCTUnwrap(NativeIconRenderer.shared.image(for: descriptor, pointSize: 24))
    XCTAssertEqual(image.size, CGSize(width: 24, height: 24))
    XCTAssertEqual(image.renderingMode, .alwaysTemplate)
    XCTAssertGreaterThan(alpha(of: image, at: CGPoint(x: 12, y: 12)), 0.9, "the plus crosses the centre")
    XCTAssertEqual(alpha(of: image, at: CGPoint(x: 3, y: 3)), 0)
  }

  func testPackageIconFontResolves() throws {
    // CupertinoIcons.gauge from packages/cupertino_icons.
    let descriptor = try XCTUnwrap(
      NativeIconDescriptor(["type": "glyph", "codePoint": 0xF686, "family": "packages/cupertino_icons/CupertinoIcons"]))
    XCTAssertNotNil(NativeIconRenderer.shared.image(for: descriptor, pointSize: 25))
  }

  func testFontFamilyFallback() throws {
    let descriptor = try XCTUnwrap(
      NativeIconDescriptor(["type": "glyph", "codePoint": 0xE047, "family": "Nope", "fallback": ["MaterialIcons"]]))
    XCTAssertNotNil(NativeIconRenderer.shared.image(for: descriptor, pointSize: 24))
  }

  func testMatchTextDirectionMirrorsInRightToLeft() throws {
    let descriptor = try XCTUnwrap(
      NativeIconDescriptor(["type": "glyph", "codePoint": 0xE047, "family": "MaterialIcons", "mirror": true]))
    XCTAssertTrue(try XCTUnwrap(NativeIconRenderer.shared.image(for: descriptor, pointSize: 24)).flipsForRightToLeftLayoutDirection)
  }

  func testVariableFontAxesChangeTheGlyph() throws {
    // The system font is variable (wght); the same mechanism drives Material Symbols' FILL/wght/GRAD/opsz.
    let base = CTFontCopyGraphicsFont(UIFont.systemFont(ofSize: 40) as CTFont, nil)
    func ink(_ weight: Double) -> Int {
      let font = CTFontCreateWithGraphicsFont(NativeIconRenderer.applying(["wght": weight], to: base), 40, nil, nil)
      var ch: [UniChar] = [0x49]  // "I"
      var glyph: CGGlyph = 0
      CTFontGetGlyphsForCharacters(font, &ch, &glyph, 1)
      let path = CTFontCreatePathForGlyph(font, glyph, nil)!
      return Int(path.boundingBoxOfPath.width * 100)
    }
    XCTAssertGreaterThan(ink(900), ink(100), "heavier weight, wider stem")
  }

  func testUnknownFontFamilyFailsCleanly() throws {
    let descriptor = try XCTUnwrap(NativeIconDescriptor(["type": "glyph", "codePoint": 0xE047, "family": "Nope"]))
    XCTAssertNil(NativeIconRenderer.shared.image(for: descriptor, pointSize: 24))
  }

  // MARK: Helpers

  private func render(_ svg: String, size: CGFloat = 24, file: StaticString = #filePath, line: UInt = #line) -> Pixels {
    guard let icon = SVGIcon(data: Data(svg.utf8)) else {
      XCTFail("SVG failed to parse", file: file, line: line)
      return Pixels(UIImage())
    }
    return Pixels(icon.image(size: size, template: false))
  }

  private func alpha(of image: UIImage, at point: CGPoint) -> CGFloat {
    let cg = image.cgImage!
    let scale = image.scale
    var pixel = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(
      data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: -point.x * scale, y: -(CGFloat(cg.height) - point.y * scale))
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    return CGFloat(pixel[3]) / 255
  }

  private func assertRect(_ a: CGRect, _ b: CGRect, accuracy: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.minX, b.minX, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(a.minY, b.minY, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(a.width, b.width, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(a.height, b.height, accuracy: accuracy, file: file, line: line)
  }
}

/// Reads un-premultiplied RGBA at points of a rendered image.
struct Pixels {
  let image: UIImage
  private let data: [UInt8]
  private let width: Int
  private let height: Int
  private let scale: CGFloat

  init(_ image: UIImage) {
    self.image = image
    scale = image.scale
    guard let cg = image.cgImage else {
      data = []
      width = 0
      height = 0
      return
    }
    width = cg.width
    height = cg.height
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    let ctx = CGContext(
      data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    data = buffer
  }

  private func index(_ x: CGFloat, _ y: CGFloat) -> Int? {
    let px = Int(x * scale + scale / 2), py = Int(y * scale + scale / 2)
    guard px >= 0, py >= 0, px < width, py < height else { return nil }
    return (py * width + px) * 4  // CGContext memory is top row first
  }

  func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
    index(x, y).map { CGFloat(data[$0 + 3]) / 255 } ?? 0
  }

  func rgb(_ x: CGFloat, _ y: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    guard let i = index(x, y), data[i + 3] > 0 else { return (0, 0, 0) }
    let a = CGFloat(data[i + 3])
    return (CGFloat(data[i]) / a, CGFloat(data[i + 1]) / a, CGFloat(data[i + 2]) / a)
  }

  func assertColor(
    _ x: CGFloat, _ y: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat, _ message: String = "",
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let c = rgb(x, y)
    XCTAssertEqual(c.r, r, accuracy: 0.06, "red \(message)", file: file, line: line)
    XCTAssertEqual(c.g, g, accuracy: 0.06, "green \(message)", file: file, line: line)
    XCTAssertEqual(c.b, b, accuracy: 0.06, "blue \(message)", file: file, line: line)
  }
}
