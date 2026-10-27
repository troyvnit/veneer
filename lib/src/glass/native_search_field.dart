import 'package:flutter/material.dart';

import '../core/fallback_scope.dart';
import '../core/fallback_style.dart';
import '../core/native_icon.dart';
import '../core/route_visibility.dart';
import '../core/veneer_bridge.dart';
import 'glass_coordinator.dart';
import 'glass_group.dart';
import 'glass_shape.dart';

/// A search field on Liquid Glass, positioned by Flutter layout.
///
/// On iOS 26 it is a real `UISearchTextField` inside a glass capsule — the
/// magnifier, placeholder, clear button, keyboard and text editing are all
/// UIKit's, the way search fields look in Apple's apps. Typing reports back
/// through [onChanged]; the keyboard's search key through [onSubmitted].
///
/// Pass a [controller] to read or replace the text from Dart: setting
/// `controller.text` (e.g. clearing it) updates the native field too. Use
/// [NativeSearchFieldState.focus] and [NativeSearchFieldState.unfocus] (via a
/// `GlobalKey`) to move the keyboard.
///
/// Pass [onMicrophonePressed] to show a microphone in the field while it is
/// empty, the way Apple's apps offer dictation; [microphoneActive] fills it
/// while the app is listening.
///
/// [searchIcon], [microphoneIcon] and [microphoneActiveIcon] replace the
/// system magnifier and microphone with the app's own icons; left `null`,
/// UIKit's SF Symbols are used. [iconSize] is the side of those icons.
///
/// On Android and iOS 15–25 it renders a Flutter replica with the same size.
class NativeSearchField extends StatefulWidget {
  const NativeSearchField({
    super.key,
    required this.placeholder,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.onFocusChanged,
    this.onMicrophonePressed,
    this.microphoneActive = false,
    this.searchIcon,
    this.microphoneIcon,
    this.microphoneActiveIcon,
    this.iconSize = 20,
    this.height = 44,
    this.style = GlassStyle.regular,
    this.tint,
  });

  final String placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<bool>? onFocusChanged;
  final VoidCallback? onMicrophonePressed;
  final bool microphoneActive;
  final NativeIcon? searchIcon;
  final NativeIcon? microphoneIcon;
  final NativeIcon? microphoneActiveIcon;
  final double iconSize;
  final double height;
  final GlassStyle style;
  final Color? tint;

  @override
  State<NativeSearchField> createState() => NativeSearchFieldState();
}

class NativeSearchFieldState extends State<NativeSearchField> {
  final int _id = GlassCoordinator.allocateId();
  final FocusNode _fallbackFocus = FocusNode();

  int? _group;
  bool _native = false;
  TextEditingController? _ownController;

  /// The text the native field last reported or was last sent, so a
  /// controller change that came from UIKit isn't echoed back to it.
  String _nativeText = '';

  late final RouteChainWatcher _routes = RouteChainWatcher(() {
    if (mounted) setState(() {});
  });

  TextEditingController get _controller => widget.controller ?? (_ownController ??= TextEditingController());

  /// Raises the keyboard in the field.
  void focus() {
    if (_native) {
      VeneerBridge.instance.searchCommand(_id, 'focus');
    } else {
      _fallbackFocus.requestFocus();
    }
  }

  /// Dismisses the keyboard if the field holds it.
  void unfocus() {
    if (_native) {
      VeneerBridge.instance.searchCommand(_id, 'blur');
    } else {
      _fallbackFocus.unfocus();
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
    _native = useNativeLayer(context);
    final group = GlassGroup.groupIdOf(context);
    if (group != _group) {
      _group = group;
      _configure();
    }
  }

  @override
  void didUpdateWidget(NativeSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_onControllerChanged);
      _controller.addListener(_onControllerChanged);
      _configure();
      return;
    }
    if (old.placeholder != widget.placeholder ||
        old.style != widget.style ||
        old.tint != widget.tint ||
        (old.onMicrophonePressed == null) != (widget.onMicrophonePressed == null) ||
        old.microphoneActive != widget.microphoneActive ||
        old.searchIcon != widget.searchIcon ||
        old.microphoneIcon != widget.microphoneIcon ||
        old.microphoneActiveIcon != widget.microphoneActiveIcon ||
        old.iconSize != widget.iconSize) {
      _configure();
    }
  }

  void _onControllerChanged() {
    if (!_native || _controller.text == _nativeText) return;
    _configure();
  }

  void _configure() {
    if (!_native) return;
    _nativeText = _controller.text;
    VeneerBridge.instance
        .configureShape(
          {
            'id': _id,
            'group': _group,
            'style': widget.style.name,
            'tint': widget.tint?.toARGB32(),
            'interactive': true,
            'search': {
              'placeholder': widget.placeholder,
              'text': _controller.text,
              if (widget.searchIcon case final icon?) 'searchIcon': icon.encode(),
              if (widget.searchIcon != null || widget.microphoneIcon != null) 'iconSize': widget.iconSize,
              if (widget.onMicrophonePressed != null) ...{
                'microphone': true,
                'microphoneActive': widget.microphoneActive,
                if (widget.microphoneIcon case final icon?) 'microphoneIcon': icon.encode(),
                if (widget.microphoneActiveIcon case final icon?) 'microphoneActiveIcon': icon.encode(),
              },
            },
          },
          null,
          onSearch: VeneerSearchHandlers(
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
            onMicrophone: () => widget.onMicrophonePressed?.call(),
          ),
        )
        .then((_) => GlassCoordinator.instance.markDirty());
  }

  @override
  void dispose() {
    _routes.dispose();
    _controller.removeListener(_onControllerChanged);
    _ownController?.dispose();
    _fallbackFocus.dispose();
    if (_native) VeneerBridge.instance.removeShape(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_native) {
      return _FallbackSearchField(field: widget, controller: _controller, focusNode: _fallbackFocus);
    }
    final visible = Visibility.of(context) && isRouteOnTop(context);
    return _SearchAnchor(
      shapeId: _id,
      shouldShow: visible,
      child: SizedBox(width: double.infinity, height: widget.height),
    );
  }
}

class _SearchAnchor extends SingleChildRenderObjectWidget {
  const _SearchAnchor({required this.shapeId, required this.shouldShow, super.child});

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

/// Flutter replica where native glass isn't available: a capsule on the
/// fallback surface with a magnifier, the placeholder and a clear button.
class _FallbackSearchField extends StatelessWidget {
  const _FallbackSearchField({required this.field, required this.controller, required this.focusNode});

  final NativeSearchField field;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final style = VeneerFallbackStyle.of(context);
    final textStyle = TextStyle(color: style.label, fontSize: 17);

    return SizedBox(
      height: field.height,
      child: DecoratedBox(
        decoration: style.surfaceDecoration(radius: BorderRadius.circular(field.height / 2), color: field.tint),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: field.searchIcon == null
                  ? Icon(Icons.search, size: 20, color: style.secondaryLabel)
                  : NativeIconView(field.searchIcon!, size: field.iconSize, color: style.secondaryLabel),
            ),
            Expanded(
              child: Focus(
                onFocusChange: field.onFocusChanged,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: textStyle,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration.collapsed(
                    hintText: field.placeholder,
                    hintStyle: textStyle.copyWith(color: style.placeholder),
                  ),
                  onChanged: field.onChanged,
                  onSubmitted: field.onSubmitted,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? field.onMicrophonePressed == null
                        ? const SizedBox(width: 12)
                        : IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: _FallbackMicrophone(field: field, style: style),
                            onPressed: field.onMicrophonePressed,
                          )
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.cancel, size: 18, color: style.placeholder),
                      onPressed: () {
                        controller.clear();
                        field.onChanged?.call('');
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackMicrophone extends StatelessWidget {
  const _FallbackMicrophone({required this.field, required this.style});

  final NativeSearchField field;
  final VeneerFallbackStyle style;

  @override
  Widget build(BuildContext context) {
    final active = field.microphoneActive;
    final color = active ? style.label : style.secondaryLabel;
    final icon = active ? field.microphoneActiveIcon ?? field.microphoneIcon : field.microphoneIcon;
    if (icon == null) return Icon(active ? Icons.mic : Icons.mic_none, size: 20, color: color);
    return NativeIconView(icon, size: field.iconSize, color: color);
  }
}
