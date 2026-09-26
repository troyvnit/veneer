import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fallback_style.dart';
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
    this.iconSize,
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

  /// Icon size in points. Null: SF Symbols follow the body text style
  /// (Dynamic Type); IconData and SVGs use 22.
  final double? iconSize;
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
        old.iconSize != widget.iconSize ||
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
          'iconSize': widget.iconSize,
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
    if (!VeneerBridge.instance.isSupported) return _FallbackGlassShape(widget);
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

/// Flutter replica where native glass isn't available (Android, iOS 15–25):
/// the same shape, size and content on a solid surface — the fallback
/// palette's white/#2C2C2E with a hairline border and soft shadow, or the
/// tint — and a press highlight when tappable. It doesn't merge with
/// neighbours.
class _FallbackGlassShape extends StatefulWidget {
  const _FallbackGlassShape(this.shape);

  final GlassShape shape;

  @override
  State<_FallbackGlassShape> createState() => _FallbackGlassShapeState();
}

class _FallbackGlassShapeState extends State<_FallbackGlassShape> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final shape = widget.shape;
    final style = VeneerFallbackStyle.of(context);
    final clear = shape.style == GlassStyle.clear;
    final fill = shape.tint ?? (clear ? style.surface.withValues(alpha: 0.6) : style.surface);
    final foreground = shape.foreground ?? style.label;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shape.icon case final icon?) NativeIconView(icon, size: shape.iconSize ?? 22, color: foreground),
        if (shape.icon != null && (shape.label ?? '').isNotEmpty) const SizedBox(width: 6),
        if ((shape.label ?? '').isNotEmpty)
          Flexible(
            child: Text(
              shape.label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );

    return Semantics(
      button: shape.onTap != null,
      label: shape.label,
      child: SizedBox(
        width: shape.width ?? double.infinity,
        height: shape.height ?? double.infinity,
        child: LayoutBuilder(
          builder: (context, c) {
            final radius = shape.cornerRadius ?? math.min(c.maxWidth, c.maxHeight) / 2;
            return GestureDetector(
              onTapDown: shape.onTap == null ? null : (_) => setState(() => _pressed = true),
              onTapUp: shape.onTap == null ? null : (_) => setState(() => _pressed = false),
              onTapCancel: shape.onTap == null ? null : () => setState(() => _pressed = false),
              onTap: shape.onTap,
              child: AnimatedScale(
                // Mirrors the native interactive glass's slight swell on press.
                scale: _pressed ? 1.04 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                child: DecoratedBox(
                  decoration: style.surfaceDecoration(radius: BorderRadius.circular(radius), color: fill),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Center(child: content),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
