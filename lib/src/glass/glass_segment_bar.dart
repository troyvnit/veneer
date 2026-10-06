import 'package:flutter/material.dart';

import '../core/fallback_scope.dart';
import '../core/fallback_style.dart';
import '../core/native_icon.dart';
import '../core/route_visibility.dart';
import '../core/veneer_bridge.dart';
import 'glass_coordinator.dart';
import 'glass_group.dart';
import 'glass_shape.dart';

/// One item of a [GlassSegmentBar]: an icon, a short label (e.g. an emoji),
/// or both.
@immutable
class GlassSegment {
  const GlassSegment({this.icon, this.label}) : assert(icon != null || label != null);

  final NativeIcon? icon;
  final String? label;

  Map<String, Object?> encode() => {'icon': icon?.encode(), 'label': label};

  @override
  bool operator ==(Object other) => other is GlassSegment && other.icon == icon && other.label == label;

  @override
  int get hashCode => Object.hash(icon, label);
}

/// A row of tappable icons on one Liquid Glass capsule, with a highlight
/// that slides to the selected one — like the category bar of an emoji
/// keyboard or a compact tab strip.
///
/// On iOS 26 the capsule, icons, highlight and its spring are native; taps
/// come back through [onSelected]. The bar sizes itself to
/// `segments.length * segmentWidth` plus its inner padding.
///
/// On Android and iOS 15–25 it renders a Flutter replica with the same
/// layout.
class GlassSegmentBar extends StatefulWidget {
  const GlassSegmentBar({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 44,
    this.segmentWidth = 40,
    this.iconSize = 20,
    this.foreground,
    this.selectedForeground,
    this.selectionColor,
    this.style = GlassStyle.regular,
    this.tint,
  });

  final List<GlassSegment> segments;

  /// Out of range (e.g. -1) highlights nothing.
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;
  final double segmentWidth;
  final double iconSize;

  /// Icon/label colour of unselected segments. Null: secondary label.
  final Color? foreground;

  /// Icon/label colour of the selected segment. Null: label.
  final Color? selectedForeground;

  /// The highlight behind the selected segment. Null: a light capsule that
  /// adapts to light and dark mode.
  final Color? selectionColor;
  final GlassStyle style;
  final Color? tint;

  /// Space between the capsule's edge and the outer segments.
  static const double padding = 4;

  @override
  State<GlassSegmentBar> createState() => _GlassSegmentBarState();
}

class _GlassSegmentBarState extends State<GlassSegmentBar> {
  final int _id = GlassCoordinator.allocateId();

  int? _group;
  bool _native = false;

  late final RouteChainWatcher _routes = RouteChainWatcher(() {
    if (mounted) setState(() {});
  });

  double get _width => widget.segments.length * widget.segmentWidth + GlassSegmentBar.padding * 2;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routes.update(context);
    _native = useNativeLayer(context);
    final group = GlassGroup.groupIdOf(context);
    if (group != _group) {
      _group = group;
      _configure();
    }
  }

  @override
  void didUpdateWidget(GlassSegmentBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.selectedIndex != widget.selectedIndex ||
        old.height != widget.height ||
        old.segmentWidth != widget.segmentWidth ||
        old.iconSize != widget.iconSize ||
        old.foreground != widget.foreground ||
        old.selectedForeground != widget.selectedForeground ||
        old.selectionColor != widget.selectionColor ||
        old.style != widget.style ||
        old.tint != widget.tint ||
        !_sameSegments(old.segments, widget.segments)) {
      _configure();
    }
  }

  static bool _sameSegments(List<GlassSegment> a, List<GlassSegment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _configure() {
    if (!_native) return;
    VeneerBridge.instance
        .configureShape(
          {
            'id': _id,
            'group': _group,
            'style': widget.style.name,
            'tint': widget.tint?.toARGB32(),
            'interactive': true,
            'segments': {
              'items': [for (final segment in widget.segments) segment.encode()],
              'selected': widget.selectedIndex,
              'iconSize': widget.iconSize,
              'padding': GlassSegmentBar.padding,
              'foreground': widget.foreground?.toARGB32(),
              'selectedForeground': widget.selectedForeground?.toARGB32(),
              'selectionColor': widget.selectionColor?.toARGB32(),
            },
          },
          null,
          onSegment: (index) {
            if (index >= 0 && index < widget.segments.length) widget.onSelected(index);
          },
        )
        .then((_) => GlassCoordinator.instance.markDirty());
  }

  @override
  void dispose() {
    _routes.dispose();
    if (_native) VeneerBridge.instance.removeShape(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_native) return _FallbackSegmentBar(bar: widget, width: _width);
    final visible = Visibility.of(context) && isRouteOnTop(context);
    return _SegmentAnchor(
      shapeId: _id,
      shouldShow: visible,
      child: SizedBox(width: _width, height: widget.height),
    );
  }
}

class _SegmentAnchor extends SingleChildRenderObjectWidget {
  const _SegmentAnchor({required this.shapeId, required this.shouldShow, super.child});

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

/// Flutter replica: the capsule on the fallback surface, with the
/// highlight sliding between segments.
class _FallbackSegmentBar extends StatelessWidget {
  const _FallbackSegmentBar({required this.bar, required this.width});

  final GlassSegmentBar bar;
  final double width;

  @override
  Widget build(BuildContext context) {
    final style = VeneerFallbackStyle.of(context);
    final selected = bar.selectedIndex;
    final hasSelection = selected >= 0 && selected < bar.segments.length;
    final inner = bar.height - GlassSegmentBar.padding * 2;

    return SizedBox(
      width: width,
      height: bar.height,
      child: DecoratedBox(
        decoration: style.surfaceDecoration(radius: BorderRadius.circular(bar.height / 2), color: bar.tint),
        child: Padding(
          padding: const EdgeInsets.all(GlassSegmentBar.padding),
          child: Stack(
            children: [
              if (hasSelection)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: selected * bar.segmentWidth,
                  top: 0,
                  width: bar.segmentWidth,
                  height: inner,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: bar.selectionColor ?? style.selection,
                      borderRadius: BorderRadius.circular(inner / 2),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < bar.segments.length; i++)
                    SizedBox(
                      width: bar.segmentWidth,
                      height: inner,
                      child: Semantics(
                        button: true,
                        selected: i == selected,
                        label: bar.segments[i].label,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => bar.onSelected(i),
                          child: Center(child: _segmentContent(bar.segments[i], i == selected, style)),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segmentContent(GlassSegment segment, bool selected, VeneerFallbackStyle style) {
    final color = selected ? bar.selectedForeground ?? style.label : bar.foreground ?? style.secondaryLabel;
    if (segment.icon case final icon?) return NativeIconView(icon, size: bar.iconSize, color: color);
    return Text(
      segment.label!,
      style: TextStyle(fontSize: bar.iconSize, color: color),
    );
  }
}
