import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A UIKit control in a platform view (`veneer/<kind>`), configured from
/// [config] and reporting user changes through [onEvent].
///
/// The control is controlled, like Flutter's: after every user change the
/// current [config] is sent again, so a parent that doesn't take the new
/// value puts the control back.
class NativeControlView extends StatefulWidget {
  const NativeControlView({super.key, required this.kind, required this.config, required this.onEvent});

  final String kind;
  final Map<String, Object?> config;
  final void Function(String method, Map<Object?, Object?> arguments) onEvent;

  @override
  State<NativeControlView> createState() => _NativeControlViewState();
}

class _NativeControlViewState extends State<NativeControlView> {
  MethodChannel? _channel;
  Map<String, Object?>? _sent;

  @override
  void didUpdateWidget(NativeControlView old) {
    super.didUpdateWidget(old);
    if (!mapEquals(widget.config, _sent)) _send();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onCreated(int id) {
    _channel = MethodChannel('veneer/${widget.kind}_$id')
      ..setMethodCallHandler((call) async {
        widget.onEvent(call.method, call.arguments as Map<Object?, Object?>? ?? const {});
        // A parent that keeps its value doesn't rebuild, so ask for the frame.
        SchedulerBinding.instance
          ..addPostFrameCallback((_) {
            if (mounted) _send();
          })
          ..ensureVisualUpdate();
      });
    // The view was made from the first build's config; send what it is now.
    _send();
  }

  void _send() {
    final channel = _channel;
    if (channel == null) return;
    _sent = widget.config;
    channel.invokeMethod<void>('update', widget.config);
  }

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: 'veneer/${widget.kind}',
      creationParams: widget.config,
      creationParamsCodec: const StandardMessageCodec(),
      // Keeps a drag on the control from becoming a Flutter scroll.
      gestureRecognizers: {Factory<HorizontalDragGestureRecognizer>(HorizontalDragGestureRecognizer.new)},
      onPlatformViewCreated: _onCreated,
    );
  }
}
