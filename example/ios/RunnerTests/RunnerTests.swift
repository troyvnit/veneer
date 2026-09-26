import UIKit
import XCTest

@testable import veneer

/// Native icon rendering: the SVG parser (path grammar, arcs, transforms,
/// styles) and IconData glyphs drawn from the app's bundled icon fonts.
/// Runs hosted in the example app, so Flutter assets and the plugin are live.
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

  // MARK: Documents

  func testTransformsComposeRightToLeft() throws {
    let svg = #"<svg viewBox="0 0 24 24"><g transform="translate(10,0) scale(2)"><rect width="1" height="1"/></g></svg>"#
    let icon = try XCTUnwrap(SVGIcon(data: Data(svg.utf8)))
    XCTAssertEqual(icon.shapes.first?.path.boundingBoxOfPath, CGRect(x: 10, y: 0, width: 2, height: 2))
  }

  func testStylesInheritAndStyleAttributeWins() throws {
    let svg = #"""
      <svg viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2">
        <circle cx="12" cy="12" r="5" style="stroke-width: 3; stroke-linecap: round"/>
        <rect width="4" height="4" fill="rgb(255, 0, 0)"/>
      </svg>
      """#
    let icon = try XCTUnwrap(SVGIcon(data: Data(svg.utf8)))
    XCTAssertEqual(icon.shapes.count, 2)
    XCTAssertEqual(icon.shapes[0].style.fill, SVGIcon.Paint.none)
    XCTAssertEqual(icon.shapes[0].style.strokeWidth, 3)
    XCTAssertEqual(icon.shapes[0].style.lineCap, .round)
    guard case .color(let red) = icon.shapes[1].style.fill else { return XCTFail("rgb() fill not parsed") }
    var r: CGFloat = 0, g: CGFloat = 0
    red.getRed(&r, green: &g, blue: nil, alpha: nil)
    XCTAssertEqual(r, 1, accuracy: 0.01)
    XCTAssertEqual(g, 0, accuracy: 0.01)
  }

  func testUnsupportedElementsAreSkipped() throws {
    let svg = #"""
      <svg viewBox="0 0 10 10">
        <defs><linearGradient id="g"><stop offset="0"/></linearGradient></defs>
        <title>t</title>
        <path d="M0 0h10v10H0z"/>
      </svg>
      """#
    XCTAssertEqual(try XCTUnwrap(SVGIcon(data: Data(svg.utf8))).shapes.count, 1)
  }

  func testTemplateRenderingFillsTheShape() throws {
    let svg = #"<svg viewBox="0 0 24 24"><polygon points="12,2.5 21.5,9.4 17.9,20.5 6.1,20.5 2.5,9.4"/></svg>"#
    let image = try XCTUnwrap(SVGIcon(data: Data(svg.utf8))).image(size: 24, template: true)
    XCTAssertEqual(image.renderingMode, .alwaysTemplate)
    XCTAssertGreaterThan(alpha(of: image, at: CGPoint(x: 12, y: 13)), 0.9, "centre is filled")
    XCTAssertEqual(alpha(of: image, at: CGPoint(x: 1, y: 1)), 0, "corner is empty")
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

  func testUnknownFontFamilyFailsCleanly() throws {
    let descriptor = try XCTUnwrap(NativeIconDescriptor(["type": "glyph", "codePoint": 0xE047, "family": "Nope"]))
    XCTAssertNil(NativeIconRenderer.shared.image(for: descriptor, pointSize: 24))
  }

  // MARK: Helpers

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
