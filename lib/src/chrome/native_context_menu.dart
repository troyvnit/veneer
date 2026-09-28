import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/fallback_scope.dart';
import '../core/native_menu.dart';
import '../core/route_visibility.dart';
import '../core/veneer_bridge.dart';
import '../glass/glass_coordinator.dart';

/// Long-pressing [child] opens a context menu of [items].
///
/// On iOS 26 it is UIKit's own `UIContextMenuInteraction`: the press
/// shrink, [child] lifting over a blurred backdrop with the menu beside it,
/// haptics, and the settle back. UIKit recognizes the long press on the
/// Flutter view and hit-tests against where Flutter laid [child] out this
/// frame, so it follows scrolling with no round trip; a press that moves
/// (a scroll) never opens it. The lifted preview is a snapshot of [child]
/// clipped to [borderRadius], and [child] is hidden while it's up.
///
/// Elsewhere (Android, iOS 15–25) a long press opens the Flutter replica of
/// a native menu next to [child].
class NativeContextMenu extends StatefulWidget {
  const NativeContextMenu({super.key, required this.items, required this.child, this.borderRadius = BorderRadius.zero});

  /// Empty disables the menu.
  final List<NativeMenuItem> items;
  final Widget child;

  /// Shape of the lifted preview, e.g. a message bubble's corners.
  final BorderRadius borderRadius;

  @override
  State<NativeContextMenu> createState() => _NativeContextMenuState();
}

class _NativeContextMenuState extends State<NativeContextMenu> {
  final int _id = GlassCoordinator.allocateId();
  bool _native = false;
  bool _configured = false;
  bool _open = false;

  late final RouteChainWatcher _routes = RouteChainWatcher(() {
    if (mounted) setState(() {});
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routes.update(context);
    final native = useNativeLayer(context);
    if (native != _native) {
      _native = native;
      _configure();
    }
  }

  @override
  void didUpdateWidget(NativeContextMenu old) {
    super.didUpdateWidget(old);
    if (_key(old) != _key(widget)) _configure();
  }

  static String _key(NativeContextMenu menu) =>
      jsonEncode([for (final item in menu.items) item.encode(), menu.borderRadius.toString()]);

  void _configure() {
    if (!_native || widget.items.isEmpty) {
      if (_configured) VeneerBridge.instance.removeContextMenu(_id);
      _configured = false;
      return;
    }
    _configured = true;
    final r = widget.borderRadius;
    VeneerBridge.instance
        .configureContextMenu(
          {
            'id': _id,
            'menu': encodeMenu('$_id', widget.items, {}),
            'radii': [r.topLeft.x, r.topRight.x, r.bottomRight.x, r.bottomLeft.x],
          },
          VeneerContextMenuHandlers(
            onSelected: (index) {
              final items = widget.items;
              if (index < items.length) items[index].onSelected?.call();
            },
            onOpenChanged: (open) {
              if (mounted && open != _open) setState(() => _open = open);
            },
          ),
        )
        // Geometry for this id may have gone out before native knew it.
        .then((_) => GlassCoordinator.instance.markDirty());
  }

  @override
  void dispose() {
    _routes.dispose();
    if (_configured) VeneerBridge.instance.removeContextMenu(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_native) {
      if (widget.items.isEmpty) return widget.child;
      return GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          showFallbackMenu(context, widget.items);
        },
        child: widget.child,
      );
    }
    final visible = Visibility.of(context) && isRouteOnTop(context) && widget.items.isNotEmpty;
    return _MenuAnchor(
      id: _id,
      shouldShow: visible,
      child: Opacity(opacity: _open ? 0 : 1, child: widget.child),
    );
  }
}

class _MenuAnchor extends SingleChildRenderObjectWidget {
  const _MenuAnchor({required this.id, required this.shouldShow, super.child});

  final int id;
  final bool shouldShow;

  @override
  RenderGlassAnchor createRenderObject(BuildContext context) => RenderGlassAnchor(shapeId: id, shouldShow: shouldShow);

  @override
  void updateRenderObject(BuildContext context, RenderGlassAnchor renderObject) {
    renderObject.shouldShow = shouldShow;
  }
}
