import 'package:flutter/widgets.dart';

import '../core/veneer_bridge.dart';

/// Scopes the [GlassShape]s below it into one native glass container.
///
/// Shapes merge and morph only with shapes in the same group. Groups stack
/// by [zIndex] (then creation order); glass in an upper group refracts the
/// groups beneath it but never fuses with them.
///
/// Shapes outside any [GlassGroup] join their route's default group, so
/// glass on different routes never merges — e.g. during a push transition.
///
/// Typical split: floating controls in a `GlassGroup(zIndex: 1)`, content
/// glass in the route default, so scrolling content glides *under* the
/// controls instead of melting into them.
class GlassGroup extends StatefulWidget {
  const GlassGroup({super.key, this.spacing, this.zIndex = 0, required this.child});

  /// Distance within which this group's shapes merge. Null uses the
  /// app-wide default ([Veneer.setGlassSpacing]).
  final double? spacing;

  /// Stacking order among groups. Route default groups are 0.
  final int zIndex;

  final Widget child;

  /// The group id a [GlassShape] at [context] belongs to.
  static int groupIdOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_GlassGroupScope>();
    if (scope != null) return scope.id;
    final route = ModalRoute.of(context);
    return route == null ? 0 : (_routeGroups[route] ??= _nextRouteGroupId--);
  }

  // Explicit groups count up from 1, route defaults down from -1; 0 is the
  // route-less default. Route groups are created natively on first use and
  // dropped there once empty, so nothing to clean up here.
  static final Expando<int> _routeGroups = Expando('GlassGroup.route');
  static int _nextRouteGroupId = -1;
  static int _nextId = 1;

  @override
  State<GlassGroup> createState() => _GlassGroupState();
}

class _GlassGroupState extends State<GlassGroup> {
  final int _id = GlassGroup._nextId++;

  @override
  void initState() {
    super.initState();
    // Sent before any child shape's configureShape: parents run initState
    // first and both queue behind the same attach future.
    _configure();
  }

  @override
  void didUpdateWidget(GlassGroup old) {
    super.didUpdateWidget(old);
    if (old.spacing != widget.spacing || old.zIndex != widget.zIndex) _configure();
  }

  void _configure() {
    VeneerBridge.instance.configureGroup({'id': _id, 'spacing': widget.spacing, 'zIndex': widget.zIndex});
  }

  @override
  void dispose() {
    VeneerBridge.instance.removeGroup(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _GlassGroupScope(id: _id, child: widget.child);
}

class _GlassGroupScope extends InheritedWidget {
  const _GlassGroupScope({required this.id, required super.child});

  final int id;

  @override
  bool updateShouldNotify(_GlassGroupScope old) => old.id != id;
}
