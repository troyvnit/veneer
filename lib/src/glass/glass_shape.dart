import 'package:flutter/material.dart';

import '../core/native_icon.dart';
import '../core/veneer_bridge.dart';
import 'glass_coordinator.dart';
import 'glass_group.dart';

enum GlassStyle { regular, clear }

/// A native Liquid Glass shape positioned by Flutter layout.
///
/// Shapes in the same [GlassGroup] share one native glass container, so
/// shapes within the group's spacing merge, and shapes that appear or
/// disappear morph out of their neighbours. Shapes outside any group share
/// their route's default group.
///
/// The glass sits *above* all Flutter content, so content inside the shape
/// is native too ([icon], [label]). Flutter widgets placed under a shape
/// are refracted by it, not shown on top of it.
///
/// When [onTap] is set the shape is interactive: touches go to UIKit, which
/// runs the real `UIGlassEffect.isInteractive` response, and the tap comes
/// back to Dart. Touches on non-interactive shapes pass through to Flutter.
class GlassShape extends StatefulWidget {
  const GlassShape({
    super.key,
    this.width,
    this.height,
    this.style = GlassStyle.regular,
    this.tint,
    this.cornerRadius,
    this.icon,
    this.label,
    this.foreground,
    this.onTap,
  });

  /// Null fills the incoming constraints on that axis.
  final double? width;
  final double? height;
  final GlassStyle style;
  final Color? tint;

  /// Null means capsule.
  final double? cornerRadius;

  /// SF Symbol, IconData or SVG — see [NativeIcon].
  final NativeIcon? icon;
  final String? label;
  final Color? foreground;
  final VoidCallback? onTap;

  @override
  State<GlassShape> createState() => _GlassShapeState();
}

class _GlassShapeState extends State<GlassShape> {
  static int _nextId = 1;
  final int _id = _nextId++;

  int? _group;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs after initState and whenever the enclosing GlassGroup changes;
    // moving to another group reparents the native view.
    final group = GlassGroup.groupIdOf(context);
    if (group != _group) {
      _group = group;
      _configure();
    }
  }

  @override
  void didUpdateWidget(GlassShape old) {
    super.didUpdateWidget(old);
    if (old.style != widget.style ||
        old.tint != widget.tint ||
        old.cornerRadius != widget.cornerRadius ||
        old.icon != widget.icon ||
        old.label != widget.label ||
        old.foreground != widget.foreground ||
        (old.onTap == null) != (widget.onTap == null)) {
      _configure();
    }
  }

  void _configure() {
    VeneerBridge.instance
        .configureShape({
          'id': _id,
          'group': _group,
          'style': widget.style.name,
          'tint': widget.tint?.toARGB32(),
          'interactive': widget.onTap != null,
          'cornerRadius': widget.cornerRadius,
          'icon': widget.icon?.encode(),
          'label': widget.label,
          'foreground': widget.foreground?.toARGB32(),
        }, widget.onTap == null ? null : () => widget.onTap?.call())
        // The native view may be created after geometry for this id was
        // already sent; resend on the next frame.
        .then((_) => GlassCoordinator.instance.markDirty());
  }

  @override
  void dispose() {
    VeneerBridge.instance.removeShape(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hide when another route covers ours or an IndexedStack/Visibility
    // hides us: native glass would otherwise float above that content.
    // Offstage and zero opacity are caught by the coordinator's paint walk.
    final visible = Visibility.of(context) && (ModalRoute.isCurrentOf(context) ?? true);
    return Semantics(
      button: widget.onTap != null,
      label: widget.label,
      onTap: widget.onTap,
      child: _GlassAnchor(
        shapeId: _id,
        shouldShow: visible,
        child: SizedBox(width: widget.width ?? double.infinity, height: widget.height ?? double.infinity),
      ),
    );
  }
}

class _GlassAnchor extends SingleChildRenderObjectWidget {
  const _GlassAnchor({required this.shapeId, required this.shouldShow, super.child});

  final int shapeId;
  final bool shouldShow;

  @override
  RenderGlassAnchor createRenderObject(BuildContext context) =>
      RenderGlassAnchor(shapeId: shapeId, shouldShow: shouldShow);

  @override
  void updateRenderObject(BuildContext context, RenderGlassAnchor renderObject) {
    renderObject.shouldShow = shouldShow;
  }
}
