import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'native_chrome_pane.dart';

/// Whether the page holding [context] is the one on screen: its route is
/// current in its navigator, and so is every enclosing navigator's route.
/// A page in a nested navigator (a tab's) stays current there while a route
/// pushed on an outer navigator covers it, so the nearest route alone isn't
/// enough. Registers dependencies on each route, so callers rebuild when any
/// of them changes.
///
/// In a [NativeChromePane], routes above that show in other panes
/// ([NativePaneRoute]) don't cover the page.
bool isRouteOnTop(BuildContext context) {
  final pane = NativeChromePane.maybeOf(context)?.id;
  BuildContext? current = context;
  while (current != null) {
    final route = ModalRoute.of(current);
    if (route == null) return true;
    if (!route.isCurrent && !_onlyOtherPanesAbove(route, pane)) return false;
    current = route.navigator?.context;
  }
  return true;
}

bool _onlyOtherPanesAbove(Route<dynamic> route, String? pane) {
  if (pane == null) return false;
  final navigator = route.navigator;
  final stack = navigator == null ? null : _stacks[navigator];
  if (stack == null) return false;
  final index = stack.indexOf(route);
  if (index < 0) return false;
  for (final above in stack.skip(index + 1)) {
    if (above is! NativePaneRoute) return false;
    final other = above.nativePane;
    if (other == null || other == pane) return false;
  }
  return true;
}

final Expando<List<Route<dynamic>>> _stacks = Expando('veneer route stack');

/// Keeps each observed navigator's routes in order, bottom to top, for
/// [isRouteOnTop] in split layouts.
abstract final class RouteStacks {
  static List<Route<dynamic>> _of(NavigatorState navigator) => _stacks[navigator] ??= [];

  /// Bumped after any observed navigator's routes change, once per frame. A
  /// page in a split layout can be covered or uncovered by a route that isn't
  /// the one right above its own (a sheet over the other pane's page), which
  /// its own route doesn't hear about.
  static final ValueNotifier<int> revision = ValueNotifier(0);
  static bool _scheduled = false;

  static void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      revision.value++;
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  static void pushed(NavigatorState? navigator, Route<dynamic> route) {
    if (navigator == null) return;
    _of(navigator).add(route);
    _changed();
  }

  static void removed(NavigatorState? navigator, Route<dynamic> route) {
    if (navigator == null) return;
    _of(navigator).remove(route);
    _changed();
  }

  static void replaced(NavigatorState? navigator, Route<dynamic>? oldRoute, Route<dynamic>? newRoute) {
    if (navigator == null) return;
    final stack = _of(navigator);
    final index = oldRoute == null ? -1 : stack.indexOf(oldRoute);
    if (index < 0) {
      if (newRoute != null) stack.add(newRoute);
    } else if (newRoute == null) {
      stack.removeAt(index);
    } else {
      stack[index] = newRoute;
    }
    _changed();
  }
}

/// Calls [onChange] when a route enclosing the page's own navigator is
/// covered or uncovered (a popup or sheet on an outer navigator). The page's
/// own route already notifies through `ModalRoute.of`; outer ones don't reach
/// its dependents, so their transitions are listened to directly.
class RouteChainWatcher {
  RouteChainWatcher(this.onChange);

  final VoidCallback onChange;
  List<Animation<double>> _watched = const [];
  bool _watchingStacks = false;

  void _onStacks() => onChange();

  /// Re-collects the outer routes; call from `didChangeDependencies`.
  void update(BuildContext context) {
    if (!_watchingStacks) {
      _watchingStacks = true;
      RouteStacks.revision.addListener(_onStacks);
    }
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

  void dispose() {
    if (_watchingStacks) RouteStacks.revision.removeListener(_onStacks);
    _detach();
  }
}
