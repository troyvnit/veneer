import 'dart:io' show File;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// An icon rendered natively by UIKit — never rasterized by Flutter.
///
/// ```dart
/// NativeIcon.symbol('house.fill')                    // SF Symbol
/// NativeIcon.icon(Icons.favorite)                    // IconData: Material, Cupertino, any icon font
/// NativeIcon.icon(Symbols.home, fill: 1, weight: 600) // variable icon fonts (Material Symbols)
/// NativeIcon.svgAsset('assets/icons/star.svg')       // SVG asset
/// NativeIcon.svgFile('/path/to/downloaded.svg')      // SVG file on disk
/// NativeIcon.svg('<svg …>…</svg>')                    // SVG markup
/// NativeIcon.image('assets/photos/trail.jpg')        // PNG/JPEG asset, own colours
/// NativeIcon.imageFile('/path/to/photo.heic')        // image file on disk
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
  ///
  /// Where SF Symbols don't exist (Android, the Flutter fallbacks on older
  /// iOS), common names map to Material icons automatically; pass [fallback]
  /// for anything else.
  const factory NativeIcon.symbol(String name, {IconData? fallback}) = _SymbolIcon;

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

  /// A raster image (PNG, JPEG, HEIC…) from the app's assets, drawn in its
  /// own colours — for photos, thumbnails and avatars rather than glyphs.
  const factory NativeIcon.image(String asset, {String? package}) = _ImageAssetIcon;

  /// A raster image file on disk, e.g. a photo the user picked.
  const factory NativeIcon.imageFile(String path) = _ImageFileIcon;

  /// Wire format for the native side (`NativeIconDescriptor`).
  Map<String, Object?> encode();
}

final class _SymbolIcon extends NativeIcon {
  const _SymbolIcon(this.name, {this.fallback});
  final String name;
  final IconData? fallback;

  @override
  Map<String, Object?> encode() => {'type': 'symbol', 'name': name};

  /// The Material stand-in: explicit fallback, the mapping table, the name
  /// without `.fill`/`.circle` suffixes, then a neutral dot.
  IconData get materialIcon {
    if (fallback case final f?) return f;
    if (sfSymbolFallbacks[name] case final m?) return m;
    for (final suffix in const ['.fill', '.circle', '.square']) {
      if (name.endsWith(suffix)) {
        if (sfSymbolFallbacks[name.substring(0, name.length - suffix.length)] case final m?) return m;
      }
    }
    return Icons.circle_outlined;
  }

  @override
  bool operator ==(Object other) => other is _SymbolIcon && other.name == name && other.fallback == fallback;

  @override
  int get hashCode => Object.hash(name, fallback);
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

final class _ImageAssetIcon extends NativeIcon {
  const _ImageAssetIcon(this.asset, {this.package});
  final String asset;
  final String? package;

  @override
  Map<String, Object?> encode() => {'type': 'imageAsset', 'asset': asset, 'package': package};

  @override
  bool operator ==(Object other) => other is _ImageAssetIcon && other.asset == asset && other.package == package;

  @override
  int get hashCode => Object.hash(asset, package);
}

final class _ImageFileIcon extends NativeIcon {
  const _ImageFileIcon(this.path);
  final String path;

  @override
  Map<String, Object?> encode() => {'type': 'imageFile', 'path': path};

  @override
  bool operator ==(Object other) => other is _ImageFileIcon && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// Renders a [NativeIcon] with Flutter, for the fallback UI where the native
/// layer isn't available (Android, iOS 15–25). Sizes and colours follow the
/// ambient [IconTheme] unless given.
class NativeIconView extends StatelessWidget {
  const NativeIconView(this.icon, {super.key, this.size, this.color, this.fit = BoxFit.contain});

  final NativeIcon icon;
  final double? size;
  final Color? color;

  /// How raster images and colour SVGs fill the box (thumbnails use cover).
  final BoxFit fit;

  /// Whether the icon keeps its own colours (raster images, untinted SVGs).
  static bool keepsColors(NativeIcon icon) => switch (icon) {
    _ImageAssetIcon() || _ImageFileIcon() => true,
    _SvgAssetIcon(:final tinted) || _SvgFileIcon(:final tinted) || _SvgStringIcon(:final tinted) => !tinted,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final color = this.color ?? theme.color;
    ColorFilter? tint(bool tinted) => tinted && color != null ? ColorFilter.mode(color, BlendMode.srcIn) : null;
    return switch (icon) {
      final _SymbolIcon i => Icon(i.materialIcon, size: size, color: color),
      final _GlyphIcon i => Icon(
        i.data,
        size: size,
        color: color,
        fill: i.fill,
        weight: i.weight,
        grade: i.grade,
        opticalSize: i.opticalSize,
      ),
      final _SvgAssetIcon i => SvgPicture.asset(
        i.asset,
        package: i.package,
        width: size,
        height: size,
        fit: fit,
        colorFilter: tint(i.tinted),
      ),
      final _SvgFileIcon i => SvgPicture.file(
        File(i.path),
        width: size,
        height: size,
        fit: fit,
        colorFilter: tint(i.tinted),
      ),
      final _SvgStringIcon i => SvgPicture.string(
        i.svg,
        width: size,
        height: size,
        fit: fit,
        colorFilter: tint(i.tinted),
      ),
      final _ImageAssetIcon i => Image.asset(i.asset, package: i.package, width: size, height: size, fit: fit),
      final _ImageFileIcon i => Image.file(File(i.path), width: size, height: size, fit: fit),
    };
  }
}

/// Common SF Symbol names and their closest Material icons.
const Map<String, IconData> sfSymbolFallbacks = {
  'house': Icons.home_outlined,
  'house.fill': Icons.home,
  'magnifyingglass': Icons.search,
  'gear': Icons.settings_outlined,
  'gearshape': Icons.settings_outlined,
  'gearshape.fill': Icons.settings,
  'bell': Icons.notifications_none,
  'bell.fill': Icons.notifications,
  'person': Icons.person_outline,
  'person.fill': Icons.person,
  'person.2': Icons.people_outline,
  'plus': Icons.add,
  'plus.circle': Icons.add_circle_outline,
  'plus.circle.fill': Icons.add_circle,
  'minus': Icons.remove,
  'xmark': Icons.close,
  'checkmark': Icons.check,
  'chevron.left': Icons.arrow_back_ios_new,
  'chevron.right': Icons.arrow_forward_ios,
  'chevron.down': Icons.expand_more,
  'chevron.up': Icons.expand_less,
  'arrow.left': Icons.arrow_back,
  'arrow.right': Icons.arrow_forward,
  'arrow.up.arrow.down': Icons.swap_vert,
  'arrow.left.and.right': Icons.swap_horiz,
  'heart': Icons.favorite_border,
  'heart.fill': Icons.favorite,
  'star': Icons.star_border,
  'star.fill': Icons.star,
  'bolt': Icons.bolt_outlined,
  'bolt.fill': Icons.bolt,
  'trash': Icons.delete_outline,
  'trash.fill': Icons.delete,
  'square.and.arrow.up': Icons.ios_share,
  'paperplane': Icons.send_outlined,
  'paperplane.fill': Icons.send,
  'mic': Icons.mic_none,
  'mic.fill': Icons.mic,
  'headphones': Icons.headphones,
  'lock': Icons.lock_outline,
  'lock.fill': Icons.lock,
  'ellipsis': Icons.more_horiz,
  'bubble.left': Icons.chat_bubble_outline,
  'bubble.left.fill': Icons.chat_bubble,
  'bubble.left.and.bubble.right': Icons.forum_outlined,
  'bubble.left.and.bubble.right.fill': Icons.forum,
  'face.smiling': Icons.emoji_emotions_outlined,
  'at': Icons.alternate_email,
  'textformat': Icons.text_format,
  'photo': Icons.photo_outlined,
  'camera': Icons.photo_camera_outlined,
  'drop': Icons.water_drop_outlined,
  'drop.fill': Icons.water_drop,
  'sparkles': Icons.auto_awesome,
  'scissors': Icons.content_cut,
  'play.fill': Icons.play_arrow,
  'pause.fill': Icons.pause,
  'ruler': Icons.straighten,
  'tag': Icons.sell_outlined,
  'tag.fill': Icons.sell,
  'hand.draw': Icons.gesture,
  'square.stack.3d.up': Icons.layers_outlined,
  'square.stack.3d.up.fill': Icons.layers,
  'square.grid.2x2': Icons.grid_view,
  'circle.grid.cross': Icons.apps,
  'circle.lefthalf.filled': Icons.contrast,
  'gauge.with.dots.needle.33percent': Icons.speed,
  'calendar': Icons.calendar_today_outlined,
  'clock': Icons.schedule,
  'link': Icons.link,
  'pencil': Icons.edit_outlined,
  'folder': Icons.folder_outlined,
  'doc': Icons.description_outlined,
  'doc.fill': Icons.description,
  'waveform': Icons.graphic_eq,
  'mic.slash': Icons.mic_off_outlined,
  'mic.slash.fill': Icons.mic_off,
  'arrow.up': Icons.arrow_upward,
  'square.and.pencil': Icons.edit_square,
  'slider.horizontal.3': Icons.tune,
  'line.3.horizontal': Icons.menu,
  'photo.on.rectangle': Icons.photo_library_outlined,
  'camera.fill': Icons.photo_camera,
  'paperclip': Icons.attach_file,
  'globe': Icons.language,
  'lightbulb': Icons.lightbulb_outline,
  'square.and.arrow.down': Icons.download_outlined,
  'arrow.clockwise': Icons.refresh,
  'doc.on.doc': Icons.content_copy,
  'hand.thumbsup': Icons.thumb_up_outlined,
  'hand.thumbsdown': Icons.thumb_down_outlined,
  'speaker.wave.2': Icons.volume_up_outlined,
};
