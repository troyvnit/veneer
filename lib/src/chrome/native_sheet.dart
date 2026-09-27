import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import '../core/fallback_scope.dart';
import '../core/fallback_style.dart';
import '../core/veneer_bridge.dart';

/// A height a [NativeSheetRoute] rests at, like `UISheetPresentationController.Detent`.
@immutable
class NativeSheetDetent {
  /// A fraction of the tallest the sheet can be ([large]).
  const NativeSheetDetent.fraction(double this.fraction) : height = null;

  /// A fixed height in points (capped at [large]).
  const NativeSheetDetent.height(double this.height) : fraction = null;

  /// About half the screen: the sheet floats inset from the edges.
  static const medium = NativeSheetDetent.fraction(0.5);

  /// Nearly full screen: the sheet meets the edges and the page behind recedes.
  static const large = NativeSheetDetent.fraction(1);

  final double? fraction;
  final double? height;

  /// Resolved against the large detent's height.
  double resolve(double largeHeight) => math.min(largeHeight, height ?? largeHeight * fraction!);

  Map<String, Object?> _encode() => this == medium
      ? {'type': 'medium'}
      : this == large
      ? {'type': 'large'}
      : height != null
      ? {'type': 'height', 'value': height}
      : {'type': 'fraction', 'value': fraction};

  @override
  bool operator ==(Object other) => other is NativeSheetDetent && other.fraction == fraction && other.height == height;

  @override
  int get hashCode => Object.hash(fraction, height);
}

/// Presents a sheet, following Apple's Human Interface Guidelines for sheets.
///
/// **Native (iOS 26, with an [entrypoint])** — a real UIKit sheet: a
/// `FlutterViewController` presented with `.pageSheet`, so
/// `UISheetPresentationController` provides the detents, grabber, drag,
/// dimming, Liquid Glass background and the page behind receding. The
/// sheet's view is transparent, so the glass shows through its content.
///
/// A Flutter engine renders into one view at a time, so the sheet runs in its
/// own engine: a top-level function marked `@pragma('vm:entry-point')` that
/// calls [runNativeSheet], in your `main.dart` (or in [libraryUri]). Engines
/// are spawned from a shared `FlutterEngineGroup`, which shares compiled code
/// and the GPU context; call [NativeSheet.prewarm] early so content is ready
/// the moment the sheet slides up. The sheet's isolate doesn't share state
/// with the app: pass [arguments] in (they reach the entrypoint as its
/// `List<String>` parameter; arguments bypass pre-warmed engines), or a
/// [payload] the sheet reads with [NativeSheet.payload] (pre-warmed engines
/// receive it when presented), and return a result with [NativeSheet.close]. Veneer works inside it: a
/// [NativeNavigationBar] is a real `UINavigationBar` in the sheet and a
/// composer rides the sheet natively.
///
/// **Elsewhere (Android, iOS 15–25, or without an entrypoint)** — [builder]'s
/// content in a Flutter sheet with the same behaviour ([NativeSheetRoute]),
/// its Veneer widgets drawn as Flutter replicas.
///
/// In both: rests at each of [detents] (default: large only); a grabber shows
/// when there's more than one (override with [showGrabber]); the page behind
/// dims above [largestUndimmedDetent] (all detents when null); drag down or
/// tap the dimmed area to dismiss unless [isDismissible] is false.
Future<T?> showNativeSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? entrypoint,
  String? libraryUri,
  List<String> arguments = const [],
  Object? payload,
  List<NativeSheetDetent> detents = const [NativeSheetDetent.large],
  NativeSheetDetent? initialDetent,
  bool? showGrabber,
  bool isDismissible = true,
  NativeSheetDetent? largestUndimmedDetent,
  ValueChanged<NativeSheetDetent>? onDetentChanged,
  bool expandsOnScroll = true,
  Color? backgroundColor,
  bool useRootNavigator = true,
}) async {
  final bridge = VeneerBridge.instance;
  if (entrypoint != null && bridge.isSupported) {
    try {
      final result = await bridge.presentSheet({
        'entrypoint': entrypoint,
        'libraryUri': libraryUri,
        'arguments': arguments,
        'payload': payload,
        'detents': [for (final d in detents) d._encode()],
        'initialDetent': initialDetent == null ? null : detents.indexOf(initialDetent),
        'grabber': showGrabber,
        'largestUndimmedDetent': largestUndimmedDetent == null ? null : detents.indexOf(largestUndimmedDetent),
        'dismissible': isDismissible,
        'expandsOnScroll': expandsOnScroll,
      }, onDetentChanged: onDetentChanged == null ? null : (i) => onDetentChanged(detents[i]));
      return result as T?;
    } on StateError {
      // Not presentable (no view controller yet): fall back to Flutter.
    }
  }
  if (!context.mounted) return null;
  return Navigator.of(context, rootNavigator: useRootNavigator).push(
    NativeSheetRoute<T>(
      builder: builder,
      detents: detents,
      initialDetent: initialDetent,
      showGrabber: showGrabber,
      isDismissible: isDismissible,
      largestUndimmedDetent: largestUndimmedDetent,
      onDetentChanged: onDetentChanged,
      backgroundColor: backgroundColor,
    ),
  );
}

/// Starts a native sheet's Flutter app. Call it from the sheet's entrypoint:
///
/// ```dart
/// @pragma('vm:entry-point')
/// void assistantSheet(List<String> args) =>
///     runNativeSheet(const MaterialApp(home: AssistantPage()));
/// ```
///
/// Give the sheet's `Scaffold` a transparent background so the sheet's
/// Liquid Glass shows through.
void runNativeSheet(Widget app) {
  WidgetsFlutterBinding.ensureInitialized();
  VeneerBridge.instance.isSheetEngine = true;
  runApp(_SheetScrollEdgeReporter(child: app));
}

/// Tells UIKit, as each touch starts, whether the content under it is
/// scrolled to its top edge — the sheet's rule for whether a pull down drags
/// the sheet or scrolls the content. Content that doesn't scroll counts as
/// at the top.
class _SheetScrollEdgeReporter extends StatefulWidget {
  const _SheetScrollEdgeReporter({required this.child});

  final Widget child;

  @override
  State<_SheetScrollEdgeReporter> createState() => _SheetScrollEdgeReporterState();
}

class _SheetScrollEdgeReporterState extends State<_SheetScrollEdgeReporter> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A sheet never sits under the status bar, and iOS delivers an engine's
    // overlay style to every Flutter view controller: left on, a sheet
    // engine (pre-warmed ones too) would restyle the app's status bar.
    context.findAncestorRenderObjectOfType<RenderView>()?.automaticSystemUiAdjustment = false;
  }

  static bool _atTop(Offset position, int viewId) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderViewportBase && axisDirectionToAxis(target.axisDirection) == Axis.vertical) {
        final offset = target.offset;
        if (offset is! ScrollPosition || !offset.hasContentDimensions) return true;
        return target.axisDirection == AxisDirection.down
            ? offset.pixels <= offset.minScrollExtent + 0.5
            : offset.pixels >= offset.maxScrollExtent - 0.5;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) =>
        VeneerBridge.instance.setSheetContentAtTop(_atTop(event.position, View.of(context).viewId)),
    child: widget.child,
  );
}

/// Sheet helpers that work in native sheets and their Flutter fallback alike.
abstract final class NativeSheet {
  /// Closes the sheet showing [context], returning [result] to
  /// [showNativeSheet] (for native sheets: any value the standard message
  /// codec carries — strings, numbers, lists, maps).
  static Future<void> close(BuildContext context, [Object? result]) async {
    if (VeneerBridge.instance.isSheetEngine) {
      await VeneerBridge.instance.dismissSheet(result);
    } else {
      await Navigator.of(context).maybePop(result);
    }
  }

  /// Starts an engine at [entrypoint] now, so the next native sheet shows its
  /// content immediately. After a sheet closes, the next engine is warmed
  /// automatically. Does nothing where native sheets aren't available.
  static Future<void> prewarm(String entrypoint, {String? libraryUri}) async {
    if (!VeneerBridge.instance.isSupported) return;
    await VeneerBridge.instance.prewarmSheet(entrypoint, libraryUri: libraryUri);
  }

  /// Inside a native sheet: the `payload` given to [showNativeSheet]. A
  /// pre-warmed engine starts before it's presented, so this completes once
  /// the sheet is presented. Null outside native sheets.
  static Future<Object?> payload() async {
    if (!VeneerBridge.instance.isSheetEngine) return null;
    return VeneerBridge.instance.sheetPayload();
  }

  /// Whether this code runs inside a native sheet's engine.
  static bool get isNativeSheet => VeneerBridge.instance.isSheetEngine;
}

/// The Flutter sheet behind [showNativeSheet] where UIKit sheets aren't used:
/// UIKit's metrics and physics — detents with spring snapping and velocity
/// projection, a grabber, the iOS 26 look (floating inset with display-
/// concentric corners and a translucent material below the large detent,
/// meeting the edges and opaque at large, the page behind receding),
/// dimming, drag-to-dismiss (also from content scrolled to its edge), and a
/// move to the largest detent for the keyboard. Veneer widgets inside draw as
/// Flutter replicas ([VeneerFallbackScope]).
class NativeSheetRoute<T> extends PageRoute<T> {
  NativeSheetRoute({
    required this.builder,
    this.detents = const [NativeSheetDetent.large],
    this.initialDetent,
    this.showGrabber,
    this.isDismissible = true,
    this.largestUndimmedDetent,
    this.onDetentChanged,
    this.backgroundColor,
    super.settings,
  }) : assert(detents.isNotEmpty, 'A sheet needs at least one detent');

  final WidgetBuilder builder;
  final List<NativeSheetDetent> detents;
  final NativeSheetDetent? initialDetent;
  final bool? showGrabber;
  final bool isDismissible;
  final NativeSheetDetent? largestUndimmedDetent;
  final ValueChanged<NativeSheetDetent>? onDetentChanged;
  final Color? backgroundColor;

  /// 0 below the large detent, 1 at it: how far the page behind recedes.
  final ValueNotifier<double> _recede = ValueNotifier(0);

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 350);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      _NativeSheet(route: this);

  // The sheet animates itself (the slide depends on its height).
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;

  /// The page behind recedes — scales back with rounded corners — while the
  /// sheet is at its large detent, as in UIKit.
  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      (context, animation, secondaryAnimation, allowSnapshotting, child) => AnimatedBuilder(
        animation: Listenable.merge([secondaryAnimation, _recede]),
        builder: (context, child) {
          final t = Curves.easeOut.transform(secondaryAnimation.value.clamp(0, 1)) * _recede.value;
          if (t == 0) return child!;
          final top = MediaQuery.paddingOf(context).top;
          return Transform.translate(
            offset: Offset(0, t * (top * 0.45)),
            child: Transform.scale(
              scale: 1 - 0.075 * t,
              alignment: Alignment.topCenter,
              child: ClipRRect(borderRadius: BorderRadius.circular(t * 36), child: child),
            ),
          );
        },
        child: child,
      );

  @override
  void dispose() {
    _recede.dispose();
    super.dispose();
  }
}

class _NativeSheet extends StatefulWidget {
  const _NativeSheet({required this.route});

  final NativeSheetRoute<Object?> route;

  @override
  State<_NativeSheet> createState() => _NativeSheetState();
}

class _NativeSheetState extends State<_NativeSheet> with SingleTickerProviderStateMixin {
  // UIKit's sheet spring: critically damped, about 0.5 s.
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: 1);
  static const _presentCurve = Cubic(0.2, 0.9, 0.25, 1);

  static const _grabberTop = 5.0;
  static const _grabberSize = Size(36, 5);
  static const _floatingInset = 8.0;
  static const _largeRadius = 34.0;
  static const _dimAlpha = 0.28;

  late final AnimationController _height = AnimationController.unbounded(vsync: this);
  late final CurvedAnimation _present = CurvedAnimation(
    parent: widget.route.animation!,
    curve: _presentCurve,
    reverseCurve: Curves.easeInCubic,
  );

  /// Drag past the smallest detent, downwards.
  double _drag = 0;
  bool _dragging = false;
  bool _initialized = false;
  bool _keyboardExpanded = false;
  NativeSheetDetent? _reported;
  List<double> _heights = const [];
  double _large = 0;

  NativeSheetRoute<Object?> get _route => widget.route;

  @override
  void initState() {
    super.initState();
    _height.addListener(_changed);
    _present.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.of(context);
    // The large detent leaves the status bar and a sliver of the page behind.
    _large = mq.size.height - mq.padding.top - 10;
    _heights = [for (final d in _route.detents) d.resolve(_large)]..sort();
    if (!_initialized) {
      _initialized = true;
      final initial = (_route.initialDetent ?? _route.detents.first).resolve(_large);
      _height.value = initial;
      _reported = _detentFor(initial);
      WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
    }
    // UIKit moves the sheet to its largest detent for the keyboard.
    final keyboard = mq.viewInsets.bottom > 0;
    if (keyboard && !_keyboardExpanded && _height.value < _heights.last - 0.5) {
      _keyboardExpanded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _settleTo(_heights.last, 0));
    } else if (!keyboard) {
      _keyboardExpanded = false;
    }
  }

  @override
  void dispose() {
    _height.dispose();
    _present.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    _publish();
    setState(() {});
  }

  double get _inset => lerpDouble(_floatingInset, 0, _largeness)!;

  /// How far the page behind recedes. Published from animation ticks and
  /// drags, never during build (the page behind listens).
  void _publish() {
    _route._recede.value = _largeness * (1 - (_drag / math.max(1, _min)).clamp(0.0, 1.0));
  }

  double get _min => _heights.first;
  double get _max => _heights.last;

  /// 0 at or below the detent under large, 1 at large.
  double get _largeness {
    final below = _heights.length > 1 ? _heights[_heights.length - 2] : _max * 0.5;
    if (_max - below < 1) return _max >= _large - 0.5 ? 1 : 0;
    return ((_height.value - below) / (_max - below)).clamp(0.0, 1.0);
  }

  NativeSheetDetent _detentFor(double height) {
    var best = _route.detents.first;
    var distance = double.infinity;
    for (final d in _route.detents) {
      final delta = (d.resolve(_large) - height).abs();
      if (delta < distance) {
        distance = delta;
        best = d;
      }
    }
    return best;
  }

  // MARK: Dragging

  void _dragStart() {
    _dragging = true;
    _height.stop();
  }

  /// [delta] > 0 moves the sheet down.
  void _dragBy(double delta) {
    if (!_dragging) _dragStart();
    var h = _height.value;
    if (delta > 0) {
      final shrink = math.min(delta, math.max(0, h - _min));
      h -= shrink;
      _drag += delta - shrink;
    } else {
      final up = -delta;
      final undrag = math.min(up, _drag);
      _drag -= undrag;
      var grow = up - undrag;
      // Rubber band above the largest detent.
      if (h >= _max) grow *= 0.12;
      h += grow;
    }
    if (!_route.isDismissible && _drag > 0) _drag *= 0.5;
    _height.value = h; // notifies _changed
    _changed();
  }

  void _dragEnd(double velocity) {
    _dragging = false;
    if (_drag > 0) {
      if (_route.isDismissible && (_drag > _min * 0.3 || velocity > 800)) {
        Navigator.of(context).maybePop();
        return;
      }
      _springDrag(velocity);
      return;
    }
    // Project where the flick would carry the sheet, then take the nearest
    // detent — UIKit's rule, so fast flicks skip past the middle one.
    final projected = _height.value - velocity * 0.18;
    if (_route.isDismissible && projected < _min * 0.45 && _height.value <= _min + 1) {
      Navigator.of(context).maybePop();
      return;
    }
    var target = _heights.first;
    for (final h in _heights) {
      if ((h - projected).abs() < (target - projected).abs()) target = h;
    }
    _settleTo(target, -velocity);
  }

  void _settleTo(double target, double velocity) {
    _height.animateWith(SpringSimulation(_spring, _height.value, target, velocity));
    final detent = _detentFor(target);
    if (detent != _reported) {
      _reported = detent;
      _route.onDetentChanged?.call(detent);
    }
  }

  void _springDrag(double velocity) {
    final controller = AnimationController.unbounded(vsync: this, value: _drag);
    controller.addListener(() {
      _drag = math.max(0, controller.value);
      _changed();
    });
    controller.animateWith(SpringSimulation(_spring, _drag, 0, -velocity)).whenComplete(controller.dispose);
  }

  /// Content scrolled to its edge hands the rest of the drag to the sheet.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;
    final towardsStart = n.metrics.axisDirection == AxisDirection.down ? -1.0 : 1.0;
    if (n is OverscrollNotification && n.dragDetails != null) {
      final down = n.overscroll * towardsStart;
      if (down > 0 || _drag > 0 || _dragging) _dragBy(down);
    } else if (n is ScrollUpdateNotification && _dragging && n.dragDetails != null && _drag > 0) {
      // Pulling back up while the sheet is displaced: the sheet goes first.
      final down = (n.scrollDelta ?? 0) * towardsStart;
      if (down < 0) _dragBy(down);
    } else if (n is ScrollEndNotification && _dragging) {
      _dragEnd(n.dragDetails?.primaryVelocity ?? 0);
    }
    return false;
  }

  // MARK: Build

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final style = VeneerFallbackStyle.of(context);
    final t = _largeness;
    final hasHomeIndicator = mq.viewPadding.bottom > 0;
    final inset = _inset;
    // Concentric with the display corners while floating.
    final floatingRadius = hasHomeIndicator ? 46.0 : 22.0;
    final topRadius = lerpDouble(floatingRadius, _largeRadius, t)!;
    final bottomRadius = lerpDouble(floatingRadius, hasHomeIndicator ? 46 : 0, t)!;
    final height = math.max(0.0, _height.value);
    final displacement = (1 - _present.value) * (height + inset + 24) + _drag;

    final undimmed = _route.largestUndimmedDetent?.resolve(_large);
    final dimLevel = undimmed == null
        ? 1.0
        : _heights.where((h) => h > undimmed + 0.5).isEmpty
        ? 0.0
        : ((height - undimmed) / (_heights.firstWhere((h) => h > undimmed + 0.5) - undimmed)).clamp(0.0, 1.0);
    final dim = dimLevel * _present.value * (1 - (_drag / math.max(1, _min)).clamp(0.0, 1.0));

    final dark = style.dark;
    final opaque = _route.backgroundColor ?? (dark ? const Color(0xFF1C1C1E) : Colors.white);
    // A translucent material while floating, opaque once it meets the edges.
    final surface = opaque.withValues(alpha: lerpDouble(dark ? 0.78 : 0.82, 1, t));
    final grabber = _route.showGrabber ?? _route.detents.length > 1;

    final radius = BorderRadius.vertical(top: Radius.circular(topRadius), bottom: Radius.circular(bottomRadius));

    // Content starts below the grabber, like a UIKit sheet's safe area.
    final contentTop = grabber ? 14.0 : 6.0;
    Widget content = MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(top: contentTop, bottom: math.max(0, mq.padding.bottom - inset)),
        viewPadding: mq.viewPadding.copyWith(top: contentTop, bottom: math.max(0, mq.viewPadding.bottom - inset)),
      ),
      child: ScrollConfiguration(
        // Clamping, so content at its edge reports overscroll to the sheet.
        behavior: ScrollConfiguration.of(context).copyWith(physics: const ClampingScrollPhysics()),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          // Native views can't follow a Flutter-drawn sheet: Veneer widgets
          // inside use their Flutter replicas.
          child: VeneerFallbackScope(child: Builder(builder: _route.builder)),
        ),
      ),
    );

    content = ClipRSuperellipse(
      borderRadius: radius,
      child: BackdropFilter(
        enabled: surface.a < 1,
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: ColoredBox(color: surface, child: content),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: dim < 0.5,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _route.isDismissible ? () => Navigator.of(context).maybePop() : null,
              child: ColoredBox(color: Colors.black.withValues(alpha: _dimAlpha * dim)),
            ),
          ),
        ),
        Positioned(
          left: inset,
          right: inset,
          bottom: inset - displacement,
          height: height,
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: (_) => _dragStart(),
              onVerticalDragUpdate: (d) => _dragBy(d.delta.dy),
              onVerticalDragEnd: (d) => _dragEnd(d.primaryVelocity ?? 0),
              onVerticalDragCancel: () => _dragEnd(0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.45 : 0.14 * (1 - t) + 0.04),
                      blurRadius: 40,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(child: content),
                    // The sheet's rim: a hairline that keeps its rounded top
                    // edge visible against a dark page behind, as UIKit's does.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            shape: RoundedSuperellipseBorder(
                              borderRadius: radius,
                              side: BorderSide(color: style.border, width: 1 / mq.devicePixelRatio * 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (grabber)
                      Positioned(
                        top: _grabberTop,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: _grabberSize.width,
                            height: _grabberSize.height,
                            decoration: BoxDecoration(
                              color: style.secondaryLabel.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(_grabberSize.height / 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
