import CoreText
import UIKit

/// An icon described by Dart (`NativeIcon`) and rendered by UIKit.
///
/// Nothing is rasterized by Flutter:
///   * `.symbol` — an SF Symbol, via `UIImage(systemName:)`.
///   * `.glyph`  — a Flutter `IconData`: the icon font is read from the app's
///     Flutter assets (the same subset font Flutter uses) and the glyph is
///     drawn with CoreText.
///   * `.svg`    — parsed and drawn with CoreGraphics (`SVGIcon`).
///
/// Glyphs and tinted SVGs come back as template images, so they tint like SF
/// Symbols: tab bar selection colours, glass vibrancy, `tintColor`.
struct NativeIconDescriptor: Hashable {
  enum Source: Hashable {
    case symbol(String)
    /// `family` is the FontManifest key: `MaterialIcons`,
    /// `packages/cupertino_icons/CupertinoIcons`, …
    case glyph(codePoint: Int, family: String)
    case svgAsset(asset: String, package: String?)
    case svg(String)
  }

  var source: Source
  /// Keep SVG colours instead of rendering as a template.
  var original = false

  init?(_ value: Any?) {
    guard let map = value as? [String: Any], let type = map["type"] as? String else { return nil }
    original = (map["tinted"] as? Bool) == false
    switch type {
    case "symbol":
      guard let name = map["name"] as? String else { return nil }
      source = .symbol(name)
    case "glyph":
      guard let codePoint = (map["codePoint"] as? NSNumber)?.intValue, let family = map["family"] as? String else {
        return nil
      }
      source = .glyph(codePoint: codePoint, family: family)
    case "svgAsset":
      guard let asset = map["asset"] as? String else { return nil }
      source = .svgAsset(asset: asset, package: map["package"] as? String)
    case "svg":
      guard let data = map["data"] as? String else { return nil }
      source = .svg(data)
    default:
      return nil
    }
  }

  var isSymbol: Bool {
    if case .symbol = source { return true }
    return false
  }
}

final class NativeIconRenderer {
  static let shared = NativeIconRenderer()

  /// Resolves a Flutter asset key (optionally from a package) to a file path
  /// in the app bundle. Set by the plugin from its registrar.
  var assetPath: ((String, String?) -> String?)?

  private struct CacheKey: Hashable {
    let icon: NativeIconDescriptor
    let size: CGFloat
  }

  private var cache: [CacheKey: UIImage] = [:]
  private var fonts: [String: CGFont] = [:]
  private var fontManifest: [String: [String]]?
  private var svgs: [NativeIconDescriptor.Source: SVGIcon] = [:]

  /// - Parameter pointSize: the image's side length for glyphs and SVGs.
  ///   `nil` leaves SF Symbols unconfigured, so a host like `UITabBar`
  ///   applies its own system symbol metrics.
  func image(for icon: NativeIconDescriptor, pointSize: CGFloat?) -> UIImage? {
    if case .symbol(let name) = icon.source {
      guard let pointSize else { return UIImage(systemName: name) }
      return UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize))
    }
    let size = pointSize ?? 25
    let key = CacheKey(icon: icon, size: size)
    if let cached = cache[key] { return cached }

    let image: UIImage?
    switch icon.source {
    case .symbol:
      image = nil
    case let .glyph(codePoint, family):
      image = glyphImage(codePoint: codePoint, family: family, size: size)
    case .svgAsset, .svg:
      image = svg(for: icon.source)?.image(size: size, template: !icon.original)
    }
    if let image { cache[key] = image }
    return image
  }

  // MARK: - IconData glyphs

  /// Draws a glyph the way Flutter's `Icon` lays it out: a `size`×`size`
  /// box, font size `size`, line height 1.0 (baseline at size·ascent/(ascent+descent)),
  /// horizontally centred on the glyph's advance.
  private func glyphImage(codePoint: Int, family: String, size: CGFloat) -> UIImage? {
    guard let cgFont = font(family: family), let scalar = UnicodeScalar(codePoint) else { return nil }
    let font = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    var chars = Array(String(Character(scalar)).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count), glyphs[0] != 0,
      let path = CTFontCreatePathForGlyph(font, glyphs[0], nil)
    else { return nil }

    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advance, 1)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let baseline = ascent + descent > 0 ? size * ascent / (ascent + descent) : size

    let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
      let cg = ctx.cgContext
      cg.translateBy(x: (size - advance.width) / 2, y: baseline)
      cg.scaleBy(x: 1, y: -1)
      cg.addPath(path)
      cg.setFillColor(UIColor.black.cgColor)
      cg.fillPath()
    }
    return image.withRenderingMode(.alwaysTemplate)
  }

  private func font(family: String) -> CGFont? {
    if let cached = fonts[family] { return cached }
    guard let assets = manifest()[family] else { return nil }
    for asset in assets {
      guard let path = assetPath?(asset, nil),
        let provider = CGDataProvider(url: URL(fileURLWithPath: path) as CFURL),
        let font = CGFont(provider)
      else { continue }
      fonts[family] = font
      return font
    }
    return nil
  }

  /// FontManifest.json: `[{"family": "...", "fonts": [{"asset": "..."}]}]`.
  private func manifest() -> [String: [String]] {
    if let fontManifest { return fontManifest }
    var result: [String: [String]] = [:]
    if let path = assetPath?("FontManifest.json", nil),
      let data = FileManager.default.contents(atPath: path),
      let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    {
      for entry in entries {
        guard let family = entry["family"] as? String, let fonts = entry["fonts"] as? [[String: Any]] else { continue }
        result[family] = fonts.compactMap { $0["asset"] as? String }
      }
    }
    fontManifest = result
    return result
  }

  // MARK: - SVG

  private func svg(for source: NativeIconDescriptor.Source) -> SVGIcon? {
    if let cached = svgs[source] { return cached }
    let data: Data?
    switch source {
    case let .svgAsset(asset, package):
      data = assetPath?(asset, package).flatMap { FileManager.default.contents(atPath: $0) }
    case let .svg(string):
      data = string.data(using: .utf8)
    default:
      data = nil
    }
    guard let data, let icon = SVGIcon(data: data) else { return nil }
    svgs[source] = icon
    return icon
  }
}
