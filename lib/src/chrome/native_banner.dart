import 'package:flutter/widgets.dart';

import '../core/native_icon.dart';
import '../core/veneer_bridge.dart';

/// How a [showNativeBanner] looks. Every size is in points; colours are
/// resolved by the caller (pass the ones for the current brightness and set
/// [dark] to match, so the glass follows).
@immutable
class NativeBannerStyle {
  const NativeBannerStyle({
    this.dark = false,
    this.titleStyle,
    this.subtitleStyle,
    this.bodyStyle,
    this.trailingStyle,
    this.tint,
    this.borderColor,
    this.borderWidth = 1,
    this.shadowColor,
    this.shadowBlur = 16,
    this.shadowOffsetY = 8,
    this.shadowSpread = -4,
    this.cornerRadius = 24,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 0),
    this.horizontalPadding = 16,
    this.verticalPadding = 16,
    this.iconGap = 12,
    this.trailingGap = 12,
    this.subtitleGap = 8,
    this.iconBackground,
    this.iconBoxSize = 40,
    this.iconSize = 24,
    this.badgeColor,
    this.badgeBackground,
    this.badgeShadowColor,
    this.badgeSize = 16,
    this.badgePadding = 2,
    this.badgeOffset = -4,
  });

  /// Renders the glass in its dark appearance.
  final bool dark;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final TextStyle? bodyStyle;
  final TextStyle? trailingStyle;

  /// Tints the Liquid Glass behind the content.
  final Color? tint;
  final Color? borderColor;
  final double borderWidth;
  final Color? shadowColor;
  final double shadowBlur;
  final double shadowOffsetY;
  final double shadowSpread;
  final double cornerRadius;

  /// Space around the banner, inside the safe area.
  final EdgeInsets margin;
  final double horizontalPadding;
  final double verticalPadding;
  final double iconGap;
  final double trailingGap;
  final double subtitleGap;

  /// The circle behind the icon.
  final Color? iconBackground;
  final double iconBoxSize;
  final double iconSize;
  final Color? badgeColor;
  final Color? badgeBackground;
  final Color? badgeShadowColor;
  final double badgeSize;
  final double badgePadding;

  /// How far the badge sits outside the icon circle's top-right corner.
  final double badgeOffset;

  Map<String, Object?> encode() => {
    'dark': dark,
    'titleStyle': _encodeStyle(titleStyle),
    'subtitleStyle': _encodeStyle(subtitleStyle),
    'bodyStyle': _encodeStyle(bodyStyle),
    'trailingStyle': _encodeStyle(trailingStyle),
    'tint': tint?.toARGB32(),
    'borderColor': borderColor?.toARGB32(),
    'borderWidth': borderWidth,
    'shadowColor': shadowColor?.toARGB32(),
    'shadowBlur': shadowBlur,
    'shadowOffsetY': shadowOffsetY,
    'shadowSpread': shadowSpread,
    'cornerRadius': cornerRadius,
    'marginLeft': margin.left,
    'marginTop': margin.top,
    'marginRight': margin.right,
    'horizontalPadding': horizontalPadding,
    'verticalPadding': verticalPadding,
    'iconGap': iconGap,
    'trailingGap': trailingGap,
    'subtitleGap': subtitleGap,
    'iconBackground': iconBackground?.toARGB32(),
    'iconBoxSize': iconBoxSize,
    'iconSize': iconSize,
    'badgeColor': badgeColor?.toARGB32(),
    'badgeBackground': badgeBackground?.toARGB32(),
    'badgeShadowColor': badgeShadowColor?.toARGB32(),
    'badgeSize': badgeSize,
    'badgePadding': badgePadding,
    'badgeOffset': badgeOffset,
  };

  static Map<String, Object?>? _encodeStyle(TextStyle? style) => style == null
      ? null
      : {
          'family': style.fontFamily,
          'size': style.fontSize,
          'weight': style.fontWeight?.value,
          'height': style.height,
          'color': style.color?.toARGB32(),
        };
}

/// Drops a notification banner in from the top of the screen, like an
/// in-app version of a system notification: [icon] in a circle (with an
/// optional [badge] on its corner), [title] with [trailing] (a time, say)
/// beside it, then [subtitle] and up to [bodyMaxLines] of [body].
///
/// On iOS 26 it is UIKit on Liquid Glass, in a window of its own above the
/// app's native chrome and sheets — which Flutter content can't cover. Tap
/// it for [onTap]; swipe it up to dismiss. It leaves after [duration] (held
/// while touched), or when another banner replaces it; [onDismissed] runs
/// whichever way it goes, after [onTap] for a tap.
///
/// Answers whether it was shown. There is no Flutter fallback: elsewhere
/// (Android, iOS 15–25) it answers false, so draw your own.
Future<bool> showNativeBanner({
  required String title,
  String? subtitle,
  String? body,
  String? trailing,
  NativeIcon? icon,
  NativeIcon? badge,
  int bodyMaxLines = 3,
  Duration duration = const Duration(seconds: 5),
  NativeBannerStyle style = const NativeBannerStyle(),
  String? semanticLabel,
  VoidCallback? onTap,
  VoidCallback? onDismissed,
}) async {
  final bridge = VeneerBridge.instance;
  if (!bridge.isSupported) return false;
  return bridge.showBanner(
    {
      'title': title,
      'subtitle': subtitle,
      'body': body,
      'trailing': trailing,
      'icon': icon?.encode(),
      'badge': badge?.encode(),
      'bodyMaxLines': bodyMaxLines,
      'duration': duration.inMilliseconds / 1000,
      'semanticLabel': semanticLabel,
      ...style.encode(),
    },
    onTap: onTap,
    onDismissed: onDismissed,
  );
}

/// Slides away the banner [showNativeBanner] is showing, if any.
Future<void> hideNativeBanner() async {
  final bridge = VeneerBridge.instance;
  if (!bridge.isSupported) return;
  await bridge.hideBanner();
}
