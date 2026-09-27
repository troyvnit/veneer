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

/// Calls [onChange] when a route enclosing the page's own navigator is
/// covered or uncovered (a popup or sheet on an outer navigator). The page's
/// own route already notifies through `ModalRoute.of`; outer ones don't reach
/// its dependents, so their transitions are listened to directly.
class RouteChainWatcher {
  RouteChainWatcher(this.onChange);

  final VoidCallback onChange;
  List<Animation<double>> _watched = const [];

  /// Re-collects the outer routes; call from `didChangeDependencies`.
  void update(BuildContext context) {
    final animations = <Animation<double>>[];
    var route = ModalRoute.of(context);
    while (route != null) {
      final outer = route.navigator?.context;
      route = outer == null ? null : ModalRoute.of(outer);
      if (route == null) break;
      if (route.animation case final a?) animations.add(a);
      if (route.secondaryAnimation case final a?) animations.add(a);
    }
    if (_sameAs(animations)) return;
    _detach();
    _watched = animations;
    for (final a in _watched) {
      a.addStatusListener(_onStatus);
    }
  }

  bool _sameAs(List<Animation<double>> other) {
    if (other.length != _watched.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (!identical(other[i], _watched[i])) return false;
    }
    return true;
  }

  void _onStatus(AnimationStatus _) => onChange();

  void _detach() {
    for (final a in _watched) {
      a.removeStatusListener(_onStatus);
    }
    _watched = const [];
  }

  void dispose() => _detach();
}
