import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fallback_scope.dart';
import '../core/fallback_style.dart';
import '../core/route_visibility.dart';
import '../core/veneer_bridge.dart';
import '../glass/native_search_field.dart';

/// UIKit's own search field at the bottom of the screen, as Settings and
/// Passwords show it on iOS 26: a `UISearchController` integrated into the
/// toolbar. Native, everything about it is UIKit's — the field, its
/// dictation microphone (system dictation, with its own pill, sounds and
/// languages), the clear button, the close button while searching, and the
/// ride on the keyboard. Elsewhere a Flutter replica: a search field and a
/// close button above the keyboard.
///
/// [child] (the results) fills the screen and gets bottom padding for the
/// space the bar takes, keyboard included, so its content can scroll
/// underneath and end above the bar. The keyboard inset is consumed here, so
/// an inner `Scaffold` doesn't also resize.
///
/// One search toolbar is shown at a time, while its page is visible. Use a
/// `GlobalKey<NativeSearchToolbarState>` to move the keyboard.
class NativeSearchToolbar extends StatefulWidget {
  const NativeSearchToolbar({
    super.key,
    required this.placeholder,
    required this.child,
    this.controller,
    this.autofocus = true,
    this.onChanged,
    this.onSubmitted,
    this.onFocusChanged,
    this.onClose,
    this.closeLabel,
  });

  final String placeholder;
  final Widget child;
  final TextEditingController? controller;

  /// Raise the keyboard when the bar first appears.
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<bool>? onFocusChanged;

  /// The close button was tapped; the bar has already left search mode.
  final VoidCallback? onClose;

  /// VoiceOver label of the replica's close button; UIKit labels its own.
  final String? closeLabel;

  @override
  State<NativeSearchToolbar> createState() => NativeSearchToolbarState();
}

class NativeSearchToolbarState extends State<NativeSearchToolbar> {
  static NativeSearchToolbarState? _active;

  static const _fallbackPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  static const _fallbackHeight = 44.0;
  static const _layoutDuration = Duration(milliseconds: 250);

  final _fallbackField = GlobalKey<NativeSearchFieldState>();
  TextEditingController? _ownController;
  bool _native = false;
  bool _visible = false;
  bool _focusRequested = false;
  double _bottom = 0;

  /// The text the native bar last reported or was last sent, so a controller
  /// change that came from UIKit isn't echoed back to it.
  String _nativeText = '';

  late final RouteChainWatcher _routes = RouteChainWatcher(() {
    if (mounted) _refresh();
  });

  TextEditingController get _controller => widget.controller ?? (_ownController ??= TextEditingController());
  VeneerBridge get _bridge => VeneerBridge.instance;

  /// Raises the keyboard in the field.
  void focus() {
    if (_native) {
      _bridge.searchToolbarCommand('focus');
    } else {
      _fallbackField.currentState?.focus();
    }
  }

  /// Dismisses the keyboard if the field holds it.
  void unfocus() {
    if (_native) {
      _bridge.searchToolbarCommand('unfocus');
    } else {
      _fallbackField.currentState?.unfocus();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routes.update(context);
    _refresh();
  }

  @override
  void didUpdateWidget(NativeSearchToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownController)?.removeListener(_onControllerChanged);
      _controller.addListener(_onControllerChanged);
    }
    _refresh(resend: oldWidget.placeholder != widget.placeholder);
  }

  /// Visibility is checked against the live route: while its page is
  /// covered the native bar is hidden, not removed, so it comes back as it
  /// was left.
  void _refresh({bool resend = false}) {
    _native = useNativeLayer(context);
    if (!_native) return;
    final visible = Visibility.of(context) && isRouteOnTop(context);
    if (visible != _visible || resend) {
      _visible = visible;
      _push();
    } else if (_active == this) {
      _bridge.updateSearchToolbarHandlers(_handlers);
    }
  }

  VeneerSearchToolbarHandlers get _handlers => VeneerSearchToolbarHandlers(
    onChanged: (text) {
      _nativeText = text;
      if (_controller.text != text) {
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      widget.onChanged?.call(text);
    },
    onSubmitted: (text) => widget.onSubmitted?.call(text),
    onFocusChanged: (focused) => widget.onFocusChanged?.call(focused),
    onClose: () => widget.onClose?.call(),
    onLayout: (bottom) {
      if (mounted && bottom != _bottom) setState(() => _bottom = bottom);
    },
  );

  Future<void> _push() async {
    if (!_visible && _active != this) return;
    _active = this;
    if (_bottom == 0 && _bridge.searchToolbarBottom > 0) _bottom = _bridge.searchToolbarBottom;
    final focus = _visible && widget.autofocus && !_focusRequested;
    if (focus) _focusRequested = true;
    _nativeText = _controller.text;
    await _bridge.setSearchToolbar({
      'placeholder': widget.placeholder,
      'text': _controller.text,
      'hidden': !_visible,
    }, _handlers);
    if (focus && _active == this) await _bridge.searchToolbarCommand('focus');
  }

  void _remove() {
    if (_active != this) return;
    _active = null;
    _bridge.removeSearchToolbar();
  }

  void _onControllerChanged() {
    if (!_native || !_visible || _controller.text == _nativeText) return;
    _nativeText = _controller.text;
    _bridge.searchToolbarCommand('setText', text: _nativeText);
  }

  @override
  void dispose() {
    _routes.dispose();
    _controller.removeListener(_onControllerChanged);
    _remove();
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (!_native) return _buildFallback(context, mq);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: _visible ? _bottom : 0),
      duration: _layoutDuration,
      curve: Curves.easeOutCubic,
      builder: (context, bottom, child) => MediaQuery(
        data: mq.copyWith(
          padding: mq.padding.copyWith(bottom: math.max(mq.padding.bottom, bottom)),
          viewPadding: mq.viewPadding.copyWith(bottom: math.max(mq.viewPadding.bottom, bottom)),
          viewInsets: mq.viewInsets.copyWith(bottom: 0),
        ),
        child: child!,
      ),
      child: widget.child,
    );
  }

  Widget _buildFallback(BuildContext context, MediaQueryData mq) {
    final style = VeneerFallbackStyle.of(context);
    final base = math.max(mq.viewInsets.bottom, mq.padding.bottom);
    final barHeight = _fallbackPadding.vertical + _fallbackHeight;
    return Stack(
      children: [
        Positioned.fill(
          child: MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(bottom: base + barHeight),
              viewPadding: mq.viewPadding.copyWith(bottom: math.max(mq.viewPadding.bottom, base + barHeight)),
              viewInsets: mq.viewInsets.copyWith(bottom: 0),
            ),
            child: widget.child,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: base,
          child: Padding(
            padding: _fallbackPadding,
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: _FallbackAutofocus(
                    enabled: widget.autofocus,
                    field: _fallbackField,
                    child: NativeSearchField(
                      key: _fallbackField,
                      placeholder: widget.placeholder,
                      controller: _controller,
                      height: _fallbackHeight,
                      onChanged: widget.onChanged,
                      onSubmitted: widget.onSubmitted,
                      onFocusChanged: widget.onFocusChanged,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: widget.closeLabel,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () {
                      _fallbackField.currentState?.unfocus();
                      widget.onClose?.call();
                    },
                    child: Container(
                      width: _fallbackHeight,
                      height: _fallbackHeight,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: style.surface,
                        border: Border.all(color: style.border),
                        boxShadow: style.shadows,
                      ),
                      child: Icon(Icons.close, size: 20, color: style.label),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Focuses the replica's field once, after its first frame.
class _FallbackAutofocus extends StatefulWidget {
  const _FallbackAutofocus({required this.enabled, required this.field, required this.child});

  final bool enabled;
  final GlobalKey<NativeSearchFieldState> field;
  final Widget child;

  @override
  State<_FallbackAutofocus> createState() => _FallbackAutofocusState();
}

class _FallbackAutofocusState extends State<_FallbackAutofocus> {
  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.field.currentState?.focus());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
