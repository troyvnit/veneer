import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/cupertino.dart' show CupertinoDynamicColor;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../core/fallback_scope.dart';
import '../core/fallback_style.dart';
import '../core/veneer_bridge.dart';

/// A height a [NativeSheetRoute] rests at, like `UISheetPresentationController.Detent`.
@immutable
class NativeSheetDetent {
  /// A fraction of the tallest the sheet can be ([large]).
  const NativeSheetDetent.fraction(double this.fraction) : height = null, isContent = false;

  /// A fixed height in points (capped at [large]).
  const NativeSheetDetent.height(double this.height) : fraction = null, isContent = false;

  /// As tall as the sheet's content (capped at [large]), following it as it
  /// changes — for sheets of controls rather than pages. Flutter sheets
  /// measure the content themselves; in a native sheet, wrap it in
  /// [NativeSheetContent] so its engine can tell UIKit its height.
  const NativeSheetDetent.content() : fraction = null, height = null, isContent = true;

  /// About half the screen: the sheet floats inset from the edges.
  static const medium = NativeSheetDetent.fraction(0.5);

  /// Nearly full screen: the sheet meets the edges and the page behind recedes.
  static const large = NativeSheetDetent.fraction(1);

  final double? fraction;
  final double? height;
  final bool isContent;

  /// Resolved against the large detent's height ([content] resolves to it
  /// until measured).
  double resolve(double largeHeight) =>
      isContent ? largeHeight : math.min(largeHeight, height ?? largeHeight * fraction!);

  Map<String, Object?> _encode() => this == medium
      ? {'type': 'medium'}
      : this == large
      ? {'type': 'large'}
      : isContent
      ? {'type': 'content'}
      : height != null
      ? {'type': 'height', 'value': height}
      : {'type': 'fraction', 'value': fraction};

  @override
  bool operator ==(Object other) =>
      other is NativeSheetDetent &&
      other.fraction == fraction &&
      other.height == height &&
      other.isContent == isContent;

  @override
  int get hashCode => Object.hash(fraction, height, isContent);
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
/// receive it when presented), and return a result with [NativeSheet.close].
///
/// With [keepAlive], closing the sheet hides it instead of ending its engine:
/// the sheet's app keeps running (timers, network, audio; no frames are drawn
/// while hidden), and the next [showNativeSheet] at the same [entrypoint]
/// presents the same app again, state intact. Inside, [NativeSheet.shown]
/// says whether it's on screen and [NativeSheet.presented] brings each new
/// payload. [NativeSheet.release] frees it. Ignored with [arguments], and
/// where native sheets aren't used. Veneer works inside it: a
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
  bool keepAlive = false,
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
        'retain': keepAlive,
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
  unawaited(VeneerBridge.instance.refreshSheetShown());
  runApp(_SheetScrollEdgeReporter(child: app));
}

/// The entrypoint of the idle engine every native sheet's engine is spawned
/// from (see `NativeSheetPresenter.anchor`).
@pragma('vm:entry-point')
void veneerSheetAnchor() {}

/// The content of a native sheet with a [NativeSheetDetent.content] detent:
/// measures [child]'s natural height and has the UIKit sheet follow it (the
/// sheet slides up at that height). Elsewhere — the Flutter sheet measures
/// its content itself — it's just [child].
class NativeSheetContent extends StatelessWidget {
  const NativeSheetContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!NativeSheet.isNativeSheet) return child;
    final mq = MediaQuery.of(context);
    final display = View.of(context).display;
    // The view is the sheet, so its size would cap the content at the
    // sheet's current height: measure against the screen instead. UIKit adds
    // the bottom safe area to a detent's height itself.
    return ValueListenableBuilder<double?>(
      valueListenable: VeneerBridge.instance.sheetMaximumHeight,
      builder: (context, maximum, child) => _ContentSizedBox(
        maxHeight: display.size.height / display.devicePixelRatio,
        scrollsFrom: maximum == null ? null : maximum + mq.viewPadding.bottom,
        onMeasured: (height) => VeneerBridge.instance.setSheetContentHeight(height - mq.viewPadding.bottom),
        child: child,
      ),
      child: child,
    );
  }
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

  /// Inside a sheet: asks the app that presented it, which answers through
  /// [setRequestHandler] — e.g. for a fresh credential, or data only the app
  /// holds. A native sheet's engine shares no memory with the app, so this
  /// is how it reaches the app while open. In the Flutter fallback the sheet
  /// runs in the app's engine and the handler is called directly.
  ///
  /// [arguments] and the answer are values the standard message codec
  /// carries. Throws a [PlatformException] when the app has no handler or
  /// the handler fails (`no_handler`, `not_shown` for a sheet that's no
  /// longer showing). A sheet presented from inside a sheet asks that
  /// sheet's engine, which can forward with a handler of its own.
  static Future<Object?> request(String name, [Object? arguments]) async {
    final bridge = VeneerBridge.instance;
    if (bridge.isSheetEngine) return bridge.sheetRequest(name, arguments);
    final handler = bridge.sheetRequestHandler;
    if (handler == null) {
      throw PlatformException(code: 'no_handler', message: 'No NativeSheet.setRequestHandler for "$name"');
    }
    return handler(name, arguments);
  }

  /// In the app: answers [request]s from the sheets it presents. One handler
  /// serves every sheet; switch on the request's name. Null removes it.
  static void setRequestHandler(SheetRequestHandler? handler) => VeneerBridge.instance.sheetRequestHandler = handler;

  /// Inside a native sheet: whether it's on screen. Turns false when a
  /// kept-alive sheet ([showNativeSheet]'s `keepAlive`) closes, while its app
  /// keeps running, and true again when it's presented. Always false outside
  /// native sheets.
  static ValueListenable<bool> get shown => VeneerBridge.instance.sheetShown;

  /// Inside a native sheet: the payload of each presentation as the sheet
  /// comes up — for a kept-alive sheet, every reopening. Empty outside
  /// native sheets.
  static Stream<Object?> get presented => VeneerBridge.instance.sheetPresentations;

  /// From the app: frees the kept-alive sheet engine at [entrypoint], ending
  /// its app — immediately when it's hidden, or once its sheet closes. The
  /// next [showNativeSheet] there starts a fresh one. Does nothing where
  /// native sheets aren't available.
  static Future<void> release(String entrypoint, {String? libraryUri}) async {
    if (!VeneerBridge.instance.isSupported) return;
    await VeneerBridge.instance.releaseSheet(entrypoint, libraryUri: libraryUri);
  }
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

  /// A solid surface at every detent. Without it the sheet is white (light)
  /// or #1C1C1E (dark), translucent below the large detent as in iOS 26.
  /// A [CupertinoDynamicColor] follows the theme's brightness while the
  /// sheet is open.
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

  /// Whether the route above is another sheet: this one then steps back
  /// behind it (see [_NativeSheetState]) rather than receding like a page.
  bool _coveredBySheet = false;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    // Kept through the sheet above's dismissal, which ends with no next route.
    if (nextRoute != null) _coveredBySheet = nextRoute is NativeSheetRoute;
  }

  /// The page behind recedes — scales back with rounded corners — while the
  /// sheet is at its large detent, as in UIKit. A sheet behind steps back on
  /// its own.
  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      (context, animation, secondaryAnimation, allowSnapshotting, child) => AnimatedBuilder(
        animation: Listenable.merge([secondaryAnimation, _recede]),
        builder: (context, child) {
          if (ModalRoute.of(context) is NativeSheetRoute) return child!;
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

  /// Under another sheet, UIKit's sheet shrinks and lifts so its top edge
  /// peeks above the new one, its grabber hidden.
  static const _stackedShrink = 0.06;
  static const _stackedLift = 10.0;

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

  /// The height the sheet had when the keyboard began to rise: until the
  /// sheet reaches its largest detent it grows at least with the keyboard,
  /// so its content is never squeezed between the two.
  double? _keyboardBase;
  double _keyboard = 0;
  NativeSheetDetent? _reported;
  List<double> _heights = const [];
  double _large = 0;

  /// The content's own height, for a [NativeSheetDetent.content] detent.
  double? _contentHeight;
  double _lastKeyboard = 0;

  bool get _sizesToContent => _route.detents.any((d) => d.isContent);

  double _resolve(NativeSheetDetent d) =>
      d.isContent && _contentHeight != null ? math.min(_contentHeight!, _large) : d.resolve(_large);

  void _recomputeHeights() => _heights = [for (final d in _route.detents) _resolve(d)]..sort();

  /// The content was measured (or changed height): a sheet resting at the
  /// content detent follows it — at once while the keyboard moves (the
  /// content pads for it frame by frame), on the sheet's spring otherwise.
  void _contentMeasured(double height) {
    if (!mounted || (_contentHeight != null && (_contentHeight! - height).abs() < 0.5)) return;
    final first = _contentHeight == null;
    final restingOnContent = _reported?.isContent ?? false;
    _contentHeight = height;
    _recomputeHeights();
    if (_dragging) return setState(() {});
    final target = _resolve(_reported ?? _route.detents.first);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardMoving = keyboard != _lastKeyboard;
    _lastKeyboard = keyboard;
    if (first || keyboardMoving || !restingOnContent) {
      if (first || keyboardMoving) _height.value = target;
      setState(() {});
    } else {
      _settleTo(target, 0);
    }
  }

  NativeSheetRoute<Object?> get _route => widget.route;

  @override
  void initState() {
    super.initState();
    _height.addListener(_changed);
    _present.addListener(_changed);
    _route.secondaryAnimation?.addListener(_changed);
  }

  /// 0 on top, 1 fully stepped back behind a sheet above.
  double get _stacked =>
      _route._coveredBySheet ? Curves.easeOut.transform((_route.secondaryAnimation?.value ?? 0).clamp(0.0, 1.0)) : 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.of(context);
    // The large detent leaves the status bar and a sliver of the page behind.
    _large = mq.size.height - mq.padding.top - 10;
    _recomputeHeights();
    if (!_initialized) {
      _initialized = true;
      final initial = _resolve(_route.initialDetent ?? _route.detents.first);
      _height.value = initial;
      _reported = _detentFor(initial);
      WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
    }
    // UIKit moves the sheet to its largest detent for the keyboard.
    _keyboard = mq.viewInsets.bottom;
    final keyboard = _keyboard > 0;
    if (keyboard && !_keyboardExpanded && _height.value < _heights.last - 0.5) {
      _keyboardExpanded = true;
      _keyboardBase = _height.value;
      WidgetsBinding.instance.addPostFrameCallback((_) => _settleTo(_heights.last, 0));
    } else if (!keyboard) {
      _keyboardExpanded = false;
      _keyboardBase = null;
    }
  }

  @override
  void dispose() {
    _route.secondaryAnimation?.removeListener(_changed);
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

  double get _visibleHeight {
    final base = _keyboardBase;
    if (base == null || _dragging) return _height.value;
    return math.max(_height.value, math.min(_max, base + _keyboard));
  }

  double get _min => _heights.first;
  double get _max => _heights.last;

  /// 0 at or below the detent under large, 1 at large.
  double get _largeness {
    // Only the large detent meets the edges; shorter sheets float.
    if (_max < _large - 0.5) return 0;
    final below = _heights.length > 1 ? _heights[_heights.length - 2] : _max * 0.5;
    if (_max - below < 1) return _max >= _large - 0.5 ? 1 : 0;
    return ((_visibleHeight - below) / (_max - below)).clamp(0.0, 1.0);
  }

  NativeSheetDetent _detentFor(double height) {
    var best = _route.detents.first;
    var distance = double.infinity;
    for (final d in _route.detents) {
      final delta = (_resolve(d) - height).abs();
      if (delta < distance) {
        distance = delta;
        best = d;
      }
    }
    return best;
  }

  // MARK: Dragging

  void _dragStart() {
    _height.value = _visibleHeight;
    _dragging = true;
    // Dragging the sheet puts the keyboard away, so the content isn't left
    // squeezed between a shrinking sheet and the keyboard.
    if (MediaQuery.viewInsetsOf(context).bottom > 0) FocusManager.instance.primaryFocus?.unfocus();
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
    final height = math.max(0.0, _visibleHeight);
    final displacement = (1 - _present.value) * (height + inset + 24) + _drag;

    final undimmed = _route.largestUndimmedDetent == null ? null : _resolve(_route.largestUndimmedDetent!);
    final dimLevel = undimmed == null
        ? 1.0
        : _heights.where((h) => h > undimmed + 0.5).isEmpty
        ? 0.0
        : ((height - undimmed) / (_heights.firstWhere((h) => h > undimmed + 0.5) - undimmed)).clamp(0.0, 1.0);
    final dim = dimLevel * _present.value * (1 - (_drag / math.max(1, _min)).clamp(0.0, 1.0));

    final dark = style.dark;
    // A translucent material while floating, opaque once it meets the edges;
    // a colour the app chose stays solid, so content never shows the page
    // behind through it, nor bands under the bar's edge fade.
    final chosen = switch (_route.backgroundColor) {
      final c? => Color(CupertinoDynamicColor.resolve(c, context).toARGB32()),
      null => null,
    };
    final surface =
        chosen ??
        (dark ? const Color(0xFF1C1C1E) : Colors.white).withValues(alpha: lerpDouble(dark ? 0.78 : 0.82, 1, t));
    final grabber = _route.showGrabber ?? _route.detents.length > 1;
    final stacked = _stacked;

    final radius = BorderRadius.vertical(top: Radius.circular(topRadius), bottom: Radius.circular(bottomRadius));

    // Content starts below the grabber, like a UIKit sheet's safe area.
    final contentTop = grabber ? 14.0 : 6.0;
    Widget content = MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(top: contentTop, bottom: math.max(0, mq.padding.bottom - inset)),
        viewPadding: mq.viewPadding.copyWith(top: contentTop, bottom: math.max(0, mq.viewPadding.bottom - inset)),
        // The sheet's own inset already lifts its content off the bottom.
        viewInsets: mq.viewInsets.copyWith(bottom: math.max(0, mq.viewInsets.bottom - inset)),
      ),
      child: ScrollConfiguration(
        // Clamping, so content at its edge reports overscroll to the sheet.
        behavior: ScrollConfiguration.of(context).copyWith(physics: const ClampingScrollPhysics()),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          // Native views can't follow a Flutter-drawn sheet: Veneer widgets
          // inside use their Flutter replicas.
          // Like Flutter's own sheets: text fields, ink and list tiles in the
          // content need a Material.
          child: VeneerFallbackScope(
            // The sheet's surface is the content's background: scaffolds and
            // the bar's edge fade blend into it rather than the page's colour.
            child: Theme(
              data: Theme.of(context).copyWith(scaffoldBackgroundColor: surface),
              child: Material(
                type: MaterialType.transparency,
                child: Builder(builder: _route.builder),
              ),
            ),
          ),
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
          child: Transform.translate(
            offset: Offset(0, -_stackedLift * stacked),
            child: Transform.scale(
              scale: 1 - _stackedShrink * stacked,
              alignment: Alignment.topCenter,
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
                        Positioned.fill(
                          child: _sizesToContent
                              ? _ContentSizedBox(maxHeight: _large, onMeasured: _contentMeasured, child: content)
                              : content,
                        ),
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
                              child: Opacity(
                                opacity: 1 - stacked,
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
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // The page behind recedes onto black: like UIKit, the status bar
        // turns light over it. Last, so adding it never remounts the sheet.
        if (t * _present.value >= 0.5)
          const Positioned.fill(
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Color(0x00000000),
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
              child: SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}

/// Lays its child out at its own height (up to [maxHeight]) to measure it
/// for a [NativeSheetDetent.content] detent, then again to fill the sheet
/// when the sheet is taller (a larger detent, or the rubber band).
class _ContentSizedBox extends SingleChildRenderObjectWidget {
  const _ContentSizedBox({required this.maxHeight, required this.onMeasured, this.scrollsFrom, super.child});

  final double maxHeight;

  /// The tallest the sheet gets ([maxHeight] when null): content that
  /// reaches it is held to the sheet and scrolls; shorter content is only
  /// waiting for the sheet to grow to it, and keeps its height meanwhile.
  final double? scrollsFrom;
  final ValueChanged<double> onMeasured;

  @override
  _RenderContentSizedBox createRenderObject(BuildContext context) =>
      _RenderContentSizedBox(maxHeight, scrollsFrom ?? maxHeight, onMeasured);

  @override
  void updateRenderObject(BuildContext context, _RenderContentSizedBox renderObject) => renderObject
    ..maxHeight = maxHeight
    ..scrollsFrom = scrollsFrom ?? maxHeight
    ..onMeasured = onMeasured;
}

class _RenderContentSizedBox extends RenderProxyBox {
  _RenderContentSizedBox(this._maxHeight, this._scrollsFrom, this.onMeasured);

  double _scrollsFrom;
  set scrollsFrom(double value) {
    if (value == _scrollsFrom) return;
    _scrollsFrom = value;
    markNeedsLayout();
  }

  double _maxHeight;
  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  ValueChanged<double> onMeasured;
  double? _reported;

  /// Keeps the second layout's constraints loose (see [performLayout]).
  static const _slack = 0.01;

  @override
  void performLayout() {
    final child = this.child;
    size = constraints.biggest;
    if (child == null) return;
    child.layout(
      BoxConstraints(minWidth: size.width, maxWidth: size.width, maxHeight: _maxHeight),
      parentUsesSize: true,
    );
    final natural = child.size.height;
    // Then laid out at the sheet's own height: stretched to fill a taller
    // sheet, or held to a shorter one that can't grow to it (the large
    // detent is shorter than the screen it was measured against) so scroll
    // views end at its bottom. Content the sheet is still growing to keeps
    // its height, clipped, rather than being squeezed for a frame. Never
    // with tight constraints: those would make the child a relayout
    // boundary, and its later changes of height would never reach this box.
    final heldToSheet = size.height < natural - 0.5 && natural >= _scrollsFrom - 0.5;
    if (size.height > natural + 0.5 || heldToSheet) {
      child.layout(
        BoxConstraints(
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height + _slack,
        ),
        parentUsesSize: true,
      );
    }
    if (_reported == null || (_reported! - natural).abs() >= 0.5) {
      _reported = natural;
      // Heights feed the sheet's layout, so report after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => onMeasured(natural));
    }
  }
}
