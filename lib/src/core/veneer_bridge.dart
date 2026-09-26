import 'dart:async';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// How per-frame glass geometry reaches the native layer.
enum VeneerTransport {
  /// Synchronous `dart:ffi` call. With merged UI/platform threads this
  /// runs on the main thread inside the Flutter frame, so native frames are
  /// set in the same run-loop turn Flutter paints in.
  ffi,

  /// Async method channel. Kept only to measure the lag FFI avoids.
  channel,

  /// Channel delivery held back ~one 60 Hz frame. A control for the sync
  /// harness: if this doesn't measure as ~1 frame of lag, the harness
  /// can't detect lag and a zero reading from the other transports is
  /// meaningless.
  delayedChannel,
}

typedef _ApplyFrameNative = Void Function(Pointer<Double>, Int32);
typedef _ApplyFrameDart = void Function(Pointer<Double>, int);

/// Low-level link to the iOS overlay. Widgets use this; apps normally don't.
class VeneerBridge {
  VeneerBridge._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final VeneerBridge instance = VeneerBridge._();

  final MethodChannel _channel = const MethodChannel('veneer');

  /// Transport for per-frame geometry. Switchable at runtime for A/B tests.
  VeneerTransport transport = VeneerTransport.ffi;

  /// Distance from the top of native chrome to the bottom of the screen.
  final ValueNotifier<double> chromeBottomInset = ValueNotifier(0);

  final Map<int, VoidCallback> _shapeTapHandlers = {};
  ValueChanged<int>? _tabSelectedHandler;
  VoidCallback? _tabActionHandler;

  _ApplyFrameDart? _ffiApplyFrame;
  Pointer<Double>? _ffiBufferPointer;
  Float64List? _ffiBuffer;
  Future<bool>? _attaching;
  bool _attached = false;

  /// Called once the overlay exists, so pending geometry can be re-sent.
  VoidCallback? onAttached;

  /// Forgets the attached overlay. Tests need this: a cached attach future
  /// belongs to the fake-async zone of the test that created it.
  @visibleForTesting
  void debugReset() {
    _attaching = null;
    _attached = false;
    _ffiApplyFrame = null;
    _ffiBufferPointer = null;
    _ffiBuffer = null;
    _shapeTapHandlers.clear();
    _tabSelectedHandler = null;
    _tabActionHandler = null;
  }

  bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;
  bool get isAttached => _attached;

  /// Installs the native overlay above the FlutterView. Retries across
  /// frames because the FlutterViewController may not exist yet at startup.
  Future<bool> ensureAttached() {
    if (!isSupported) return Future.value(false);
    return _attaching ??= _attach();
  }

  Future<bool> _attach() async {
    for (var attempt = 0; attempt < 30; attempt++) {
      try {
        final result = await _channel.invokeMapMethod<String, Object?>('attach');
        final address = result?['applyFrameAddress'] as int?;
        final bufferAddress = result?['bufferAddress'] as int?;
        final capacity = result?['bufferCapacity'] as int?;
        if (address != null && address != 0 && bufferAddress != null && capacity != null) {
          _ffiApplyFrame = Pointer<NativeFunction<_ApplyFrameNative>>.fromAddress(address)
              // Not `isLeaf`: UIKit can synchronously re-enter Dart from
              // inside the call (FlutterViewController layout → viewport
              // metrics), which deadlocks a leaf call.
              .asFunction<_ApplyFrameDart>();
          _ffiBufferPointer = Pointer<Double>.fromAddress(bufferAddress);
          _ffiBuffer = _ffiBufferPointer!.asTypedList(capacity);
        }
        _attached = true;
        onAttached?.call();
        return true;
      } on PlatformException catch (e) {
        if (e.code != 'no_view') rethrow;
        final next = Completer<void>();
        SchedulerBinding.instance.addPostFrameCallback((_) => next.complete());
        SchedulerBinding.instance.scheduleFrame();
        await next.future;
      }
    }
    _attaching = null;
    return false;
  }

  /// Sends a packed geometry frame. See `GlassLayerView.apply` for layout.
  void applyFrame(Float64List frame) {
    if (!_attached) return;
    final ffi = _ffiApplyFrame;
    final buffer = _ffiBuffer;
    if (transport == VeneerTransport.ffi && ffi != null && buffer != null) {
      assert(frame.length <= buffer.length, 'Too many glass shapes on screen');
      buffer.setRange(0, frame.length, frame);
      ffi(_ffiBufferPointer!, frame.length);
    } else if (transport == VeneerTransport.delayedChannel) {
      Future<void>.delayed(const Duration(milliseconds: 16), () => _channel.invokeMethod<void>('applyFrame', frame));
    } else {
      _channel.invokeMethod<void>('applyFrame', frame);
    }
  }

  Future<void> configureShape(Map<String, Object?> config, VoidCallback? onTap) async {
    final id = config['id']! as int;
    if (onTap != null) {
      _shapeTapHandlers[id] = onTap;
    } else {
      _shapeTapHandlers.remove(id);
    }
    if (!await ensureAttached()) return;
    await _channel.invokeMethod<void>('configureShape', config);
  }

  Future<void> removeShape(int id) async {
    _shapeTapHandlers.remove(id);
    if (!_attached) return;
    await _channel.invokeMethod<void>('removeShape', {'id': id});
  }

  Future<void> configureGroup(Map<String, Object?> config) async {
    if (!await ensureAttached()) return;
    await _channel.invokeMethod<void>('configureGroup', config);
  }

  Future<void> removeGroup(int id) async {
    if (!_attached) return;
    await _channel.invokeMethod<void>('removeGroup', {'id': id});
  }

  Future<void> setSpacing(double spacing) async {
    if (!await ensureAttached()) return;
    await _channel.invokeMethod<void>('setSpacing', {'spacing': spacing});
  }

  Future<void> setTabBar(
    Map<String, Object?> config, {
    required ValueChanged<int> onSelected,
    required VoidCallback onAction,
  }) async {
    _tabSelectedHandler = onSelected;
    _tabActionHandler = onAction;
    if (!await ensureAttached()) return;
    await _channel.invokeMethod<void>('setTabBar', config);
  }

  Future<void> removeTabBar() async {
    _tabSelectedHandler = null;
    _tabActionHandler = null;
    if (!_attached) return;
    await _channel.invokeMethod<void>('removeTabBar');
  }

  Future<void> setChromeHidden(bool hidden) async {
    if (!_attached) return;
    await _channel.invokeMethod<void>('setChromeHidden', {'hidden': hidden});
  }

  Future<Map<String, Object?>> stats() async => await _channel.invokeMapMethod<String, Object?>('getStats') ?? const {};

  Future<void> resetStats() => _channel.invokeMethod<void>('resetStats');

  Future<Object?> _handleNativeCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    switch (call.method) {
      case 'shapeTapped':
        _shapeTapHandlers[args['id']]?.call();
      case 'tabSelected':
        _tabSelectedHandler?.call(args['index']! as int);
      case 'tabActionPressed':
        _tabActionHandler?.call();
      case 'chromeInsets':
        chromeBottomInset.value = (args['bottom']! as num).toDouble();
    }
    return null;
  }
}
