import 'package:flutter/widgets.dart';

/// An icon rendered natively by UIKit — never rasterized by Flutter.
///
/// ```dart
/// NativeIcon.symbol('house.fill')              // SF Symbol
/// NativeIcon.icon(Icons.favorite)              // IconData (Material, Cupertino, any icon font)
/// NativeIcon.svgAsset('assets/icons/star.svg') // SVG asset, drawn with CoreGraphics
/// NativeIcon.svg('<svg …>…</svg>')              // SVG markup
/// ```
///
/// IconData is drawn from the app's own copy of the icon font, so it matches
/// Flutter's `Icon` exactly. Pass `const` IconData values: release builds
/// tree-shake icon fonts down to the glyphs referenced by constants.
///
/// SVGs cover what icon sets use: paths (arcs included), basic shapes,
/// groups, transforms, fill and stroke. Gradients, masks, `use` and text are
/// skipped. By default SVGs render as template images, tinted like SF
/// Symbols; pass `tinted: false` to keep their own colours.
@immutable
sealed class NativeIcon {
  const NativeIcon();

  /// An SF Symbol by name, e.g. `'heart.fill'`.
  const factory NativeIcon.symbol(String name) = _SymbolIcon;

  /// A Flutter [IconData] from any icon font bundled with the app.
  const factory NativeIcon.icon(IconData data) = _GlyphIcon;

  /// An SVG from the app's assets (declared in pubspec `flutter: assets:`).
  const factory NativeIcon.svgAsset(String asset, {String? package, bool tinted}) = _SvgAssetIcon;

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
  const _GlyphIcon(this.data);
  final IconData data;

  /// The FontManifest family key: package fonts are `packages/<pkg>/<family>`.
  String? get _family {
    final family = data.fontFamily;
    if (family == null) return null;
    return data.fontPackage == null ? family : 'packages/${data.fontPackage}/$family';
  }

  @override
  Map<String, Object?> encode() => {'type': 'glyph', 'codePoint': data.codePoint, 'family': _family};

  @override
  bool operator ==(Object other) => other is _GlyphIcon && other.data == data;

  @override
  int get hashCode => data.hashCode;
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
