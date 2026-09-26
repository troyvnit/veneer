import 'package:flutter/widgets.dart';

import 'veneer_bridge.dart';

/// Makes Veneer widgets below it render their Flutter replicas even where
/// the native layer is available — for content native views can't follow,
/// such as a sheet drawn by Flutter.
class VeneerFallbackScope extends InheritedWidget {
  const VeneerFallbackScope({super.key, required super.child});

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VeneerFallbackScope>() != null;

  @override
  bool updateShouldNotify(VeneerFallbackScope oldWidget) => false;
}

/// Whether Veneer widgets at [context] use the native layer.
bool useNativeLayer(BuildContext context) =>
    VeneerBridge.instance.isSupported && !VeneerFallbackScope.isActive(context);
