import 'package:flutter/widgets.dart';

/// An icon rendered natively by UIKit — never rasterized by Flutter.
///
/// ```dart
/// NativeIcon.symbol('house.fill')                    // SF Symbol
/// NativeIcon.icon(Icons.favorite)                    // IconData: Material, Cupertino, any icon font
/// NativeIcon.icon(Symbols.home, fill: 1, weight: 600) // variable icon fonts (Material Symbols)
/// NativeIcon.svgAsset('assets/icons/star.svg')       // SVG asset
/// NativeIcon.svgFile('/path/to/downloaded.svg')      // SVG file on disk
/// NativeIcon.svg('<svg …>…</svg>')                    // SVG markup
/// ```
///
/// **IconData** is drawn from the app's own copy of the icon font, laid out
/// like Flutter's `Icon`, with `fontFamilyFallback` and `matchTextDirection`
/// honoured (mirrored by UIKit in right-to-left layouts). Pass `const`
/// IconData: release builds tree-shake icon fonts down to glyphs referenced
/// by constants, as for `Icon`; build with `--no-tree-shake-icons` otherwise.
///
/// **SVG** is rendered natively with CSS styling, `use`/`defs`/`symbol`,
/// gradients, clip paths, masks, group opacity, dashes, text, embedded
/// images, nested viewports and `preserveAspectRatio`. Filters, patterns,
/// markers and animation aren't. By default SVGs render as template images,
/// tinted like SF Symbols; pass `tinted: false` to keep their own colours
/// (`currentColor` then follows light/dark mode).
@immutable
sealed class NativeIcon {
  const NativeIcon();

  /// An SF Symbol by name, e.g. `'heart.fill'`.
  const factory NativeIcon.symbol(String name) = _SymbolIcon;

  /// A Flutter [IconData] from any icon font bundled with the app.
  ///
  /// [fill], [weight], [grade] and [opticalSize] set the axes of variable icon
  /// fonts such as Material Symbols, like the same parameters on `Icon`;
  /// they're ignored for fonts without those axes.
  const factory NativeIcon.icon(IconData data, {double? fill, double? weight, double? grade, double? opticalSize}) =
      _GlyphIcon;

  /// An SVG from the app's assets (declared in pubspec `flutter: assets:`).
  const factory NativeIcon.svgAsset(String asset, {String? package, bool tinted}) = _SvgAssetIcon;

  /// An SVG file on disk, e.g. one downloaded at runtime.
  const factory NativeIcon.svgFile(String path, {bool tinted}) = _SvgFileIcon;

  /// SVG markup.
  const factory NativeIcon.svg(String svg, {bool tinted}) = _SvgStringIcon;

  /// Wire format for the native side (`NativeIconDescriptor`).
  Map<String, Object?> encode();
}

final class _SymbolIcon extends NativeIcon {
  const _SymbolIcon(this.name);
  final String name;

  @override
  Map<String, Object?> encode() => {'type': 'symbol', 'name': name};

  @override
  bool operator ==(Object other) => other is _SymbolIcon && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

final class _GlyphIcon extends NativeIcon {
  const _GlyphIcon(this.data, {this.fill, this.weight, this.grade, this.opticalSize});
  final IconData data;
  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;

  /// FontManifest family key: package fonts are `packages/<pkg>/<family>`
  /// (fallbacks too, as `TextStyle` resolves them).
  String _key(String family) => data.fontPackage == null ? family : 'packages/${data.fontPackage}/$family';

  @override
  Map<String, Object?> encode() => {
    'type': 'glyph',
    'codePoint': data.codePoint,
    'family': data.fontFamily == null ? null : _key(data.fontFamily!),
    'fallback': [for (final f in data.fontFamilyFallback ?? const <String>[]) _key(f)],
    'mirror': data.matchTextDirection,
    'axes': {'FILL': ?fill, 'wght': ?weight, 'GRAD': ?grade, 'opsz': ?opticalSize},
  };

  @override
  bool operator ==(Object other) =>
      other is _GlyphIcon &&
      other.data == data &&
      other.fill == fill &&
      other.weight == weight &&
      other.grade == grade &&
      other.opticalSize == opticalSize;

  @override
  int get hashCode => Object.hash(data, fill, weight, grade, opticalSize);
}

final class _SvgAssetIcon extends NativeIcon {
  const _SvgAssetIcon(this.asset, {this.package, this.tinted = true});
  final String asset;
  final String? package;
  final bool tinted;

  @override
  Map<String, Object?> encode() => {'type': 'svgAsset', 'asset': asset, 'package': package, 'tinted': tinted};

  @override
  bool operator ==(Object other) =>
      other is _SvgAssetIcon && other.asset == asset && other.package == package && other.tinted == tinted;

  @override
  int get hashCode => Object.hash(asset, package, tinted);
}

final class _SvgFileIcon extends NativeIcon {
  const _SvgFileIcon(this.path, {this.tinted = true});
  final String path;
  final bool tinted;

  @override
  Map<String, Object?> encode() => {'type': 'svgFile', 'path': path, 'tinted': tinted};

  @override
  bool operator ==(Object other) => other is _SvgFileIcon && other.path == path && other.tinted == tinted;

  @override
  int get hashCode => Object.hash(path, tinted);
}

final class _SvgStringIcon extends NativeIcon {
  const _SvgStringIcon(this.svg, {this.tinted = true});
  final String svg;
  final bool tinted;

  @override
  Map<String, Object?> encode() => {'type': 'svg', 'data': svg, 'tinted': tinted};

  @override
  bool operator ==(Object other) => other is _SvgStringIcon && other.svg == svg && other.tinted == tinted;

  @override
  int get hashCode => Object.hash(svg, tinted);
}
