import 'package:flutter/widgets.dart';

/// Whether the page holding [context] is the one on screen: its route is
/// current in its navigator, and so is every enclosing navigator's route.
/// A page in a nested navigator (a tab's) stays current there while a route
/// pushed on an outer navigator covers it, so the nearest route alone isn't
/// enough. Registers dependencies on each route, so callers rebuild when any
/// of them changes.
bool isRouteOnTop(BuildContext context) {
  BuildContext? current = context;
  while (current != null) {
    final route = ModalRoute.of(current);
    if (route == null) return true;
    if (!route.isCurrent) return false;
    current = route.navigator?.context;
  }
  return true;
}
