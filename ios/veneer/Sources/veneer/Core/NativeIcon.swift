import CoreText
import UIKit

/// An icon described by Dart (`NativeIcon`) and rendered by UIKit.
///
/// Nothing is rasterized by Flutter:
///   * `.symbol` — an SF Symbol, via `UIImage(systemName:)`.
///   * `.glyph`  — a Flutter `IconData`: the icon font is read from the app's
///     Flutter assets (the same subset font Flutter uses) and the glyph is
///     drawn with CoreText. Font fallbacks, variable-font axes (Material
///     Symbols fill/weight/grade/optical size) and `matchTextDirection`
///     (mirrored in right-to-left layouts, by UIKit) are honoured.
///   * `.svg…`   — parsed and drawn natively (`SVGIcon`), from an asset, a
///     file or markup.
///   * `.image…` — a PNG/JPEG/HEIC from an asset or a file, loaded by UIKit
///     and kept in its own colours (photos, thumbnails, avatars).
///
/// Glyphs and tinted SVGs come back as template images, so they tint like SF
/// Symbols: tab bar selection colours, glass vibrancy, `tintColor`. SVGs that
/// keep their colours get light and dark variants, so `currentColor`
/// follows the interface style.
@available(iOS 26.0, *)
struct NativeIconDescriptor: Hashable {
  enum Source: Hashable {
    case symbol(String)
    /// `families` are FontManifest keys, primary first then fallbacks:
    /// `MaterialIcons`, `packages/cupertino_icons/CupertinoIcons`, …
    /// `axes` are variable-font settings keyed by 4-letter tag (`FILL`, `wght`, …).
    case glyph(codePoint: Int, families: [String], axes: [String: Double])
    case svgAsset(asset: String, package: String?)
    case svgFile(path: String)
    case svg(String)
    case imageAsset(asset: String, package: String?)
    case imageFile(path: String)
  }

  var source: Source
  /// Keep SVG colours instead of rendering as a template.
  var original = false
  /// Mirror in right-to-left layouts (`IconData.matchTextDirection`).
  var mirrored = false

  init?(_ value: Any?) {
    guard let map = value as? [String: Any], let type = map["type"] as? String else { return nil }
    original = (map["tinted"] as? Bool) == false
    mirrored = (map["mirror"] as? Bool) ?? false
    switch type {
    case "symbol":
      guard let name = map["name"] as? String else { return nil }
      source = .symbol(name)
    case "glyph":
      guard let codePoint = (map["codePoint"] as? NSNumber)?.intValue else { return nil }
      let families = [map["family"] as? String].compactMap { $0 } + (map["fallback"] as? [String] ?? [])
      guard !families.isEmpty else { return nil }
      let axes = (map["axes"] as? [String: NSNumber] ?? [:]).mapValues(\.doubleValue)
      source = .glyph(codePoint: codePoint, families: families, axes: axes)
    case "svgAsset":
      guard let asset = map["asset"] as? String else { return nil }
      source = .svgAsset(asset: asset, package: map["package"] as? String)
    case "svgFile":
      guard let path = map["path"] as? String else { return nil }
      source = .svgFile(path: path)
    case "svg":
      guard let data = map["data"] as? String else { return nil }
      source = .svg(data)
    case "imageAsset":
      guard let asset = map["asset"] as? String else { return nil }
      source = .imageAsset(asset: asset, package: map["package"] as? String)
    case "imageFile":
      guard let path = map["path"] as? String else { return nil }
      source = .imageFile(path: path)
    default:
      return nil
    }
  }

  var isSymbol: Bool {
    if case .symbol = source { return true }
    return false
  }

  var isRaster: Bool {
    switch source {
    case .imageAsset, .imageFile: return true
    default: return false
    }
  }

  /// Drawn in its own colours rather than tinted: raster images and SVGs
  /// with `tinted: false`.
  var keepsColors: Bool { isRaster || (original && !isSymbol) }
}

@available(iOS 26.0, *)
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
      let image =
        pointSize.map { UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: $0)) }
        ?? UIImage(systemName: name)
      return icon.mirrored ? image?.imageFlippedForRightToLeftLayoutDirection() : image
    }
    let size = pointSize ?? 25
    let key = CacheKey(icon: icon, size: size)
    if let cached = cache[key] { return cached }

    var image: UIImage?
    switch icon.source {
    case .symbol:
      image = nil
    case let .glyph(codePoint, families, axes):
      image = families.lazy.compactMap { self.glyphImage(codePoint: codePoint, family: $0, axes: axes, size: size) }.first
    case .svgAsset, .svgFile, .svg:
      guard let svg = svg(for: icon.source) else { break }
      image = icon.original ? dynamicImage(svg, size: size) : svg.image(size: size, template: true)
    case .imageAsset, .imageFile:
      image = fullImage(for: icon).map { Self.fitted($0, in: size) }
    }
    // UIKit flips it only when the view's layout direction is right-to-left.
    if icon.mirrored { image = image?.imageFlippedForRightToLeftLayoutDirection() }
    if let image { cache[key] = image }
    return image
  }

  /// Colour-preserving SVG as a dynamic image: light and dark variants with
  /// `currentColor` resolved to `.label` in each, so it follows dark mode.
  private func dynamicImage(_ svg: SVGIcon, size: CGFloat) -> UIImage {
    let asset = UIImageAsset()
    var result: UIImage?
    for style in [UIUserInterfaceStyle.light, .dark] {
      let image = svg.image(
        size: size, template: false,
        currentColor: UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
      // The display scale must be part of the traits, or UIKit returns the
      // bitmap at scale 1 (three times too large on a 3× screen).
      let traits = UITraitCollection(traitsFrom: [
        UITraitCollection(userInterfaceStyle: style), UITraitCollection(displayScale: image.scale),
      ])
      asset.register(image, with: traits)
      if style == .light { result = image }
    }
    // The light variant carries the asset; UIKit swaps to dark as traits change.
    return result ?? UIImage()
  }

  // MARK: - Raster images

  private var rasters: [NativeIconDescriptor.Source: UIImage] = [:]

  /// A raster image at its own size (for thumbnails that fill a frame).
  func fullImage(for icon: NativeIconDescriptor) -> UIImage? {
    if let cached = rasters[icon.source] { return cached }
    let path: String?
    switch icon.source {
    case let .imageAsset(asset, package): path = assetPath?(asset, package)
    case let .imageFile(p): path = p
    default: return nil
    }
    guard let path, let image = UIImage(contentsOfFile: path)?.withRenderingMode(.alwaysOriginal) else { return nil }
    rasters[icon.source] = image
    return image
  }

  /// Aspect-fit into a `size`×`size` box, as an icon.
  private static func fitted(_ image: UIImage, in size: CGFloat) -> UIImage {
    let s = image.size
    guard s.width > 0, s.height > 0 else { return image }
    let scale = min(size / s.width, size / s.height)
    let target = CGSize(width: s.width * scale, height: s.height * scale)
    return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
      image.draw(in: CGRect(x: (size - target.width) / 2, y: (size - target.height) / 2, width: target.width, height: target.height))
    }.withRenderingMode(.alwaysOriginal)
  }

  // MARK: - IconData glyphs

  /// Draws a glyph the way Flutter's `Icon` lays it out: a `size`×`size`
  /// box, font size `size`, line height 1.0 (baseline at size·ascent/(ascent+descent)),
  /// horizontally centred on the glyph's advance.
  private func glyphImage(codePoint: Int, family: String, axes: [String: Double], size: CGFloat) -> UIImage? {
    guard let base = font(family: family), let scalar = UnicodeScalar(codePoint) else { return nil }
    let font = CTFontCreateWithGraphicsFont(Self.applying(axes, to: base), size, nil, nil)
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

  /// Variable-font instance: axis tags (`FILL`, `wght`, `GRAD`, `opsz`) are
  /// mapped to the font's axis names, which `CGFont` variations are keyed by.
  /// Unknown axes and non-variable fonts are left untouched.
  static func applying(_ axes: [String: Double], to font: CGFont) -> CGFont {
    guard !axes.isEmpty, let axisInfo = CTFontCopyVariationAxes(CTFontCreateWithGraphicsFont(font, 12, nil, nil)) as? [[String: Any]]
    else { return font }
    var variations: [String: Double] = [:]
    for axis in axisInfo {
      guard let id = (axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.uint32Value,
        let name = axis[kCTFontVariationAxisNameKey as String] as? String
      else { continue }
      let tag = String(bytes: [24, 16, 8, 0].map { UInt8((id >> $0) & 0xFF) }, encoding: .ascii) ?? ""
      guard let value = axes[tag] else { continue }
      let lo = (axis[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber)?.doubleValue ?? value
      let hi = (axis[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber)?.doubleValue ?? value
      variations[name] = min(max(value, lo), hi)
    }
    guard !variations.isEmpty else { return font }
    return font.copy(withVariations: variations as CFDictionary) ?? font
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

  // MARK: - Text fonts

  private var textFonts: [String: String] = [:]
  private var weightedManifest: [String: [(asset: String, weight: Int)]]?

  /// A `UIFont` from the app's Flutter fonts: the FontManifest [family]'s
  /// face closest to [weight], registered with Core Text on first use. Falls
  /// back to the system font.
  func textFont(family: String?, size: CGFloat, weight: Int?) -> UIFont {
    let systemWeight: UIFont.Weight = switch weight ?? 400 {
    case ..<150: .ultraLight
    case ..<250: .thin
    case ..<350: .light
    case ..<450: .regular
    case ..<550: .medium
    case ..<650: .semibold
    case ..<750: .bold
    case ..<850: .heavy
    default: .black
    }
    guard let family, let faces = weightedFaces()[family], !faces.isEmpty else {
      return .systemFont(ofSize: size, weight: systemWeight)
    }
    let target = weight ?? 400
    let face = faces.min { abs($0.weight - target) < abs($1.weight - target) }!
    if let name = textFonts[face.asset] ?? registerFont(asset: face.asset), let font = UIFont(name: name, size: size) {
      return font
    }
    return .systemFont(ofSize: size, weight: systemWeight)
  }

  private func registerFont(asset: String) -> String? {
    guard let path = assetPath?(asset, nil),
      let provider = CGDataProvider(url: URL(fileURLWithPath: path) as CFURL),
      let font = CGFont(provider), let name = font.postScriptName as String?
    else { return nil }
    var error: Unmanaged<CFError>?
    // Already registered (e.g. by another engine) is fine.
    _ = CTFontManagerRegisterGraphicsFont(font, &error)
    textFonts[asset] = name
    return name
  }

  private func weightedFaces() -> [String: [(asset: String, weight: Int)]] {
    if let weightedManifest { return weightedManifest }
    var result: [String: [(asset: String, weight: Int)]] = [:]
    if let path = assetPath?("FontManifest.json", nil),
      let data = FileManager.default.contents(atPath: path),
      let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    {
      for entry in entries {
        guard let family = entry["family"] as? String, let fonts = entry["fonts"] as? [[String: Any]] else { continue }
        result[family] = fonts.compactMap { f in
          (f["asset"] as? String).map { ($0, (f["weight"] as? NSNumber)?.intValue ?? 400) }
        }
      }
    }
    weightedManifest = result
    return result
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
    case let .svgFile(path):
      data = FileManager.default.contents(atPath: path)
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
