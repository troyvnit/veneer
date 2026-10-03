import 'dart:async';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'platform/os_version_stub.dart' if (dart.library.io) 'platform/os_version_io.dart';

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

typedef _ApplyFrameNative = Void Function(Pointer<Double>, Int32, Int32);
typedef _ApplyFrameDart = void Function(Pointer<Double>, int, int);

/// Answers a native sheet's [name] request with a value the standard message
/// codec carries.
typedef SheetRequestHandler = Future<Object?> Function(String name, Object? arguments);

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

  /// Distance from the top of the screen to the bottom of the native
  /// navigation bar; 0 when none is showing.
  final ValueNotifier<double> chromeTopInset = ValueNotifier(0);

  /// In a native sheet's engine: the tallest the UIKit sheet can get (above
  /// the bottom safe area), once presented.
  final ValueNotifier<double?> sheetMaximumHeight = ValueNotifier(null);

  /// In a native sheet's engine: whether its sheet is on screen. A kept-alive
  /// sheet's engine keeps running while hidden.
  final ValueNotifier<bool> sheetShown = ValueNotifier(false);

  final StreamController<Object?> _sheetPresentations = StreamController.broadcast();

  /// In a native sheet's engine: the payload of each presentation, as the
  /// sheet comes up.
  Stream<Object?> get sheetPresentations => _sheetPresentations.stream;

  final Map<int, VoidCallback> _shapeTapHandlers = {};
  final Map<int, ValueChanged<int>> _shapeMenuHandlers = {};
  final Map<int, VeneerContextMenuHandlers> _contextMenuHandlers = {};
  ValueChanged<int>? _tabSelectedHandler;
  VoidCallback? _tabActionHandler;
  ValueChanged<String>? _navItemHandler;
  VeneerComposerHandlers? _composerHandlers;

  _ApplyFrameDart? _ffiApplyFrame;
  Pointer<Double>? _ffiBufferPointer;
  int _pluginId = 0;
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
    _shapeMenuHandlers.clear();
    _contextMenuHandlers.clear();
    _tabSelectedHandler = null;
    _tabActionHandler = null;
    _navItemHandler = null;
    _composerHandlers = null;
    _popupShowing = false;
    _tabBarCovered = false;
    _chromeHiddenSent = null;
    sheetShown.value = false;
    sheetRequestHandler = null;
  }

  /// The native layer needs iOS 26 (Liquid Glass, `UITab`, scroll edge
  /// effects). Elsewhere — Android, iOS 15–25, web — widgets render their
  /// Flutter fallbacks.
  bool get isSupported {
    if (debugForceFallback) return false;
    if (debugIsSupportedOverride case final value?) return value;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && (_iosMajor ?? 0) >= minimumIOSVersion;
  }

  static const int minimumIOSVersion = 26;
  static final int? _iosMajor = iosMajorVersion();

  /// Render the Flutter fallbacks even where the native layer is available,
  /// e.g. to preview the Android/older-iOS UI on an iOS 26 device. Set it
  /// before the first frame.
  bool debugForceFallback = false;

  /// Tests: pretend the native layer is (or isn't) available, regardless of
  /// the host platform.
  @visibleForTesting
  bool? debugIsSupportedOverride;
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
        _pluginId = (result?['pluginId'] as int?) ?? 0;
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
        // Always, even when nothing hides it: an isolate that attached
        // before (a hot restart) may have left the native chrome hidden.
        unawaited(_syncChromeHidden());
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
      ffi(_ffiBufferPointer!, frame.length, _pluginId);
    } else if (transport == VeneerTransport.delayedChannel) {
      Future<void>.delayed(const Duration(milliseconds: 16), () => _channel.invokeMethod<void>('applyFrame', frame));
    } else {
      _channel.invokeMethod<void>('applyFrame', frame);
    }
  }

  Future<void> configureShape(Map<String, Object?> config, VoidCallback? onTap, {ValueChanged<int>? onMenu}) async {
    final id = config['id']! as int;
    if (onMenu != null) {
      _shapeMenuHandlers[id] = onMenu;
    } else {
      _shapeMenuHandlers.remove(id);
    }
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
    _shapeMenuHandlers.remove(id);
    if (!_attached) return;
    await _channel.invokeMethod<void>('removeShape', {'id': id});
  }

  /// A long-press context menu region; its geometry rides the glass frames.
  Future<void> configureContextMenu(Map<String, Object?> config, VeneerContextMenuHandlers handlers) async {
    _contextMenuHandlers[config['id']! as int] = handlers;
    if (!await ensureAttached()) return;
    await _channel.invokeMethod<void>('configureContextMenu', config);
  }

  Future<void> removeContextMenu(int id) async {
    _contextMenuHandlers.remove(id);
    if (!_attached) return;
    await _channel.invokeMethod<void>('removeContextMenu', {'id': id});
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

  Future<void> setNavigationBar(Map<String, Object?> config, ValueChanged<String> onItem) async {
    _navItemHandler = onItem;
    if (!await ensureAttached()) return;
    await _channel.invokeMethod<void>('setNavigationBar', config);
  }

  /// Whether the active bar's page has scrolled under it (its edge effect
  /// shows only then).
  void setNavigationBarScrolled(bool scrolled) {
    if (!_attached) return;
    _channel.invokeMethod<void>('navigationBarScrolled', {'scrolled': scrolled});
  }

  void updateNavigationBarHandler(ValueChanged<String> onItem) => _navItemHandler = onItem;

  void updateComposerHandlers(VeneerComposerHandlers handlers) => _composerHandlers = handlers;

  Future<void> removeNavigationBar() async {
    _navItemHandler = null;
    if (!_attached) return;
    await _channel.invokeMethod<void>('removeNavigationBar');
  }

  Future<void> setComposer(Map<String, Object?> config, VeneerComposerHandlers handlers) async {
    _composerHandlers = handlers;
    if (!await ensureAttached()) return;
    await _channel.invokeMethod<void>('setComposer', config);
  }

  /// The space the native composer last reported taking above the keyboard,
  /// tab bar or safe area; 0 while there's no composer.
  double composerHeight = 0;

  Future<void> removeComposer() async {
    _composerHandlers = null;
    composerHeight = 0;
    if (!_attached) return;
    await _channel.invokeMethod<void>('removeComposer');
  }

  Future<void> composerCommand(
    String command, {
    String? text,
    TextSelection? selection,
    Map<String, Object?> args = const {},
  }) async {
    if (!_attached) return;
    await _channel.invokeMethod<void>('composerCommand', {
      ...args,
      'command': command,
      'text': text,
      if (selection != null) ...{'selectionStart': selection.start, 'selectionEnd': selection.end},
    });
  }

  bool _popupShowing = false;
  bool _tabBarCovered = false;
  bool? _chromeHiddenSent;

  /// Hides native chrome while a Flutter popup is showing (see
  /// `VeneerNavigatorObserver`).
  Future<void> setChromeHidden(bool hidden) {
    _popupShowing = hidden;
    return _syncChromeHidden();
  }

  /// Hides the tab bar while another route covers the page that shows it,
  /// as `hidesBottomBarWhenPushed` does in UIKit.
  Future<void> setTabBarCovered(bool covered) {
    _tabBarCovered = covered;
    return _syncChromeHidden();
  }

  Future<void> _syncChromeHidden() async {
    final hidden = _popupShowing || _tabBarCovered;
    if (!_attached || hidden == _chromeHiddenSent) return;
    _chromeHiddenSent = hidden;
    await _channel.invokeMethod<void>('setChromeHidden', {'hidden': hidden});
  }

  // MARK: Native sheets

  /// True in an engine started by `runNativeSheet`, inside a native sheet.
  bool isSheetEngine = false;

  int _nextSheetId = 1;
  final Map<int, Completer<Object?>> _sheetResults = {};
  final Map<int, ValueChanged<int>> _sheetDetentHandlers = {};

  /// Starts a sheet engine at [entrypoint] ahead of time.
  Future<void> prewarmSheet(String entrypoint, {String? libraryUri}) async {
    if (!await ensureAttached()) return;
    await _channel.invokeMethod<void>('prewarmSheet', {'entrypoint': entrypoint, 'libraryUri': libraryUri});
  }

  /// Presents a native sheet; completes with its result when dismissed, or
  /// throws [StateError] if it couldn't be presented.
  Future<Object?> presentSheet(Map<String, Object?> config, {ValueChanged<int>? onDetentChanged}) async {
    if (!await ensureAttached()) throw StateError('Veneer overlay not attached');
    final id = _nextSheetId++;
    final completer = Completer<Object?>();
    _sheetResults[id] = completer;
    if (onDetentChanged != null) _sheetDetentHandlers[id] = onDetentChanged;
    final presented = await _channel.invokeMethod<bool>('presentSheet', {...config, 'id': id}) ?? false;
    if (!presented) {
      _sheetResults.remove(id);
      _sheetDetentHandlers.remove(id);
      throw StateError('Sheet could not be presented');
    }
    return completer.future;
  }

  /// From inside a native sheet: whether the content under a new touch is at
  /// its top edge, so UIKit knows whether a pull down drags the sheet.
  void setSheetContentAtTop(bool atTop) {
    if (!_attached) return;
    _channel.invokeMethod<void>('sheetContentAtTop', {'atTop': atTop});
  }

  /// From inside a native sheet: its content's height, for a content-sized
  /// detent. Sent before the sheet is presented too (it's laid out off
  /// screen to measure), so it doesn't wait for the overlay.
  void setSheetContentHeight(double height) {
    _channel.invokeMethod<void>('sheetContentHeight', {'height': height});
  }

  /// From inside a native sheet: the payload [presentSheet] was given,
  /// once the sheet is presented (a pre-warmed engine waits until then).
  Future<Object?> sheetPayload() => _channel.invokeMethod<Object?>('sheetPayload');

  /// From inside a native sheet: reads whether it's on screen now, for an
  /// engine whose app started after it was presented.
  Future<void> refreshSheetShown() async {
    try {
      sheetShown.value = await _channel.invokeMethod<bool>('sheetShown') ?? false;
    } on MissingPluginException {
      sheetShown.value = false;
    }
  }

  /// Frees a kept-alive sheet engine at [entrypoint] (after its sheet closes,
  /// if it's showing).
  Future<void> releaseSheet(String entrypoint, {String? libraryUri}) async {
    if (!await ensureAttached()) return;
    await _channel.invokeMethod<void>('releaseSheet', {'entrypoint': entrypoint, 'libraryUri': libraryUri});
  }

  /// In an engine that presents native sheets: answers their requests
  /// (`NativeSheet.request`), set through `NativeSheet.setRequestHandler`.
  SheetRequestHandler? sheetRequestHandler;

  /// From inside a native sheet: asks the engine that presented it, which
  /// answers with its [sheetRequestHandler].
  Future<Object?> sheetRequest(String name, Object? arguments) =>
      _channel.invokeMethod<Object?>('sheetRequest', {'name': name, 'arguments': arguments});

  /// From inside a native sheet: dismisses it with [result].
  Future<bool> dismissSheet(Object? result) async =>
      await _channel.invokeMethod<bool>('dismissSheet', {'result': result}) ?? false;

  Future<Map<String, Object?>> stats() async => await _channel.invokeMapMethod<String, Object?>('getStats') ?? const {};

  Future<void> resetStats() => _channel.invokeMethod<void>('resetStats');

  Future<Object?> _handleNativeCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    switch (call.method) {
      case 'shapeTapped':
        _shapeTapHandlers[args['id']]?.call();
      case 'shapeMenu':
        _shapeMenuHandlers[args['id']]?.call(args['index']! as int);
      case 'contextMenuItem':
        _contextMenuHandlers[args['id']]?.onSelected(args['index']! as int);
      case 'contextMenuShown':
        _contextMenuHandlers[args['id']]?.onOpenChanged(true);
      case 'contextMenuHidden':
        _contextMenuHandlers[args['id']]?.onOpenChanged(false);
      case 'tabSelected':
        _tabSelectedHandler?.call(args['index']! as int);
      case 'tabActionPressed':
        _tabActionHandler?.call();
      case 'chromeInsets':
        chromeBottomInset.value = (args['bottom']! as num).toDouble();
        chromeTopInset.value = ((args['top'] as num?) ?? 0).toDouble();
      case 'navItemPressed':
        _navItemHandler?.call(args['id']! as String);
      case 'composerButton':
        _composerHandlers?.onButton(args['id']! as String);
      case 'composerText':
        _composerHandlers?.onText(args['text']! as String, _selection(args));
      case 'composerSelection':
        if (_selection(args) case final selection?) _composerHandlers?.onSelection?.call(selection);
      case 'composerFocus':
        _composerHandlers?.onFocus(args['focused']! as bool);
      case 'composerSend':
        _composerHandlers?.onSend(args['text']! as String);
      case 'composerRecording':
        _composerHandlers?.onRecording?.call(args);
      case 'composerAttachmentRemoved':
        _composerHandlers?.onAttachmentRemoved?.call(args['id']! as String);
      case 'composerAttachmentTapped':
        _composerHandlers?.onAttachmentTapped?.call(args['id']! as String);
      case 'sheetDismissed':
        final id = args['id']! as int;
        _sheetDetentHandlers.remove(id);
        _sheetResults.remove(id)?.complete(args['result']);
      case 'sheetMaximumHeight':
        sheetMaximumHeight.value = (args['height']! as num).toDouble();
      case 'sheetPresented':
        sheetShown.value = true;
        _sheetPresentations.add(args['payload']);
      case 'sheetHidden':
        sheetShown.value = false;
      case 'sheetDetentChanged':
        _sheetDetentHandlers[args['id']! as int]?.call(args['detent']! as int);
      case 'sheetRequest':
        final handler = sheetRequestHandler;
        if (handler == null) {
          throw PlatformException(
            code: 'no_handler',
            message: 'The app that presented this sheet has no NativeSheet.setRequestHandler',
          );
        }
        return handler(args['name']! as String, args['arguments']);
      case 'composerLayout':
        composerHeight = (args['height']! as num).toDouble();
        _composerHandlers?.onLayout(
          composerHeight,
          Duration(microseconds: (((args['duration'] as num?) ?? 0) * 1e6).round()),
        );
    }
    return null;
  }
}

TextSelection? _selection(Map<Object?, Object?> args) {
  final start = args['selectionStart'];
  final end = args['selectionEnd'];
  if (start is! int || end is! int) return null;
  return TextSelection(baseOffset: start, extentOffset: end);
}

/// Callbacks from the native composer.
class VeneerContextMenuHandlers {
  const VeneerContextMenuHandlers({required this.onSelected, required this.onOpenChanged});

  /// An item was picked, by index in the menu sent.
  final ValueChanged<int> onSelected;

  /// The menu lifted (true) or finished dismissing (false).
  final ValueChanged<bool> onOpenChanged;
}

class VeneerComposerHandlers {
  const VeneerComposerHandlers({
    required this.onButton,
    required this.onText,
    required this.onFocus,
    required this.onSend,
    required this.onLayout,
    this.onAttachmentRemoved,
    this.onAttachmentTapped,
    this.onSelection,
    this.onRecording,
  });

  final ValueChanged<String> onButton;

  /// The text changed; with the selection after the change, when known.
  final void Function(String text, TextSelection? selection) onText;

  /// The selection moved without the text changing.
  final ValueChanged<TextSelection>? onSelection;
  final ValueChanged<bool> onFocus;
  final ValueChanged<String> onSend;

  /// Space above the keyboard/tab bar, and how long the change animates.
  final void Function(double height, Duration duration) onLayout;

  /// An attachment's remove button was tapped (prompt composer).
  final ValueChanged<String>? onAttachmentRemoved;

  /// An attachment with a tap handler was tapped (prompt composer).
  final ValueChanged<String>? onAttachmentTapped;

  /// Voice recording: `{state: started|finished|cancelled|failed, path,
  /// durationMs, reason}`.
  final ValueChanged<Map<String, Object?>>? onRecording;
}
