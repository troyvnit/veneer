import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/native_icon.dart';
import '../core/veneer_bridge.dart';

/// A button in the native composer.
@immutable
class NativeComposerButton {
  const NativeComposerButton({required this.icon, this.title, this.onPressed});

  final NativeIcon icon;

  /// VoiceOver label.
  final String? title;
  final VoidCallback? onPressed;
}

/// Reads and drives a [NativeComposer]: its text and keyboard focus.
class NativeComposerController extends ChangeNotifier {
  NativeComposerController({String text = ''}) : _text = text; // ignore: prefer_initializing_formals

  String _text;
  bool _hasFocus = false;

  String get text => _text;

  set text(String value) {
    if (value == _text) return;
    _text = value;
    VeneerBridge.instance.composerCommand('setText', text: value);
    notifyListeners();
  }

  /// Whether the composer's text view has the keyboard.
  bool get hasFocus => _hasFocus;

  void focus() => VeneerBridge.instance.composerCommand('focus');

  void unfocus() => VeneerBridge.instance.composerCommand('unfocus');

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

/// A native message composer, laid out and animated by UIKit.
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
/// One composer is shown at a time, while its page is visible.
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

  final Widget child;

  @override
  State<NativeComposer> createState() => _NativeComposerState();
}

class _NativeComposerState extends State<NativeComposer> {
  static _NativeComposerState? _active;
  static String? _lastSent;

  bool _visible = false;
  double _height = 0;
  Duration _duration = Duration.zero;
  NativeComposerController? _ownController;

  NativeComposerController get _controller => widget.controller ?? (_ownController ??= NativeComposerController());
  VeneerBridge get _bridge => VeneerBridge.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = Visibility.of(context) && (ModalRoute.isCurrentOf(context) ?? true);
    if (visible != _visible) {
      _visible = visible;
      _push();
    }
  }

  @override
  void didUpdateWidget(NativeComposer old) {
    super.didUpdateWidget(old);
    if (_visible) _push();
  }

  void _push() {
    if (_visible) {
      _active = this;
    } else if (_active != this) {
      return;
    }
    final handlers = <String, VoidCallback?>{};
    Map<String, Object?> button(String id, NativeComposerButton b) {
      handlers[id] = b.onPressed;
      return {'id': id, 'icon': b.icon.encode(), 'title': b.title};
    }

    final config = <String, Object?>{
      'hidden': !_visible,
      'placeholder': widget.placeholder,
      'leading': widget.leading == null ? null : button('leading', widget.leading!),
      'idle': widget.idleAction == null ? null : button('idle', widget.idleAction!),
      'toolbar': [for (final (i, b) in widget.toolbar.indexed) button('toolbar$i', b)],
      'sendIcon': widget.sendIcon?.encode(),
      'tintColor': widget.tintColor?.toARGB32(),
      'maxLines': widget.maxLines,
      'clearOnSend': widget.clearOnSend,
    };
    final handlerSet = VeneerComposerHandlers(
      onButton: (id) => handlers[id]?.call(),
      onText: (text) {
        _controller._nativeText(text);
        widget.onChanged?.call(text);
      },
      onFocus: _controller._nativeFocus,
      onSend: (text) {
        if (widget.clearOnSend) _controller._nativeText('');
        widget.onSend?.call(text);
      },
      onLayout: (height, duration) {
        if (!mounted) return;
        setState(() {
          _height = height;
          _duration = duration;
        });
      },
    );
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
    final mq = MediaQuery.of(context);
    // The composer sits above whichever is higher: the keyboard (animated by
    // Flutter from the same system notifications) or the tab bar.
    final base = math.max(mq.viewInsets.bottom, mq.padding.bottom);
    return TweenAnimationBuilder<double>(
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
      child: widget.child,
    );
  }
}
