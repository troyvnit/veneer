/// Veneer: a thin layer of real native iOS UI over Flutter.
///
/// Instead of embedding a platform view per widget, Veneer keeps one native
/// overlay above the Flutter surface and lets Flutter layout drive it:
///   * chrome ([NativeChromeScope]) — a real `UITabBarController`, with the
///     split layout's trailing button ([NativeTabAction]);
///   * Liquid Glass ([GlassShape], [GlassGroup]) — native glass positioned by
///     Flutter layout every frame, merging within groups and honouring
///     Flutter clips.
///
/// Icons everywhere are [NativeIcon]s — SF Symbols, IconData or SVG, all
/// rendered by UIKit.
library;

import 'src/core/veneer_bridge.dart';
import 'src/glass/glass_group.dart';

export 'src/chrome/native_chrome.dart';
export 'src/chrome/native_composer.dart';
export 'src/chrome/native_navigation_bar.dart';
export 'src/core/native_icon.dart';
export 'src/core/veneer_bridge.dart' show VeneerBridge, VeneerTransport;
export 'src/glass/glass_group.dart';
export 'src/glass/glass_shape.dart';

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
