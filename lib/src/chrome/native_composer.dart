import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoSheetRoute;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/fallback_scope.dart';
import '../core/fallback_style.dart';
import '../core/native_icon.dart';
import '../core/native_menu.dart';
import '../core/veneer_bridge.dart';
import '../glass/glass_coordinator.dart';

part 'native_prompt_composer.dart';

/// A button in a native composer.
@immutable
class NativeComposerButton {
  const NativeComposerButton({required this.icon, this.title, this.onPressed, this.menu, this.prominent = false});

  final NativeIcon icon;

  /// VoiceOver label.
  final String? title;
  final VoidCallback? onPressed;

  /// Tapping opens this menu (a native `UIMenu`) instead of [onPressed].
  final List<NativeMenuItem>? menu;

  /// For side actions of a [NativePromptComposer]: glass tinted with the
  /// label colour (white in dark mode), like an End button.
  final bool prominent;

  Map<String, Object?> _encode(String id, Map<String, VoidCallback?> handlers) {
    handlers[id] = onPressed;
    return {
      'id': id,
      'icon': icon.encode(),
      'title': title,
      'prominent': prominent,
      'menu': encodeMenu(id, menu, handlers),
    };
  }
}

/// Where a controller's commands go: the native composer or the Flutter
/// fallback.
abstract class _ComposerBackend {
  void setText(String text);
  void focus();
  void unfocus();
}

class _NativeBackend implements _ComposerBackend {
  const _NativeBackend();

  @override
  void setText(String text) => VeneerBridge.instance.composerCommand('setText', text: text);

  @override
  void focus() => VeneerBridge.instance.composerCommand('focus');

  @override
  void unfocus() => VeneerBridge.instance.composerCommand('unfocus');
}

/// Reads and drives a composer ([NativeComposer], [NativePromptComposer]):
/// its text and keyboard focus. The same controller works with the native
/// composers and their Flutter fallbacks.
class NativeComposerController extends ChangeNotifier {
  NativeComposerController({String text = ''}) : _text = text; // ignore: prefer_initializing_formals

  String _text;
  bool _hasFocus = false;
  _ComposerBackend _backend = const _NativeBackend();

  String get text => _text;

  set text(String value) {
    if (value == _text) return;
    _text = value;
    _backend.setText(value);
    notifyListeners();
  }

  /// Whether the composer's text field has the keyboard.
  bool get hasFocus => _hasFocus;

  void focus() => _backend.focus();

  void unfocus() => _backend.unfocus();

  void clear() => text = '';

  void _nativeText(String value) {
    if (value == _text) return;
    _text = value;
    notifyListeners();
  }

  void _nativeFocus(bool value) {
    if (value == _hasFocus) return;
    _hasFocus = value;
    notifyListeners();
  }
}

/// What both composers share on the native path: one native composer view
/// at a time (the most recently visible composer's), its config sent only
/// when it changes, events routed back, and [child] padded for the space the
/// composer takes above the keyboard or tab bar — animated with the native
/// morph — with the keyboard inset consumed so an inner `Scaffold` doesn't
/// also resize.
abstract class _ComposerHostState<W extends StatefulWidget> extends State<W> {
  static State? _active;
  static String? _lastSent;

  bool _visible = false;
  bool _native = false;
  double _height = 0;
  Duration _duration = Duration.zero;
  NativeComposerController? _ownController;

  /// The native view class: `card` or `prompt`.
  String get _style;
  NativeComposerController? get _widgetController;
  Widget get _child;
  bool get _clearOnSend;
  bool get _interactiveDismissal;
  ValueChanged<String>? get _onSend;
  ValueChanged<String>? get _onChanged;
  ValueChanged<String>? get _onAttachmentRemoved => null;

  /// Style-specific config; registers button callbacks in [handlers].
  Map<String, Object?> _encode(Map<String, VoidCallback?> handlers);

  Widget _buildFallback(NativeComposerController controller);

  NativeComposerController get _controller => _widgetController ?? (_ownController ??= NativeComposerController());
  VeneerBridge get _bridge => VeneerBridge.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh(resend: true);
  }

  /// Visibility is checked against the live route, not a cached flag: a page
  /// covered by a new route can rebuild before it hears it's no longer
  /// current, and must not take the native view back.
  void _refresh({bool resend = false}) {
    _native = useNativeLayer(context);
    if (!_native) return;
    final visible = Visibility.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    if (visible != _visible) {
      _visible = visible;
      _push();
    } else if (resend && _visible) {
      _push();
    }
  }

  void _push() {
    if (!_native) return;
    if (_visible) {
      _active = this;
    } else if (_active != this) {
      return; // another composer owns the native view
    }
    final handlers = <String, VoidCallback?>{};
    final config = <String, Object?>{
      'style': _style,
      'hidden': !_visible,
      ..._encode(handlers),
      'clearOnSend': _clearOnSend,
      'interactiveDismissal': _interactiveDismissal,
    };
    final handlerSet = VeneerComposerHandlers(
      onButton: (id) => handlers[id]?.call(),
      onText: (text) {
        _controller._nativeText(text);
        _onChanged?.call(text);
      },
      onFocus: _controller._nativeFocus,
      onSend: (text) {
        if (_clearOnSend) _controller._nativeText('');
        _onSend?.call(text);
      },
      onLayout: (height, duration) {
        if (!mounted) return;
        setState(() {
          _height = height;
          _duration = duration;
        });
      },
      onAttachmentRemoved: (id) => _onAttachmentRemoved?.call(id),
    );
    // Pages rebuild every frame while the keyboard animates; only send real
    // changes. Callbacks are refreshed locally either way.
    final encoded = jsonEncode(config);
    if (encoded == _lastSent) {
      _bridge.updateComposerHandlers(handlerSet);
      return;
    }
    final firstShow = _lastSent == null;
    _lastSent = encoded;
    _bridge.setComposer(config, handlerSet);
    if (firstShow && _controller.text.isNotEmpty) _bridge.composerCommand('setText', text: _controller.text);
  }

  @override
  void dispose() {
    if (_active == this) {
      _active = null;
      _lastSent = null;
      _bridge.removeComposer();
    }
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_native) return _buildFallback(_controller);
    final mq = MediaQuery.of(context);
    // The composer sits above whichever is higher: the keyboard (animated by
    // Flutter from the same system notifications) or the tab bar.
    final base = math.max(mq.viewInsets.bottom, mq.padding.bottom);
    final padded = TweenAnimationBuilder<double>(
      tween: Tween(end: _visible ? _height : 0),
      duration: _duration,
      curve: Curves.easeOutCubic,
      builder: (context, height, child) => MediaQuery(
        data: mq.copyWith(
          padding: mq.padding.copyWith(bottom: base + height),
          viewPadding: mq.viewPadding.copyWith(bottom: math.max(mq.viewPadding.bottom, base + height)),
          viewInsets: mq.viewInsets.copyWith(bottom: 0),
        ),
        child: child!,
      ),
      child: _child,
    );
    // The native composer follows this widget's bottom edge frame by frame,
    // so it moves with the page: a sheet sliding up or dragged away, a
    // route sliding in.
    return _ComposerHostAnchor(active: _visible, child: padded);
  }
}

class _ComposerHostAnchor extends SingleChildRenderObjectWidget {
  const _ComposerHostAnchor({required this.active, super.child});

  final bool active;

  @override
  _RenderComposerHost createRenderObject(BuildContext context) => _RenderComposerHost(active, ModalRoute.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderComposerHost renderObject) => renderObject
    ..route = ModalRoute.of(context)
    ..active = active;
}

/// Measures how far the composer's page has moved from where it rests, for
/// the native composer to follow.
///
/// The rest position is recorded whenever the route is settled (not
/// animating, not being dragged, not covered). Before the first time — while
/// the route is still sliding in — it's estimated from layout, which ignores
/// transition transforms, plus the resting top gap of an iOS sheet.
class _RenderComposerHost extends RenderProxyBox {
  _RenderComposerHost(this._active, this.route) : _activation = _active ? ++_activations : 0;

  static int _activations = 0;

  ModalRoute<Object?>? route;
  Offset? _rest;

  /// When this composer last became visible; the latest one wins.
  int _activation;

  bool _active;
  set active(bool value) {
    if (value == _active) return;
    _active = value;
    if (value) _activation = ++_activations;
    _sync();
  }

  void _sync() {
    final coordinator = GlassCoordinator.instance;
    if (_active && attached) {
      coordinator.setComposerHost(this, _activation, _offsetFromRest);
    } else {
      coordinator.clearComposerHost(this);
    }
  }

  Offset _offsetFromRest() {
    if (!attached || !hasSize) return Offset.zero;
    final position = MatrixUtils.transformPoint(getTransformTo(null), Offset.zero);
    final route = this.route;
    final settled =
        route == null ||
        (route.animation?.status == AnimationStatus.completed &&
            (route.secondaryAnimation?.status ?? AnimationStatus.dismissed) == AnimationStatus.dismissed &&
            !(route.navigator?.userGestureInProgress ?? false));
    if (settled) _rest = position;
    return position - (_rest ?? _estimatedRest());
  }

  Offset _estimatedRest() {
    var offset = Offset.zero;
    RenderObject node = this;
    for (var ancestor = parent; ancestor != null; ancestor = ancestor.parent) {
      final data = node.parentData;
      if (data is BoxParentData) offset += data.offset;
      node = ancestor;
    }
    if (route case final CupertinoSheetRoute<Object?> sheet) {
      final screen = node is RenderView ? node.size.height : size.height;
      offset += Offset(0, sheet.topGap * screen);
    }
    return offset;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _sync();
  }

  @override
  void detach() {
    GlassCoordinator.instance.clearComposerHost(this);
    super.detach();
  }
}

/// A message composer: native (UIKit) on iOS 26, a Flutter replica with the
/// same layout elsewhere.
///
/// Put it in a `Scaffold(resizeToAvoidBottomInset: false)`: it handles the
/// keyboard itself, on both paths.
///
/// Native, it's laid out and animated by UIKit.
///
/// Idle, it's a 44 pt Liquid Glass capsule above the tab bar: [leading]
/// button, [placeholder], [idleAction]. Focused, it morphs into an expanded
/// card 9 pt above the keyboard, with the text on top and a toolbar row of
/// [leading], [toolbar] buttons and a send button — inside the keyboard's own
/// animation, so the card and keyboard move as one. Everything, including the
/// text view, is UIKit.
///
/// [child] (typically a reversed chat `ListView`) gets bottom padding for the
/// space the composer takes above the keyboard or tab bar, animated with the
/// morph, and the keyboard inset is consumed here so an inner `Scaffold`
/// doesn't also resize.
///
/// One composer ([NativeComposer] or [NativePromptComposer]) is shown at a
/// time, while its page is visible.
class NativeComposer extends StatefulWidget {
  const NativeComposer({
    super.key,
    this.controller,
    this.placeholder,
    this.leading,
    this.idleAction,
    this.toolbar = const [],
    this.sendIcon,
    this.onSend,
    this.onChanged,
    this.tintColor,
    this.maxLines = 6,
    this.clearOnSend = true,
    this.interactiveKeyboardDismissal = true,
    required this.child,
  });

  final NativeComposerController? controller;
  final String? placeholder;

  /// The circular glass button at the leading edge (e.g. attach "+").
  final NativeComposerButton? leading;

  /// Shown at the trailing edge while idle (e.g. voice message).
  final NativeComposerButton? idleAction;

  /// Shown in the expanded card's toolbar row, after [leading].
  final List<NativeComposerButton> toolbar;

  /// Defaults to `paperplane.fill`; tinted with [tintColor] when there's text.
  final NativeIcon? sendIcon;
  final ValueChanged<String>? onSend;
  final ValueChanged<String>? onChanged;

  /// Caret and enabled send button colour.
  final Color? tintColor;

  /// Lines the text view grows to before scrolling.
  final int maxLines;

  /// Clear the text natively as soon as it's sent.
  final bool clearOnSend;

  /// Dragging Flutter content down pulls the keyboard with the finger, and
  /// it dismisses or snaps back on release — UIKit's own interactive
  /// dismissal (`keyboardDismissMode = .interactive`), with the composer
  /// riding on the keyboard. Flutter still receives the drag and scrolls.
  final bool interactiveKeyboardDismissal;

  final Widget child;

  @override
  State<NativeComposer> createState() => _NativeComposerState();
}

class _NativeComposerState extends _ComposerHostState<NativeComposer> {
  @override
  String get _style => 'card';

  @override
  NativeComposerController? get _widgetController => widget.controller;

  @override
  Widget get _child => widget.child;

  @override
  bool get _clearOnSend => widget.clearOnSend;

  @override
  bool get _interactiveDismissal => widget.interactiveKeyboardDismissal;

  @override
  ValueChanged<String>? get _onSend => widget.onSend;

  @override
  ValueChanged<String>? get _onChanged => widget.onChanged;

  @override
  Map<String, Object?> _encode(Map<String, VoidCallback?> handlers) => {
    'placeholder': widget.placeholder,
    'leading': widget.leading?._encode('leading', handlers),
    'idle': widget.idleAction?._encode('idle', handlers),
    'toolbar': [for (final (i, b) in widget.toolbar.indexed) b._encode('toolbar$i', handlers)],
    'sendIcon': widget.sendIcon?.encode(),
    'tintColor': widget.tintColor?.toARGB32(),
    'maxLines': widget.maxLines,
  };

  @override
  Widget _buildFallback(NativeComposerController controller) =>
      _FallbackComposer(composer: widget, controller: controller);
}

/// A fallback button: its menu, if any, opens the Flutter menu replica.
Widget _fallbackTap(NativeComposerButton b, {required Widget child, bool enabled = true}) => Semantics(
  button: true,
  label: b.title,
  excludeSemantics: true,
  child: Builder(
    builder: (context) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !enabled
          ? null
          : (b.menu?.isNotEmpty ?? false)
          ? () => showFallbackMenu(context, b.menu!)
          : b.onPressed,
      child: child,
    ),
  ),
);

/// Flutter replica of the native composer, for Android and iOS 15–25, with
/// the same geometry — solid instead of glass:
///
/// Idle: a 44 pt capsule, 20 pt margins, 9 pt above the tab bar; a 36 pt +
/// circle inset 4 pt, placeholder at 49 pt, idle action centred 22 pt from
/// the trailing edge.
/// Focused (keyboard showing): a card 8 pt from the screen edges, 9 pt above
/// the keyboard, text inset 12 pt, a 44 pt toolbar row with the + circle, icons
/// centred at 67 + 41n pt and send 25 pt from the edge; corner radius up to 28.
///
/// It floats over [NativeComposer.child], which gets bottom padding for it.
/// Its bottom follows Flutter's keyboard inset frame by frame, so it rides
/// the keyboard's own animation; size, radius and contents animate between
/// the two states.
class _FallbackComposer extends StatefulWidget {
  const _FallbackComposer({required this.composer, required this.controller});

  final NativeComposer composer;
  final NativeComposerController controller;

  @override
  State<_FallbackComposer> createState() => _FallbackComposerState();
}

class _FallbackComposerState extends State<_FallbackComposer> implements _ComposerBackend {
  late final TextEditingController _text = TextEditingController(text: widget.controller.text);
  final FocusNode _focus = FocusNode();

  static const _idleHeight = 44.0;
  static const _idleMargin = 20.0;
  static const _expandedMargin = 8.0;
  static const _gap = 9.0;
  static const _circle = 36.0;
  static const _row = 44.0;
  static const _textTop = 12.0;
  static const _textInset = 12.0;
  static const _toolbarFirstCenter = 67.0;
  static const _toolbarSpacing = 41.0;
  static const _sendTrailing = 25.0;
  static const _maxRadius = 28.0;
  static const _duration = Duration(milliseconds: 280);
  static const _curve = Curves.easeOutCubic;
  static const _textStyle = TextStyle(fontSize: 17, height: 22 / 17);

  NativeComposer get _c => widget.composer;

  @override
  void initState() {
    super.initState();
    widget.controller._backend = this;
    _text.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_FallbackComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._backend = const _NativeBackend();
      widget.controller._backend = this;
    }
  }

  void _onText() {
    widget.controller._nativeText(_text.text);
    _c.onChanged?.call(_text.text);
    setState(() {});
  }

  void _onFocus() {
    widget.controller._nativeFocus(_focus.hasFocus);
    setState(() {});
  }

  @override
  void setText(String text) {
    if (_text.text != text) _text.text = text;
  }

  @override
  void focus() => _focus.requestFocus();

  @override
  void unfocus() => _focus.unfocus();

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    _c.onSend?.call(text);
    if (_c.clearOnSend) _text.clear();
  }

  @override
  void dispose() {
    if (widget.controller._backend == this) widget.controller._backend = const _NativeBackend();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Text block height for [width]: one 22 pt line plus 11 pt above and
  /// below (44 pt), growing per line up to [NativeComposer.maxLines].
  double _textHeight(double width) {
    final painter = TextPainter(
      text: TextSpan(text: _text.text.isEmpty ? ' ' : _text.text, style: _textStyle),
      textDirection: Directionality.of(context),
      maxLines: _c.maxLines,
    )..layout(maxWidth: math.max(1, width));
    final lines = math.max(1, (painter.height / 22).round());
    painter.dispose();
    return 22.0 * lines + 22;
  }

  Widget _iconButton(NativeComposerButton b, Color color) => _fallbackTap(
    b,
    child: SizedBox(
      width: _row,
      height: _row,
      child: Center(child: NativeIconView(b.icon, size: 22, color: color)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final style = VeneerFallbackStyle.of(context);
    final accent = _c.tintColor ?? style.accent;
    final keyboard = mq.viewInsets.bottom;
    final expanded = _focus.hasFocus && keyboard > 0;
    final base = math.max(keyboard, mq.padding.bottom);

    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = expanded ? _expandedMargin : _idleMargin;
        final width = constraints.maxWidth - 2 * margin;
        final textH = _textHeight(width - 2 * _textInset);
        final height = expanded ? _textTop + textH + _row + 4 : _idleHeight;
        final rowTop = height - _row - 4;
        final hasLeading = _c.leading != null;
        final hasText = _text.text.trim().isNotEmpty;

        final card = AnimatedContainer(
          duration: _duration,
          curve: _curve,
          height: height,
          decoration: style.surfaceDecoration(radius: BorderRadius.circular(math.min(height / 2, _maxRadius))),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Text: beside the + when idle, full width on top when expanded.
              AnimatedPositioned(
                duration: _duration,
                curve: _curve,
                left: expanded ? _textInset : (hasLeading ? 4 + _circle + 9 : 16),
                right: expanded ? _textInset : (_c.idleAction != null ? _row : 16),
                top: expanded ? _textTop : 0,
                height: expanded ? textH : _idleHeight,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: expanded ? _c.maxLines : 1,
                    cursorColor: accent,
                    textCapitalization: TextCapitalization.sentences,
                    style: _textStyle.copyWith(color: style.label),
                    decoration: InputDecoration.collapsed(
                      hintText: _c.placeholder,
                      hintStyle: _textStyle.copyWith(color: style.placeholder),
                    ).copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 11), isDense: true),
                  ),
                ),
              ),
              if (_c.leading case final leading?)
                AnimatedPositioned(
                  duration: _duration,
                  curve: _curve,
                  left: expanded ? _expandedMargin : 4,
                  top: expanded ? rowTop + (_row - _circle) / 2 : (_idleHeight - _circle) / 2,
                  width: _circle,
                  height: _circle,
                  child: _fallbackTap(
                    leading,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: style.innerSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: style.border, width: 0.5),
                      ),
                      child: Center(child: NativeIconView(leading.icon, size: 20, color: style.label)),
                    ),
                  ),
                ),
              if (_c.idleAction case final idle?)
                AnimatedPositioned(
                  duration: _duration,
                  curve: _curve,
                  right: 0,
                  top: expanded ? rowTop : 0,
                  child: IgnorePointer(
                    ignoring: expanded,
                    child: AnimatedOpacity(
                      duration: _duration,
                      opacity: expanded ? 0 : 1,
                      child: _iconButton(idle, style.secondaryLabel),
                    ),
                  ),
                ),
              // Toolbar and send wait in their expanded spots, faded out.
              for (final (i, b) in _c.toolbar.indexed)
                AnimatedPositioned(
                  duration: _duration,
                  curve: _curve,
                  left: _toolbarFirstCenter + i * _toolbarSpacing - _row / 2,
                  top: math.max(0, rowTop),
                  child: IgnorePointer(
                    ignoring: !expanded,
                    child: AnimatedOpacity(
                      duration: _duration,
                      opacity: expanded ? 1 : 0,
                      child: _iconButton(b, style.label),
                    ),
                  ),
                ),
              AnimatedPositioned(
                duration: _duration,
                curve: _curve,
                right: _sendTrailing - _row / 2,
                top: math.max(0, rowTop),
                child: IgnorePointer(
                  ignoring: !expanded,
                  child: AnimatedOpacity(
                    duration: _duration,
                    opacity: expanded ? 1 : 0,
                    child: Semantics(
                      button: true,
                      label: 'Send',
                      enabled: hasText,
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: hasText ? _send : null,
                        child: SizedBox(
                          width: _row,
                          height: _row,
                          child: Center(
                            child: NativeIconView(
                              _c.sendIcon ?? const NativeIcon.symbol('paperplane.fill'),
                              size: 22,
                              color: hasText ? accent : style.disabled,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        return Stack(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: height + _gap),
              duration: _duration,
              curve: _curve,
              builder: (context, occupied, child) => MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(bottom: base + occupied),
                  viewPadding: mq.viewPadding.copyWith(bottom: math.max(mq.viewPadding.bottom, base + occupied)),
                  viewInsets: mq.viewInsets.copyWith(bottom: 0),
                ),
                child: child!,
              ),
              child: _c.child,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: base + _gap,
              child: AnimatedPadding(
                duration: _duration,
                curve: _curve,
                padding: EdgeInsets.symmetric(horizontal: margin),
                child: Material(
                  type: MaterialType.transparency,
                  child: GestureDetector(
                    // Like the native capsule: tapping anywhere on it focuses.
                    onTap: expanded ? null : _focus.requestFocus,
                    child: card,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
