part of 'native_composer.dart';

/// Something attached to a [NativePromptComposer]'s prompt: shown along the
/// top of the composer with a remove button.
///
/// Without a [title] it's a square image tile (a photo: pass
/// `NativeIcon.image`/`imageFile`, or a colour SVG, as [thumbnail]); with
/// one, a chip with a thumbnail, the title and [subtitle] (a file). With
/// [audio], a full-width voice clip row instead.
@immutable
class NativeComposerAttachment {
  const NativeComposerAttachment({
    required this.id,
    this.title,
    this.subtitle,
    this.thumbnail,
    this.loading = false,
    this.onRemove,
    this.onTap,
    this.audio,
  });

  final String id;
  final String? title;
  final String? subtitle;
  final NativeIcon? thumbnail;

  /// Still uploading or processing: dimmed, with a spinner.
  final bool loading;

  /// The remove button was tapped; drop the attachment from the list.
  final VoidCallback? onRemove;

  /// The attachment itself was tapped, e.g. to preview or play it. Null
  /// leaves the tile inert, so a tap on it focuses the prompt as before.
  /// On an [audio] row it's the play/pause button.
  final VoidCallback? onTap;

  /// Shows the attachment as a voice clip row: play/pause, waveform,
  /// duration and remove. The app plays the clip; this only draws it.
  final NativeComposerAudio? audio;

  Map<String, Object?> _encode() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'thumbnail': thumbnail?.encode(),
    'loading': loading,
    'tappable': onTap != null,
    'audio': audio?._encode(),
  };
}

/// How [NativePromptComposer.attachmentSummary] folds the attachments away
/// while the prompt isn't focused: one pill, `[📎 3]`, beside the buttons, so
/// the composer stays a single row; focusing shows the attachments again.
@immutable
class NativeComposerAttachmentSummary {
  const NativeComposerAttachmentSummary({this.icon, this.backgroundColor, this.foregroundColor});

  /// Defaults to `paperclip`.
  final NativeIcon? icon;

  /// Defaults to the quaternary system fill.
  final Color? backgroundColor;

  /// The icon and count; defaults to the label colour.
  final Color? foregroundColor;

  Map<String, Object?> _encode() => {
    'icon': icon?.encode(),
    'backgroundColor': backgroundColor?.toARGB32(),
    'foregroundColor': foregroundColor?.toARGB32(),
  };
}

/// A voice clip shown in a [NativeComposerAttachment] row, sized like the
/// tiles' strip: 56 pt tall, 8 pt from the composer's edges.
///
/// `[(play)  ▌▌▐▌▌▐▌▐▐▌…  0:10  ×]`: a filled circle in the composer's tint,
/// bars that fill with the tint as [progress] moves, the [duration] label
/// and a remove button. Rebuild with new values as playback moves; only
/// changes reach the native side.
@immutable
class NativeComposerAudio {
  const NativeComposerAudio({
    this.waveform = const [],
    this.progress = 0,
    this.playing = false,
    this.duration,
    this.playIcon,
    this.pauseIcon,
    this.removeIcon,
    this.backgroundColor,
    this.waveColor,
    this.labelColor,
  });

  /// Amplitudes from 0 to 1, resampled to the bars that fit. A hundred or so
  /// is plenty.
  final List<double> waveform;

  /// Played fraction, 0 to 1.
  final double progress;

  /// Shows [pauseIcon] instead of [playIcon].
  final bool playing;

  /// E.g. `0:10`.
  final String? duration;

  /// Default to `play.fill`, `pause.fill` and `xmark`.
  final NativeIcon? playIcon;
  final NativeIcon? pauseIcon;
  final NativeIcon? removeIcon;

  /// The row's fill; defaults to the quaternary system fill.
  final Color? backgroundColor;

  /// Unplayed bars; defaults to the tertiary label colour.
  final Color? waveColor;

  /// The duration and remove glyph; defaults to the label colour.
  final Color? labelColor;

  Map<String, Object?> _encode() => {
    'waveform': [for (final v in waveform) (v.clamp(0, 1) * 1000).round() / 1000],
    'progress': (progress.clamp(0, 1) * 1000).round() / 1000,
    'playing': playing,
    'duration': duration,
    'playIcon': playIcon?.encode(),
    'pauseIcon': pauseIcon?.encode(),
    'removeIcon': removeIcon?.encode(),
    'backgroundColor': backgroundColor?.toARGB32(),
    'waveColor': waveColor?.toARGB32(),
    'labelColor': labelColor?.toARGB32(),
  };
}

/// An assistant-style prompt composer: native (UIKit) on iOS 26, a Flutter
/// replica with the same layout elsewhere.
///
/// Put it in a `Scaffold(resizeToAvoidBottomInset: false)`: it handles the
/// keyboard itself, on both paths.
///
/// One Liquid Glass capsule, 48 pt:
/// `[leading  placeholder…     actions  (primary)]`. The filled circle at the
/// end is [primaryAction] (e.g. voice) while the prompt is empty, and turns
/// into send — with the SF Symbol replace effect — once there's text or an
/// attachment.
///
/// It grows into a card when the text wraps, has a line break, or there are
/// [attachments]: attachments on top, the text full width, buttons along the
/// bottom row. Every change moves on one spring.
///
/// [sideActions] are glass circles beside the capsule, shown while
/// [showSideActions] is true — e.g. a voice session's mute and end buttons.
/// They split off the capsule like liquid (UIKit's glass container effect)
/// as it narrows, and the inline [actions] fade out.
///
/// Idle, it sits concentric with the display's bottom corners (inset by the
/// home indicator area + 4 pt), or 9 pt above a tab bar. Focused, it widens
/// to 12 pt margins 12 pt above the keyboard, inside the keyboard's own
/// animation. [child] gets bottom padding for it, as with [NativeComposer].
class NativePromptComposer extends StatefulWidget {
  const NativePromptComposer({
    super.key,
    this.controller,
    this.placeholder,
    this.leading,
    this.actions = const [],
    this.primaryAction,
    this.stopAction,
    this.sendIcon,
    this.sendEnabled = true,
    this.sendBusy = false,
    this.editable = true,
    this.sideActions = const [],
    this.showSideActions = false,
    this.attachments = const [],
    this.attachmentSummary,
    this.onSend,
    this.onChanged,
    this.tintColor,
    this.highlights = const [],
    this.maxLines = 8,
    this.clearOnSend = true,
    this.interactiveKeyboardDismissal = true,
    this.onVoiceRecorded,
    this.onVoiceRecordingFailed,
    this.recordingCancelLabel,
    this.recordingDoneLabel,
    required this.child,
  });

  final NativeComposerController? controller;
  final String? placeholder;

  /// At the leading edge, a plain glyph (e.g. "+" with a [NativeComposerButton.menu]).
  final NativeComposerButton? leading;

  /// Plain glyph buttons before the primary circle (e.g. dictation).
  final List<NativeComposerButton> actions;

  /// The filled circle while there's nothing to send (e.g. voice mode).
  /// Without it, a disabled send button shows instead.
  final NativeComposerButton? primaryAction;

  /// While set, the filled circle is this button whatever the prompt holds —
  /// e.g. stop while a reply is generating (defaults to `stop.fill`).
  final NativeComposerButton? stopAction;

  /// Defaults to `arrow.up`.
  final NativeIcon? sendIcon;

  /// Whether content may be sent; when false, send shows disabled.
  final bool sendEnabled;

  /// Send shows a spinner (e.g. attachments still uploading).
  final bool sendBusy;

  /// Whether the text can be edited; when false the composer shows its text
  /// (e.g. a live dictation transcript) and doesn't take the keyboard.
  final bool editable;

  /// Glass circles beside the capsule; [NativeComposerButton.prominent] tints
  /// one with the label colour.
  final List<NativeComposerButton> sideActions;
  final bool showSideActions;

  final List<NativeComposerAttachment> attachments;

  /// Set to fold [attachments] into a count pill while the prompt isn't
  /// focused (e.g. after scrolling dismissed the keyboard). Null keeps them
  /// on show.
  final NativeComposerAttachmentSummary? attachmentSummary;

  /// Called with the text (possibly empty when only attachments are sent).
  final ValueChanged<String>? onSend;
  final ValueChanged<String>? onChanged;

  /// Caret and primary circle colour.
  final Color? tintColor;

  /// See [NativeComposer.highlights].
  final List<String> highlights;

  /// Lines the text grows to before scrolling.
  final int maxLines;
  final bool clearOnSend;

  /// See [NativeComposer.interactiveKeyboardDismissal].
  final bool interactiveKeyboardDismissal;

  /// A clip recorded with [NativeComposerController.startVoiceRecording].
  final ValueChanged<NativeVoiceRecording>? onVoiceRecorded;

  /// Recording couldn't start: microphone access declined, or no native
  /// recorder here (the Flutter fallback).
  final ValueChanged<NativeVoiceRecordingFailure>? onVoiceRecordingFailed;

  /// VoiceOver labels for the recording bar's cancel and done buttons.
  final String? recordingCancelLabel;
  final String? recordingDoneLabel;

  final Widget child;

  @override
  State<NativePromptComposer> createState() => _NativePromptComposerState();
}

class _NativePromptComposerState extends _ComposerHostState<NativePromptComposer> {
  @override
  String get _style => 'prompt';

  @override
  NativeComposerController? get _widgetController => widget.controller;

  @override
  Widget get _child => widget.child;

  @override
  bool get _clearOnSend => widget.clearOnSend;

  @override
  bool get _interactiveDismissal => widget.interactiveKeyboardDismissal;

  @override
  ValueChanged<NativeVoiceRecording>? get _onVoiceRecorded => widget.onVoiceRecorded;

  @override
  ValueChanged<NativeVoiceRecordingFailure>? get _onVoiceRecordingFailed => widget.onVoiceRecordingFailed;

  @override
  String? get _recordingCancelLabel => widget.recordingCancelLabel;

  @override
  String? get _recordingDoneLabel => widget.recordingDoneLabel;

  @override
  ValueChanged<String>? get _onSend => widget.onSend;

  @override
  ValueChanged<String>? get _onChanged => widget.onChanged;

  @override
  ValueChanged<String>? get _onAttachmentRemoved =>
      (id) => widget.attachments.where((a) => a.id == id).firstOrNull?.onRemove?.call();

  @override
  ValueChanged<String>? get _onAttachmentTapped =>
      (id) => widget.attachments.where((a) => a.id == id).firstOrNull?.onTap?.call();

  @override
  Map<String, Object?> _encode(Map<String, VoidCallback?> handlers) => {
    'placeholder': widget.placeholder,
    'leading': widget.leading?._encode('leading', handlers),
    'actions': [for (final (i, b) in widget.actions.indexed) b._encode('action$i', handlers)],
    'primary': widget.primaryAction?._encode('primary', handlers),
    'stop': widget.stopAction?._encode('stop', handlers),
    'sendIcon': widget.sendIcon?.encode(),
    'sendEnabled': widget.sendEnabled,
    'sendBusy': widget.sendBusy,
    'editable': widget.editable,
    'side': [for (final (i, b) in widget.sideActions.indexed) b._encode('side$i', handlers)],
    'sideShown': widget.showSideActions,
    'attachments': [for (final a in widget.attachments) a._encode()],
    'attachmentSummary': widget.attachmentSummary?._encode(),
    'tintColor': widget.tintColor?.toARGB32(),
    'highlights': widget.highlights,
    'maxLines': widget.maxLines,
  };

  @override
  Widget _buildFallback(NativeComposerController controller) =>
      _FallbackPromptComposer(composer: widget, controller: controller);
}

/// Flutter replica of the native prompt composer, for Android and iOS 15–25,
/// with the same geometry — solid instead of glass:
///
/// A 48 pt capsule: leading glyph centred 24 pt from the edge, text from
/// 50 pt, actions every 48 pt, a 32 pt filled circle centred 24 pt from the
/// trailing edge. Multi-line (wrapping, a line break, attachments): 60 pt
/// attachment tiles 12 pt from the top, text inset 18 pt, buttons on the
/// bottom row, radius 24. Side actions: 48 pt circles 10 pt apart.
/// Idle: inset by the home indicator area + 4 pt (12 pt without one), or
/// 9 pt above a tab bar with 20 pt margins; focused: 12 pt margins, 12 pt
/// above the keyboard.
class _FallbackPromptComposer extends StatefulWidget {
  const _FallbackPromptComposer({required this.composer, required this.controller});

  final NativePromptComposer composer;
  final NativeComposerController controller;

  @override
  State<_FallbackPromptComposer> createState() => _FallbackPromptComposerState();
}

class _FallbackPromptComposerState extends State<_FallbackPromptComposer> implements _ComposerBackend {
  late final _HighlightingTextController _text = _HighlightingTextController.fromValue(
    TextEditingValue(text: widget.controller.text, selection: widget.controller.selection),
  );
  final FocusNode _focus = FocusNode();

  static const _row = 48.0;
  static const _edgeCenter = 24.0;
  static const _actionSpacing = 48.0;
  static const _primary = 32.0;
  static const _textLeading = 50.0;
  static const _textInset = 18.0;
  static const _textVertical = 13.0;
  static const _lineHeight = 22.0;
  static const _multiRowExtra = 32.0;
  static const _sideSpacing = 10.0;
  static const _radius = 24.0;
  static const _attachmentTop = 12.0;
  static const _attachmentHeight = 60.0;
  static const _audioInset = 8.0;
  static const _audioLift = 4.0;
  static const _summaryGap = 8.0;
  static const _summaryHeight = 24.0;
  static const _duration = Duration(milliseconds: 350);
  static const _curve = Curves.easeOutCubic;
  // A gentle overshoot, like UIKit's spring with a little bounce.
  static const _springCurve = Cubic(0.3, 1.25, 0.4, 1);
  static const _textStyle = TextStyle(fontSize: 17, height: _lineHeight / 17);

  NativePromptComposer get _c => widget.composer;

  @override
  void initState() {
    super.initState();
    widget.controller._backend = this;
    _text.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_FallbackPromptComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._backend = const _NativeBackend();
      widget.controller._backend = this;
    }
  }

  void _onText() {
    if (widget.controller._nativeText(_text.text, _text.selection)) _c.onChanged?.call(_text.text);
    setState(() {});
  }

  void _onFocus() {
    widget.controller._nativeFocus(_focus.hasFocus);
    setState(() {});
  }

  @override
  void setText(String text, TextSelection selection) {
    final value = TextEditingValue(text: text, selection: selection);
    if (_text.value.text != text || _text.value.selection != selection) _text.value = value;
  }

  @override
  void focus() => _focus.requestFocus();

  @override
  void unfocus() => _focus.unfocus();

  @override
  void startRecording(Duration? maxDuration) =>
      _c.onVoiceRecordingFailed?.call(NativeVoiceRecordingFailure.unavailable);

  @override
  void finishRecording() {}

  @override
  void cancelRecording() {}

  bool get _hasContent => _text.text.trim().isNotEmpty || _c.attachments.isNotEmpty;

  bool get _canSend => _hasContent && _c.sendEnabled && !_c.sendBusy && _c.stopAction == null;

  void _send() {
    if (!_canSend) return;
    _c.onSend?.call(_text.text);
    if (_c.clearOnSend) _text.clear();
  }

  @override
  void dispose() {
    if (widget.controller._backend == this) widget.controller._backend = const _NativeBackend();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  double _summaryWidth(String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _FallbackAttachmentSummary.labelStyle),
      textDirection: Directionality.of(context),
    )..layout();
    final width = _FallbackAttachmentSummary.chromeWidth + painter.width;
    painter.dispose();
    return width.ceilToDouble();
  }

  int _lines(double width) {
    final painter = TextPainter(
      text: TextSpan(text: _text.text.isEmpty ? ' ' : _text.text, style: _textStyle),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: math.max(1, width));
    final lines = math.max(1, (painter.height / _lineHeight).round());
    painter.dispose();
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final style = VeneerFallbackStyle.of(context);
    final accent = _c.tintColor ?? style.accent;
    _text
      ..highlights = _c.highlights
      ..highlightColor = accent;
    final keyboard = mq.viewInsets.bottom;
    final systemBottom = MediaQueryData.fromView(View.of(context)).viewPadding.bottom;
    // Padding beyond the system's own inset means chrome (a tab bar) below.
    final hasBar = mq.padding.bottom > systemBottom + 1;

    // Resting place; the keyboard pushes it up once it rises past it.
    final double restBottom;
    final double restMargin;
    if (hasBar) {
      restMargin = 20;
      restBottom = mq.padding.bottom + 9;
    } else {
      final inset = systemBottom > 0 ? systemBottom + 4 : 12.0;
      restMargin = inset;
      restBottom = inset;
    }
    final focused = _focus.hasFocus;
    final margin = focused ? 12.0 : restMargin;
    final bottom = math.max(keyboard + 12, restBottom);
    final base = math.max(keyboard, mq.padding.bottom);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 2 * margin;
        final sideShown = _c.showSideActions && _c.sideActions.isNotEmpty;
        final n = _c.sideActions.length;
        final capsuleWidth = width - (sideShown ? n * (_row + _sideSpacing) : 0);
        final canSend = _canSend;
        final hasContent = _hasContent;
        final stop = _c.stopAction;
        final primaryVisible = !sideShown || hasContent || stop != null;
        final hasLeading = _c.leading != null;
        final textLeading = hasLeading ? _textLeading : _textInset;
        final textEnd =
            capsuleWidth - (sideShown ? 0 : _c.actions.length * _actionSpacing) - (primaryVisible ? _row : _textInset);
        final summary = _c.attachmentSummary;
        final collapsed = summary != null && _c.attachments.isNotEmpty && !focused;
        final summaryLabel = '${_c.attachments.length}';
        final summaryWidth = collapsed ? _summaryWidth(summaryLabel) : 0.0;
        final inlineWidth = textEnd - textLeading - (collapsed ? summaryWidth + _summaryGap : 0);
        final multiline =
            (_c.attachments.isNotEmpty && !collapsed) ||
            _text.text.contains('\n') ||
            (_text.text.isNotEmpty && _lines(inlineWidth) > 1);
        final attachmentsBlock = _c.attachments.isEmpty || collapsed ? 0.0 : _attachmentTop + _attachmentHeight;
        final lines = multiline ? math.min(_lines(capsuleWidth - 2 * _textInset), _c.maxLines) : 1;
        final textHeight = lines * _lineHeight + 2 * _textVertical;
        final height = multiline ? attachmentsBlock + textHeight + _multiRowExtra : _row;
        final rowTop = height - _row;

        Widget positioned({
          required double left,
          double? top,
          double? bottom,
          required double size,
          required Widget child,
          bool visible = true,
          Curve curve = _curve,
        }) => AnimatedPositioned(
          duration: _duration,
          curve: curve,
          left: left,
          top: top,
          bottom: bottom,
          width: size,
          height: size,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              duration: _duration,
              curve: _curve,
              opacity: visible ? 1 : 0,
              child: AnimatedScale(duration: _duration, curve: _curve, scale: visible ? 1 : 0.5, child: child),
            ),
          ),
        );

        final sendFace = stop == null && (hasContent || _c.primaryAction == null);
        final busy = sendFace && _c.sendBusy && hasContent;
        final primaryIcon = stop != null
            ? stop.icon
            : sendFace
            ? (_c.sendIcon ?? const NativeIcon.symbol('arrow.up'))
            : _c.primaryAction!.icon;
        final primaryFaceKey = stop != null ? 'stop' : (sendFace ? 'send' : 'primary');

        final capsule = AnimatedContainer(
          duration: _duration,
          curve: _curve,
          width: capsuleWidth,
          height: height,
          decoration: style.surfaceDecoration(radius: BorderRadius.circular(math.min(height / 2, _radius))),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Attachments along the top.
              AnimatedPositioned(
                duration: _duration,
                curve: _curve,
                left: 0,
                right: 0,
                top: _attachmentTop - _audioLift,
                height: _attachmentHeight + _audioLift,
                child: IgnorePointer(
                  ignoring: collapsed,
                  child: AnimatedOpacity(
                    duration: _duration,
                    opacity: _c.attachments.isEmpty || collapsed ? 0 : 1,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.only(
                        left: _c.attachments.firstOrNull?.audio != null ? _audioInset : 12,
                        right: 12,
                      ),
                      children: [
                        for (final a in _c.attachments)
                          Padding(
                            key: ValueKey(a.id),
                            padding: const EdgeInsets.only(right: 8),
                            child: a.audio == null
                                ? Padding(
                                    padding: const EdgeInsets.only(top: _audioLift),
                                    child: _FallbackAttachmentTile(attachment: a, style: style),
                                  )
                                : _FallbackAudioTile(
                                    attachment: a,
                                    audio: a.audio!,
                                    width: capsuleWidth - 2 * _audioInset,
                                    accent: accent,
                                    style: style,
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Text: inline beside the buttons, or full width above them.
              AnimatedPositioned(
                duration: _duration,
                curve: _curve,
                left: multiline ? _textInset : textLeading,
                top: multiline ? attachmentsBlock : 0,
                width: multiline ? capsuleWidth - 2 * _textInset : inlineWidth,
                height: multiline ? textHeight : _row,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    readOnly: !_c.editable,
                    minLines: 1,
                    maxLines: _c.maxLines,
                    keyboardType: TextInputType.multiline,
                    cursorColor: accent,
                    textCapitalization: TextCapitalization.sentences,
                    style: _textStyle.copyWith(color: style.label),
                    decoration: InputDecoration.collapsed(
                      hintText: _c.placeholder,
                      hintStyle: _textStyle.copyWith(color: style.placeholder),
                    ).copyWith(contentPadding: const EdgeInsets.symmetric(vertical: _textVertical), isDense: true),
                  ),
                ),
              ),
              if (_c.leading case final leading?)
                positioned(
                  left: 0,
                  top: rowTop,
                  size: _row,
                  child: _fallbackTap(
                    leading,
                    child: Center(child: NativeIconView(leading.icon, size: 24, color: style.label)),
                  ),
                ),
              AnimatedPositioned(
                duration: _duration,
                curve: _curve,
                left: textEnd - summaryWidth,
                top: rowTop + (_row - _summaryHeight) / 2,
                height: _summaryHeight,
                child: IgnorePointer(
                  ignoring: !collapsed,
                  child: AnimatedOpacity(
                    duration: _duration,
                    curve: _curve,
                    opacity: collapsed ? 1 : 0,
                    child: AnimatedScale(
                      duration: _duration,
                      curve: _curve,
                      scale: collapsed ? 1 : 0.5,
                      child: Semantics(
                        button: true,
                        label: '$summaryLabel attachments',
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: _focus.requestFocus,
                          child: _FallbackAttachmentSummary(
                            label: summaryLabel,
                            summary: summary ?? const NativeComposerAttachmentSummary(),
                            style: style,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              for (final (i, b) in _c.actions.indexed)
                positioned(
                  left: capsuleWidth - _edgeCenter - _actionSpacing * (_c.actions.length - i) - _row / 2,
                  top: rowTop,
                  size: _row,
                  visible: !sideShown,
                  child: _fallbackTap(
                    b,
                    child: Center(child: NativeIconView(b.icon, size: 24, color: style.label)),
                  ),
                ),
              positioned(
                left: capsuleWidth - _edgeCenter - _primary / 2,
                top: rowTop + (_row - _primary) / 2,
                size: _primary,
                visible: primaryVisible,
                child: Semantics(
                  button: true,
                  label: stop != null ? stop.title : (sendFace ? 'Send' : _c.primaryAction!.title),
                  enabled: sendFace ? canSend : true,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: stop != null
                        ? stop.onPressed
                        : canSend
                        ? _send
                        : (sendFace ? null : _c.primaryAction?.onPressed),
                    child: AnimatedContainer(
                      duration: _duration,
                      decoration: BoxDecoration(
                        color: sendFace && !canSend ? style.selection : accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, animation) => ScaleTransition(
                          scale: Tween(begin: 0.4, end: 1.0).animate(animation),
                          child: FadeTransition(opacity: animation, child: child),
                        ),
                        child: busy
                            ? SizedBox.square(
                                key: const ValueKey('busy'),
                                dimension: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: style.disabled),
                              )
                            : NativeIconView(
                                primaryIcon,
                                key: ValueKey(primaryFaceKey),
                                size: 18,
                                color: sendFace && !canSend ? style.disabled : Colors.white,
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
              tween: Tween(end: bottom + height - base),
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
              bottom: bottom,
              child: AnimatedPadding(
                duration: _duration,
                curve: _curve,
                padding: EdgeInsets.symmetric(horizontal: margin),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: height),
                  duration: _duration,
                  curve: _curve,
                  builder: (context, h, child) => SizedBox(height: h, child: child),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: GestureDetector(
                            // Like the native capsule: tapping anywhere on it focuses.
                            onTap: focused || !_c.editable ? null : _focus.requestFocus,
                            child: capsule,
                          ),
                        ),
                        for (final (i, b) in _c.sideActions.indexed)
                          positioned(
                            left: sideShown ? width - (n - i) * _row - (n - 1 - i) * _sideSpacing : capsuleWidth - _row,
                            bottom: 0,
                            size: _row,
                            visible: sideShown,
                            curve: _springCurve,
                            child: _fallbackTap(
                              b,
                              child: DecoratedBox(
                                decoration: style.surfaceDecoration(
                                  shape: BoxShape.circle,
                                  color: b.prominent ? style.label : null,
                                ),
                                child: Center(
                                  child: NativeIconView(
                                    b.icon,
                                    size: b.prominent ? 20 : 24,
                                    color: b.prominent ? style.surface : style.label,
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
          ],
        );
      },
    );
  }
}

/// A 60 pt image tile, or a chip with a thumbnail, title and subtitle; a
/// remove button in the top trailing corner.
class _FallbackAttachmentTile extends StatelessWidget {
  const _FallbackAttachmentTile({required this.attachment, required this.style});

  final NativeComposerAttachment attachment;
  final VeneerFallbackStyle style;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final chip = (a.title ?? '').isNotEmpty;
    final side = chip ? 44.0 : 60.0;
    Widget thumbnail = SizedBox(width: side, height: side);
    if (a.thumbnail case final t?) {
      thumbnail = NativeIconView.keepsColors(t)
          ? NativeIconView(t, size: side, fit: BoxFit.cover)
          : Container(
              width: side,
              height: side,
              color: style.selection,
              alignment: Alignment.center,
              child: NativeIconView(t, size: 22, color: style.secondaryLabel),
            );
    }
    thumbnail = ClipRRect(borderRadius: BorderRadius.circular(chip ? 10 : 16), child: thumbnail);

    return TweenAnimationBuilder<double>(
      // Grows in when added.
      tween: Tween(begin: 0.5, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Opacity(
        opacity: ((scale - 0.5) * 2).clamp(0, 1),
        child: Transform.scale(scale: scale, child: child),
      ),
      child: Stack(
        children: [
          if (chip)
            Container(
              height: 60,
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.only(left: 8, right: 38),
              decoration: BoxDecoration(color: style.selection, borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  thumbnail,
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: style.label),
                        ),
                        if ((a.subtitle ?? '').isNotEmpty)
                          Text(
                            a.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: style.secondaryLabel),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            thumbnail,
          if (a.onTap case final onTap?)
            Positioned.fill(
              child: Semantics(
                container: true,
                button: true,
                label: [a.title, a.subtitle].whereType<String>().where((s) => s.isNotEmpty).join(', '),
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap),
              ),
            ),
          if (a.loading)
            Positioned(
              left: chip ? 8 : 0,
              top: chip ? 8 : 0,
              width: side,
              height: side,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(chip ? 10 : 16),
                child: const ColoredBox(
                  color: Color(0x59000000),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 5,
            right: 5,
            child: Semantics(
              container: true,
              button: true,
              label: 'Remove',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: a.onRemove,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 13, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Flutter replica of the native voice clip row: 56 pt, 8 pt padding,
/// `[40 pt circle · bars · duration · 32 pt remove]` 8 pt apart, radius 16.
/// Tops the strip, 4 pt above the other tiles, so it's 8 pt from the composer's top.
class _FallbackAudioTile extends StatelessWidget {
  const _FallbackAudioTile({
    required this.attachment,
    required this.audio,
    required this.width,
    required this.accent,
    required this.style,
  });

  final NativeComposerAttachment attachment;
  final NativeComposerAudio audio;
  final double width;
  final Color accent;
  final VeneerFallbackStyle style;

  static const _height = 56.0;
  static const _play = 40.0;
  static const _remove = 32.0;
  static const _icon = 24.0;
  static const _waveHeight = 32.0;

  @override
  Widget build(BuildContext context) {
    final label = audio.labelColor ?? style.label;
    final playIcon = audio.playing
        ? audio.pauseIcon ?? const NativeIcon.symbol('pause.fill', fallback: Icons.pause_rounded)
        : audio.playIcon ?? const NativeIcon.symbol('play.fill', fallback: Icons.play_arrow_rounded);
    final removeIcon = audio.removeIcon ?? const NativeIcon.symbol('xmark', fallback: Icons.close_rounded);

    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          height: _height,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: audio.backgroundColor ?? style.selection,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            spacing: 8,
            children: [
              Semantics(
                button: true,
                label: audio.playing ? 'Pause' : 'Play',
                child: GestureDetector(
                  onTap: attachment.loading ? null : attachment.onTap,
                  child: Container(
                    width: _play,
                    height: _play,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: attachment.loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : NativeIconView(playIcon, size: _icon, color: Colors.white),
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: _waveHeight,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      samples: audio.waveform,
                      progress: audio.progress,
                      color: audio.waveColor ?? style.placeholder,
                      progressColor: accent,
                    ),
                  ),
                ),
              ),
              if (audio.duration case final duration?)
                Text(
                  duration,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    height: 18 / 13,
                    color: label,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              Semantics(
                button: true,
                label: 'Remove',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: attachment.onRemove,
                  child: SizedBox.square(
                    dimension: _remove,
                    child: Center(
                      child: NativeIconView(removeIcon, size: _icon, color: label),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2 pt rounded bars, 1 pt apart, centred, at least 2 pt tall; the played
/// fraction in [progressColor].
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.samples, required this.progress, required this.color, required this.progressColor});

  final List<double> samples;
  final double progress;
  final Color color;
  final Color progressColor;

  static const barWidth = 2.0;
  static const gap = 1.0;
  static const minHeight = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final count = ((size.width + gap) / (barWidth + gap)).floor();
    if (count <= 0) return;
    final played = progress * size.width;
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final amplitude = _sampleAt(i, count);
      final height = math.max(minHeight, amplitude * size.height);
      final x = i * (barWidth + gap);
      paint.color = x + barWidth / 2 <= played ? progressColor : color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - height) / 2, barWidth, height),
          const Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  double _sampleAt(int bar, int count) {
    if (samples.isEmpty) return 0;
    final start = bar * samples.length ~/ count;
    final end = math.max(start + 1, (bar + 1) * samples.length ~/ count);
    var peak = 0.0;
    for (var i = start; i < end && i < samples.length; i++) {
      peak = math.max(peak, samples[i]);
    }
    return peak.clamp(0, 1);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.progressColor != progressColor ||
      !identical(old.samples, samples);
}

/// The folded attachments: `[📎 3]`, a 24 pt capsule, 4 pt before the icon
/// and 8 pt after the count.
class _FallbackAttachmentSummary extends StatelessWidget {
  const _FallbackAttachmentSummary({required this.label, required this.summary, required this.style});

  final String label;
  final NativeComposerAttachmentSummary summary;
  final VeneerFallbackStyle style;

  static const _icon = 16.0;
  static const _gap = 4.0;
  static const _padding = EdgeInsets.fromLTRB(4, 2, 8, 2);
  static const labelStyle = TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w500);
  static double get chromeWidth => _padding.horizontal + _icon + _gap;

  @override
  Widget build(BuildContext context) {
    final foreground = summary.foregroundColor ?? style.label;
    return Container(
      padding: _padding,
      decoration: BoxDecoration(
        color: summary.backgroundColor ?? style.selection,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _gap,
        children: [
          NativeIconView(
            summary.icon ?? const NativeIcon.symbol('paperclip', fallback: Icons.attach_file_rounded),
            size: _icon,
            color: foreground,
          ),
          Text(label, maxLines: 1, style: labelStyle.copyWith(color: foreground)),
        ],
      ),
    );
  }
}
