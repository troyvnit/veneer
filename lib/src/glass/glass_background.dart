import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/fallback_style.dart';
import '../core/veneer_bridge.dart';
import 'glass_shape.dart';

/// Liquid Glass *behind* Flutter content: a dock, a search field, a pill
/// holding Flutter text.
///
/// [GlassShape] glass sits above Flutter, so it can only hold native
/// content. This one is a platform view (a `UIVisualEffectView` with a
/// `UIGlassEffect`) that Flutter composites under [child], so [child] can be
/// any widget. The glass refracts the Flutter content behind it, not
/// [child]. Because Flutter composites it, it also follows content the
/// overlay can't, such as a sheet drawn by Flutter, so a [VeneerFallbackScope]
/// doesn't turn it into the replica. Platform views cost more than shapes;
/// prefer [GlassShape] when the content can be native.
///
/// With [onTap] the glass is interactive (UIKit's press response) and takes
/// the tap itself, so [child] should ignore pointers. Off iOS 26 it is the
/// replica surface: the fallback palette's surface with a hairline border
/// and soft shadow, or [tint].
class GlassBackground extends StatefulWidget {
  const GlassBackground({
    super.key,
    required this.child,
    this.style = GlassStyle.regular,
    this.tint,
    this.cornerRadius,
    this.onTap,
  }) : assert(style != GlassStyle.none, 'A glass background needs glass');

  final Widget child;
  final GlassStyle style;
  final Color? tint;

  /// Null means capsule.
  final double? cornerRadius;
  final VoidCallback? onTap;

  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends State<GlassBackground> {
  static const String _viewType = 'veneer/glass_background';
  static const double _capsuleRadius = 9999;

  MethodChannel? _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onCreated(int id) {
    _channel?.setMethodCallHandler(null);
    _channel = MethodChannel('veneer/glass_background_$id')
      ..setMethodCallHandler((call) async {
        if (call.method == 'tap') widget.onTap?.call();
      });
  }

  Map<String, Object?> get _params => {
    'style': widget.style.name,
    'tint': widget.tint?.toARGB32(),
    'cornerRadius': widget.cornerRadius,
    'tappable': widget.onTap != null,
  };

  @override
  Widget build(BuildContext context) {
    if (!VeneerBridge.instance.isSupported) return _fallback(context);
    final params = _params;
    return Stack(
      children: [
        Positioned.fill(
          child: UiKitView(
            // The view takes its configuration once; a new one is built when
            // it changes.
            key: ValueKey(params.toString()),
            viewType: _viewType,
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            hitTestBehavior: widget.onTap == null
                ? PlatformViewHitTestBehavior.transparent
                : PlatformViewHitTestBehavior.opaque,
            onPlatformViewCreated: _onCreated,
          ),
        ),
        widget.child,
      ],
    );
  }

  Widget _fallback(BuildContext context) {
    final style = VeneerFallbackStyle.of(context);
    final fill =
        widget.tint ?? (widget.style == GlassStyle.clear ? style.surface.withValues(alpha: 0.6) : style.surface);
    final surface = DecoratedBox(
      decoration: style.surfaceDecoration(
        radius: BorderRadius.circular(widget.cornerRadius ?? _capsuleRadius),
        color: fill,
      ),
      child: widget.child,
    );
    final onTap = widget.onTap;
    if (onTap == null) return surface;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: surface);
  }
}
