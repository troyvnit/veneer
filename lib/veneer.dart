/// Veneer: real native iOS 26 UI for Flutter apps.
///
/// One native overlay sits above the Flutter surface and follows Flutter
/// layout every frame, so UIKit components behave like Flutter widgets:
///   * [NativeChromeScope] — a real `UITabBarController` with the split
///     layout's trailing button ([NativeTabAction]);
///   * [NativeNavigationBar] — a real `UINavigationBar`, with native menus
///     ([NativeMenuItem]) and iOS 26's scroll edge effect;
///   * [NativeComposer] and [NativePromptComposer] — native messaging and
///     assistant-style composers that ride the keyboard;
///   * [showNativeSheet] — real UIKit sheets hosting Flutter content;
///   * [GlassShape] and [GlassGroup] — Liquid Glass positioned by Flutter
///     layout, merging within groups and honouring Flutter clips.
///   * [NativeSearchField] — a real `UISearchTextField` on glass, positioned
///     by Flutter layout.
///   * [GlassSegmentBar] — a row of icons on one glass capsule with a sliding
///     selection highlight.
///
/// Icons everywhere are [NativeIcon]s — SF Symbols, IconData, SVG or images,
/// all rendered by UIKit. On Android and iOS 15–25 every widget renders a
/// Flutter replica with the same layout.
library;

import 'src/core/veneer_bridge.dart';
import 'src/glass/glass_group.dart';

export 'src/chrome/native_chrome.dart';
export 'src/chrome/native_composer.dart';
export 'src/chrome/native_context_menu.dart';
export 'src/chrome/native_navigation_bar.dart';
export 'src/chrome/native_sheet.dart' hide veneerSheetAnchor;
export 'src/core/fallback_scope.dart' show VeneerFallbackScope, useNativeLayer;
export 'src/core/fallback_style.dart' show VeneerFallbackStyle;
export 'src/core/native_icon.dart';
export 'src/core/native_menu.dart' show NativeMenuItem;
export 'src/core/veneer_bridge.dart' show SheetRequestHandler, VeneerBridge, VeneerTransport;
export 'src/glass/glass_group.dart';
export 'src/glass/glass_segment_bar.dart';
export 'src/glass/glass_shape.dart';
export 'src/glass/native_search_field.dart';

abstract final class Veneer {
  /// Whether the native layer is available: iOS 26 or later. Elsewhere
  /// (Android, iOS 15–25) every widget renders a Flutter fallback, so one
  /// widget tree serves all platforms.
  static bool get isSupported => VeneerBridge.instance.isSupported;

  /// Render the Flutter fallbacks even on iOS 26, to preview what Android and
  /// older iOS users see. Set before the first frame.
  static bool get debugForceFallback => VeneerBridge.instance.debugForceFallback;
  static set debugForceFallback(bool value) => VeneerBridge.instance.debugForceFallback = value;

  /// Default distance within which glass shapes in the same group merge,
  /// for groups that don't set [GlassGroup.spacing].
  static Future<void> setGlassSpacing(double spacing) => VeneerBridge.instance.setSpacing(spacing);
}
