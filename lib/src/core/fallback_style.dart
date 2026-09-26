import 'package:flutter/material.dart';

/// Colours and surfaces for the Flutter fallbacks (Android, iOS 15–25).
///
/// The fallbacks replicate the iOS 26 native chrome — same layout, sizes,
/// positions and radii — with solid surfaces where iOS uses Liquid Glass:
/// white (light) or #2C2C2E (dark) with a hairline border and a soft shadow,
/// iOS system colours for labels, placeholders, accent and badges.
@immutable
class VeneerFallbackStyle {
  const VeneerFallbackStyle._(this.dark);

  factory VeneerFallbackStyle.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  static const _light = VeneerFallbackStyle._(false);
  static const _dark = VeneerFallbackStyle._(true);

  final bool dark;

  /// Where iOS draws a glass bar, capsule or button.
  Color get surface => dark ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF);

  /// A control inside a surface (the composer's + circle).
  Color get innerSurface => dark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7);

  /// The pill behind a selected tab.
  Color get selection => dark ? const Color(0x2EFFFFFF) : const Color(0x12000000);

  Color get border => dark ? const Color(0x1FFFFFFF) : const Color(0x14000000);

  /// iOS `label`, `secondaryLabel`, `placeholderText`.
  Color get label => dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  Color get secondaryLabel => dark ? const Color(0x99EBEBF5) : const Color(0x993C3C43);
  Color get placeholder => dark ? const Color(0x4DEBEBF5) : const Color(0x4D3C3C43);
  Color get disabled => dark ? const Color(0x4DEBEBF5) : const Color(0x4D3C3C43);

  /// iOS `systemBlue` and `systemRed`.
  Color get accent => dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
  Color get badge => dark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);

  List<BoxShadow> get shadow => [
    BoxShadow(
      color: dark ? const Color(0x66000000) : const Color(0x1A000000),
      blurRadius: 24,
      offset: const Offset(0, 6),
    ),
  ];

  /// A solid stand-in for a glass surface.
  BoxDecoration surfaceDecoration({BorderRadius? radius, BoxShape shape = BoxShape.rectangle, Color? color}) =>
      BoxDecoration(
        color: color ?? surface,
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : radius,
        border: Border.all(color: border, width: 0.5),
        boxShadow: shadow,
      );
}
