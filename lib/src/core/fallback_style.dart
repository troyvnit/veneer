import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Colours and surfaces for the Flutter fallbacks (Android, iOS 15–25).
///
/// The fallbacks replicate the iOS 26 native chrome — same layout, sizes,
/// positions and radii — with solid surfaces where iOS uses Liquid Glass.
/// By default: white (light) or #2C2C2E (dark) with a hairline border and a
/// soft shadow, iOS system colours for labels, placeholders, accent and
/// badges.
///
/// To match a design system, add a style to the app's `ThemeData.extensions`
/// (one per brightness); every fallback reads it from the theme.
@immutable
class VeneerFallbackStyle extends ThemeExtension<VeneerFallbackStyle> {
  const VeneerFallbackStyle({
    required this.dark,
    required this.surface,
    required this.innerSurface,
    required this.selection,
    required this.border,
    required this.label,
    required this.secondaryLabel,
    required this.placeholder,
    required this.disabled,
    required this.accent,
    required this.badge,
    required this.shadowColor,
  });

  factory VeneerFallbackStyle.of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<VeneerFallbackStyle>() ?? (theme.brightness == Brightness.dark ? iosDark : iosLight);
  }

  static const iosLight = VeneerFallbackStyle(
    dark: false,
    surface: Color(0xFFFFFFFF),
    innerSurface: Color(0xFFF2F2F7),
    selection: Color(0x12000000),
    border: Color(0x14000000),
    label: Color(0xFF000000),
    secondaryLabel: Color(0x993C3C43),
    placeholder: Color(0x4D3C3C43),
    disabled: Color(0x4D3C3C43),
    accent: Color(0xFF007AFF),
    badge: Color(0xFFFF3B30),
    shadowColor: Color(0x1A000000),
  );

  static const iosDark = VeneerFallbackStyle(
    dark: true,
    surface: Color(0xFF2C2C2E),
    innerSurface: Color(0xFF3A3A3C),
    selection: Color(0x2EFFFFFF),
    border: Color(0x1FFFFFFF),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0x99EBEBF5),
    placeholder: Color(0x4DEBEBF5),
    disabled: Color(0x4DEBEBF5),
    accent: Color(0xFF0A84FF),
    badge: Color(0xFFFF453A),
    shadowColor: Color(0x66000000),
  );

  final bool dark;

  /// Where iOS draws a glass bar, capsule or button.
  final Color surface;

  /// A control inside a surface (the composer's + circle).
  final Color innerSurface;

  /// The pill behind a selected tab.
  final Color selection;

  final Color border;

  /// iOS `label`, `secondaryLabel`, `placeholderText`.
  final Color label;
  final Color secondaryLabel;
  final Color placeholder;
  final Color disabled;

  /// iOS `systemBlue` and `systemRed` by default.
  final Color accent;
  final Color badge;

  final Color shadowColor;

  List<BoxShadow> get shadow => [BoxShadow(color: shadowColor, blurRadius: 24, offset: const Offset(0, 6))];

  /// A solid stand-in for a glass surface.
  BoxDecoration surfaceDecoration({BorderRadius? radius, BoxShape shape = BoxShape.rectangle, Color? color}) =>
      BoxDecoration(
        color: color ?? surface,
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : radius,
        border: Border.all(color: border, width: 0.5),
        boxShadow: shadow,
      );

  @override
  VeneerFallbackStyle copyWith({
    bool? dark,
    Color? surface,
    Color? innerSurface,
    Color? selection,
    Color? border,
    Color? label,
    Color? secondaryLabel,
    Color? placeholder,
    Color? disabled,
    Color? accent,
    Color? badge,
    Color? shadowColor,
  }) => VeneerFallbackStyle(
    dark: dark ?? this.dark,
    surface: surface ?? this.surface,
    innerSurface: innerSurface ?? this.innerSurface,
    selection: selection ?? this.selection,
    border: border ?? this.border,
    label: label ?? this.label,
    secondaryLabel: secondaryLabel ?? this.secondaryLabel,
    placeholder: placeholder ?? this.placeholder,
    disabled: disabled ?? this.disabled,
    accent: accent ?? this.accent,
    badge: badge ?? this.badge,
    shadowColor: shadowColor ?? this.shadowColor,
  );

  @override
  VeneerFallbackStyle lerp(VeneerFallbackStyle? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return VeneerFallbackStyle(
      dark: (lerpDouble(dark ? 1 : 0, other.dark ? 1 : 0, t) ?? 0) >= 0.5,
      surface: c(surface, other.surface),
      innerSurface: c(innerSurface, other.innerSurface),
      selection: c(selection, other.selection),
      border: c(border, other.border),
      label: c(label, other.label),
      secondaryLabel: c(secondaryLabel, other.secondaryLabel),
      placeholder: c(placeholder, other.placeholder),
      disabled: c(disabled, other.disabled),
      accent: c(accent, other.accent),
      badge: c(badge, other.badge),
      shadowColor: c(shadowColor, other.shadowColor),
    );
  }
}
