import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veneer/veneer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);
  const channel = MethodChannel('veneer');

  setUp(() {
    calls.clear();
    VeneerBridge.instance.debugReset();
    VeneerBridge.instance.debugIsSupportedOverride = true; // the test host isn't iOS 26
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'attach' ? <String, Object?>{} : null;
    });
  });

  /// Delivers a native → Dart event on the plugin channel.
  Future<void> nativeEvent(String method, Map<String, Object?> args) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'veneer',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  Iterable<Map<Object?, Object?>> sent(String method) =>
      calls.where((c) => c.method == method).map((c) => c.arguments as Map<Object?, Object?>);

  testWidgets('navigation bar sends its items once, and routes taps back', variant: ios, (tester) async {
    var huddle = 0;
    Widget page(int rebuild) => MaterialApp(
      home: Column(
        children: [
          Text('$rebuild'),
          NativeNavigationBar(
            leading: const NativeBarButton(icon: NativeIcon.symbol('chevron.left'), title: 'Back'),
            title: const NativeBarTitle(title: 'launch-crew', subtitle: '6 members', capsule: true),
            trailing: [
              const NativeBarButton(icon: NativeIcon.symbol('square.grid.2x2'), title: 'Apps'),
              NativeBarButton(
                icon: const NativeIcon.symbol('headphones'),
                title: 'Huddle',
                prominent: true,
                tint: const Color(0xFF6B4EFF),
                onPressed: () => huddle++,
              ),
            ],
            child: const SizedBox(),
          ),
        ],
      ),
    );

    await tester.pumpWidget(page(0));
    await tester.pumpAndSettle();
    final config = sent('setNavigationBar').single;
    expect(config['hidden'], isFalse);
    expect((config['title']! as Map)['capsule'], isTrue);
    expect([for (final b in config['trailing']! as List) (b as Map)['title']], ['Apps', 'Huddle']);
    expect([for (final b in config['trailing']! as List) (b as Map)['tint']], [null, 0xFF6B4EFF]);

    // Rebuilding with an identical bar (e.g. every keyboard frame) sends nothing.
    await tester.pumpWidget(page(1));
    await tester.pumpAndSettle();
    expect(sent('setNavigationBar'), hasLength(1));

    await nativeEvent('navItemPressed', {'id': 'trailing1'});
    expect(huddle, 1);
  });

  testWidgets('a titled bar button sends its title and title style', variant: ios, (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativeNavigationBar(
          trailing: [
            NativeBarButton(
              icon: NativeIcon.symbol('archivebox'),
              title: 'Archived',
              showsTitle: true,
              titleStyle: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w500),
            ),
            NativeBarButton(icon: NativeIcon.symbol('ellipsis'), title: 'More', group: 1),
          ],
          child: SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trailing = sent('setNavigationBar').single['trailing']! as List;
    final archived = trailing.first as Map;
    expect(archived['showsTitle'], isTrue);
    expect(archived['titleStyle'], {'family': 'Inter', 'size': 17.0, 'weight': 500, 'height': null, 'color': null});
    expect((trailing.last as Map)['showsTitle'], isFalse);
    expect((trailing.last as Map)['titleStyle'], isNull);
  });

  testWidgets('navigation bar on a hidden IndexedStack page never shows', variant: ios, (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IndexedStack(
          index: 0,
          children: [
            SizedBox(),
            NativeNavigationBar(
              title: NativeBarTitle(title: 'hidden'),
              child: SizedBox(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sent('setNavigationBar'), isEmpty);
  });

  testWidgets('composer pads content above the keyboard or tab bar, whichever is higher', variant: ios, (tester) async {
    late MediaQueryData inner;
    Widget app({required double keyboard}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          padding: const EdgeInsets.only(bottom: 80), // tab bar inset from NativeChromeScope
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: NativeComposer(
          placeholder: 'Message launch-crew',
          child: Builder(
            builder: (context) {
              inner = MediaQuery.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(keyboard: 0));
    await tester.pumpAndSettle();
    expect(sent('setComposer').single['placeholder'], 'Message launch-crew');
    expect(sent('setComposer').single['interactiveDismissal'], isTrue, reason: 'on by default');

    await nativeEvent('composerLayout', {'height': 53.0, 'duration': 0.0});
    await tester.pumpAndSettle();
    expect(inner.padding.bottom, 80 + 53, reason: 'idle: above the tab bar');

    await tester.pumpWidget(app(keyboard: 300));
    await nativeEvent('composerLayout', {'height': 113.0, 'duration': 0.0});
    await tester.pumpAndSettle();
    expect(inner.padding.bottom, 300 + 113, reason: 'focused: above the keyboard');
    expect(inner.viewInsets.bottom, 0, reason: 'keyboard inset consumed, so inner Scaffolds do not resize again');
  });

  testWidgets('composer controller mirrors native text and focus', variant: ios, (tester) async {
    final controller = NativeComposerController();
    String? sentText;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeComposer(controller: controller, onSend: (t) => sentText = t, child: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    await nativeEvent('composerFocus', {'focused': true});
    await nativeEvent('composerText', {'text': 'hello'});
    expect(controller.hasFocus, isTrue);
    expect(controller.text, 'hello');

    await nativeEvent('composerSend', {'text': 'hello'});
    expect(sentText, 'hello');
    expect(controller.text, isEmpty, reason: 'clearOnSend');

    controller.unfocus();
    await tester.pump();
    expect(calls.last.method, 'composerCommand');
    expect((calls.last.arguments as Map)['command'], 'unfocus');
  });

  testWidgets('composer controller follows the native caret and completes a mention', variant: ios, (tester) async {
    final controller = NativeComposerController();
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NativePromptComposer(
          controller: controller,
          highlights: const ['@Kat QA'],
          onChanged: changes.add,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sent('setComposer').last['highlights'], ['@Kat QA']);

    await nativeEvent('composerText', {'text': 'Hi @ka there', 'selectionStart': 6, 'selectionEnd': 6});
    expect(controller.text, 'Hi @ka there');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    expect(changes, ['Hi @ka there']);

    await nativeEvent('composerSelection', {'selectionStart': 2, 'selectionEnd': 5});
    expect(controller.selection, const TextSelection(baseOffset: 2, extentOffset: 5));
    expect(changes, hasLength(1), reason: 'moving the caret is not a text change');

    await nativeEvent('composerSelection', {'selectionStart': 6, 'selectionEnd': 6});
    controller.replaceRange(3, 6, '@Kat QA ');
    await tester.pump();
    expect(controller.text, 'Hi @Kat QA  there');
    expect(controller.selection, const TextSelection.collapsed(offset: 11));
    final command = calls.last.arguments as Map;
    expect(command['command'], 'setText');
    expect(command['text'], 'Hi @Kat QA  there');
    expect([command['selectionStart'], command['selectionEnd']], [11, 11]);
  });

  testWidgets('prompt composer: an attachment summary is sent with the config', variant: ios, (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativePromptComposer(
          attachmentSummary: NativeComposerAttachmentSummary(
            icon: NativeIcon.symbol('paperclip'),
            foregroundColor: Color(0xFF000000),
          ),
          child: SizedBox(),
        ),
      ),
    );
    await tester.pump();

    expect(sent('setComposer').single['attachmentSummary'], {
      'icon': const NativeIcon.symbol('paperclip').encode(),
      'backgroundColor': null,
      'foregroundColor': 0xFF000000,
    });
  });

  testWidgets('prompt composer: an audio attachment sends its clip state', variant: ios, (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativePromptComposer(
          attachments: [
            NativeComposerAttachment(
              id: 'clip',
              onTap: () {},
              audio: const NativeComposerAudio(
                waveform: [0.2, 0.123456, 1.5],
                progress: 0.5,
                playing: true,
                duration: '0:10',
                backgroundColor: Color(0x0A000000),
              ),
            ),
          ],
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();

    final attachment = (sent('setComposer').single['attachments']! as List).single as Map;
    expect(attachment['tappable'], isTrue);
    expect(attachment['audio'], {
      'waveform': [0.2, 0.123, 1.0],
      'progress': 0.5,
      'playing': true,
      'duration': '0:10',
      'playIcon': null,
      'pauseIcon': null,
      'removeIcon': null,
      'backgroundColor': 0x0A000000,
      'waveColor': null,
      'labelColor': null,
    });
  });

  testWidgets('prompt composer: config, menus, side actions and attachment removal', variant: ios, (tester) async {
    final events = <String>[];
    var removed = 0;
    var tapped = 0;
    Widget page({bool voice = false, bool attached = true}) => MaterialApp(
      home: NativePromptComposer(
        placeholder: 'Ask anything',
        leading: NativeComposerButton(
          icon: const NativeIcon.symbol('plus'),
          title: 'Add',
          menu: [NativeMenuItem(title: 'Photos', onSelected: () => events.add('photos'))],
        ),
        actions: [NativeComposerButton(icon: const NativeIcon.symbol('mic'), onPressed: () => events.add('dictate'))],
        primaryAction: NativeComposerButton(
          icon: const NativeIcon.symbol('waveform'),
          onPressed: () => events.add('voice'),
        ),
        sideActions: [
          NativeComposerButton(icon: const NativeIcon.symbol('mic.slash'), onPressed: () => events.add('mute')),
          NativeComposerButton(icon: const NativeIcon.symbol('xmark'), prominent: true, onPressed: () {}),
        ],
        showSideActions: voice,
        attachments: [
          if (attached)
            NativeComposerAttachment(
              id: 'p1',
              thumbnail: const NativeIcon.image('assets/lake.jpg'),
              onRemove: () => removed++,
              onTap: () => tapped++,
            ),
        ],
        child: const SizedBox(),
      ),
    );

    await tester.pumpWidget(page());
    await tester.pump();
    final config = sent('setComposer').single;
    expect(config['style'], 'prompt');
    expect(config['sideShown'], isFalse);
    expect((config['leading']! as Map)['menu'], [
      {'title': 'Photos', 'icon': null, 'destructive': false},
    ]);
    expect((config['side']! as List).last, containsPair('prominent', true));
    expect(
      (config['attachments']! as List).single,
      containsPair('thumbnail', {'type': 'imageAsset', 'asset': 'assets/lake.jpg', 'package': null}),
    );
    expect((config['attachments']! as List).single, containsPair('tappable', true));

    for (final id in ['leading.menu0', 'action0', 'primary', 'side0']) {
      await nativeEvent('composerButton', {'id': id});
    }
    expect(events, ['photos', 'dictate', 'voice', 'mute']);

    await nativeEvent('composerAttachmentRemoved', {'id': 'p1'});
    expect(removed, 1);

    await nativeEvent('composerAttachmentTapped', {'id': 'p1'});
    expect(tapped, 1);

    await tester.pumpWidget(page(voice: true));
    await tester.pump();
    expect(sent('setComposer').last['sideShown'], isTrue, reason: 'side actions split off');
  });

  testWidgets('a route pushed over the tab bar page hides the bar, popping shows it', variant: ios, (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: NativeChromeScope(
          tabs: const [NativeTabItem(title: 'Home', icon: NativeIcon.symbol('house'))],
          selectedIndex: 0,
          onTabSelected: (_) {},
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
    await tester.pumpAndSettle();
    expect(sent('setChromeHidden').last['hidden'], isTrue);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(sent('setChromeHidden').last['hidden'], isFalse);
  });

  testWidgets('replacing the tab bar page with another keeps the new bar', variant: ios, (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final picked = <String>[];
    Widget scope(String name) => NativeChromeScope(
      tabs: [NativeTabItem(title: name, icon: const NativeIcon.symbol('house'))],
      selectedIndex: 0,
      onTabSelected: (_) => picked.add(name),
      child: const SizedBox(),
    );
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: scope('old')));
    await tester.pumpAndSettle();

    calls.clear();
    navigator.currentState!.pushReplacement(MaterialPageRoute<void>(builder: (_) => scope('new')));
    await tester.pumpAndSettle();

    final tabBarCalls = calls.where((c) => c.method == 'setTabBar' || c.method == 'removeTabBar').toList();
    expect(tabBarCalls.last.method, 'setTabBar');
    expect((((tabBarCalls.last.arguments as Map)['items'] as List).single as Map)['title'], 'new');
    expect(sent('setChromeHidden').lastOrNull?['hidden'] ?? false, isFalse);
    await nativeEvent('tabSelected', {'index': 0});
    expect(picked, ['new']);
  });

  testWidgets('a scope inside a route over another scope hands the bar back when it goes', variant: ios, (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final picked = <String>[];
    Widget scope(String name) => NativeChromeScope(
      tabs: [NativeTabItem(title: name, icon: const NativeIcon.symbol('house'))],
      selectedIndex: 0,
      onTabSelected: (_) => picked.add(name),
      child: const SizedBox(),
    );
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: scope('first')));
    await tester.pumpAndSettle();
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => scope('second')));
    await tester.pumpAndSettle();

    calls.clear();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    final tabBarCalls = calls.where((c) => c.method == 'setTabBar' || c.method == 'removeTabBar').toList();
    expect(tabBarCalls.last.method, 'setTabBar');
    expect((((tabBarCalls.last.arguments as Map)['items'] as List).single as Map)['title'], 'first');
    expect(sent('setChromeHidden').lastOrNull?['hidden'] ?? false, isFalse);
    await nativeEvent('tabSelected', {'index': 0});
    expect(picked, ['first']);
  });

  testWidgets('a fresh attach shows chrome a previous isolate left hidden', variant: ios, (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeChromeScope(
          tabs: const [NativeTabItem(title: 'Home', icon: NativeIcon.symbol('house'))],
          selectedIndex: 0,
          onTabSelected: (_) {},
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sent('setChromeHidden').map((a) => a['hidden']), [false]);
  });

  testWidgets('a native sheet sends content-sized detents as their own type', variant: ios, (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    unawaited(
      showNativeSheet<void>(
        context: context,
        entrypoint: 'sheet',
        detents: const [NativeSheetDetent.content(), NativeSheetDetent.large],
        initialDetent: NativeSheetDetent.large,
        builder: (_) => const SizedBox(),
      ),
    );
    await tester.pump();
    final args = sent('presentSheet').single;
    expect(args['detents'], [
      {'type': 'content'},
      {'type': 'large'},
    ]);
    expect(args['initialDetent'], 1);
  });

  testWidgets('a kept-alive sheet asks native to retain its engine, and can be released', variant: ios, (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    unawaited(
      showNativeSheet<void>(context: context, entrypoint: 'sheet', keepAlive: true, builder: (_) => const SizedBox()),
    );
    unawaited(showNativeSheet<void>(context: context, entrypoint: 'other', builder: (_) => const SizedBox()));
    await tester.pump();
    expect(sent('presentSheet').map((a) => a['retain']), [true, false]);

    await NativeSheet.release('sheet');
    expect(sent('releaseSheet').single, {'entrypoint': 'sheet', 'libraryUri': null});
  });

  test('in a sheet engine, a request goes to the presenting app and returns its answer', () async {
    VeneerBridge.instance.isSheetEngine = true;
    addTearDown(() => VeneerBridge.instance.isSheetEngine = false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'sheetRequest' ? 'jwt-1' : null;
    });

    final answer = await NativeSheet.request('token', {'scope': 'api'});

    expect(answer, 'jwt-1');
    expect(sent('sheetRequest').single, {
      'name': 'token',
      'arguments': {'scope': 'api'},
    });
  });

  Future<Object?> askFromSheet(String name, Object? arguments) async {
    final reply = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'veneer',
      const StandardMethodCodec().encodeMethodCall(MethodCall('sheetRequest', {'name': name, 'arguments': arguments})),
      reply.complete,
    );
    return const StandardMethodCodec().decodeEnvelope((await reply.future)!);
  }

  test('the presenting app answers a sheet request with its handler', () async {
    final asked = <(String, Object?)>[];
    NativeSheet.setRequestHandler((name, arguments) async {
      asked.add((name, arguments));
      return {'jwt': 'jwt-2'};
    });
    addTearDown(() => NativeSheet.setRequestHandler(null));

    expect(await askFromSheet('token', null), {'jwt': 'jwt-2'});
    expect(asked, [('token', null)]);
  });

  test('a sheet request without a handler in the app fails with no_handler', () async {
    expect(askFromSheet('token', null), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'no_handler')));
  });

  testWidgets('in a sheet engine, shown and presented follow the sheet coming and going', variant: ios, (tester) async {
    final payloads = <Object?>[];
    final subscription = NativeSheet.presented.listen(payloads.add);
    addTearDown(subscription.cancel);
    expect(NativeSheet.shown.value, isFalse);

    await nativeEvent('sheetPresented', {
      'payload': {'screen': 'visit_detail'},
    });
    await tester.pump();
    expect(NativeSheet.shown.value, isTrue);

    await nativeEvent('sheetHidden', {});
    expect(NativeSheet.shown.value, isFalse, reason: 'closed, while its app keeps running');

    await nativeEvent('sheetPresented', {'payload': null});
    await tester.pump();
    expect(NativeSheet.shown.value, isTrue);
    expect(payloads, [
      {'screen': 'visit_detail'},
      null,
    ]);
  });

  testWidgets('a controller sends the open native sheet messages and closes it', variant: ios, (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'attach' => <String, Object?>{},
        'presentSheet' || 'sendToSheet' || 'dismissSheet' => true,
        _ => null,
      };
    });
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final controller = NativeSheetController();
    Object? result;
    unawaited(
      showNativeSheet<Object?>(
        context: tester.element(find.byType(SizedBox)),
        entrypoint: 'sheet',
        controller: controller,
        builder: (_) => const SizedBox(),
      ).then((r) => result = r),
    );
    await tester.pump();
    expect(controller.isOpen, isTrue);
    final id = sent('presentSheet').single['id'];

    await controller.send({'busy': true});
    expect(sent('sendToSheet').single, {
      'id': id,
      'message': {'busy': true},
    });

    await controller.close('done');
    expect(sent('dismissSheet').single, {'id': id, 'result': 'done'});
    await nativeEvent('sheetDismissed', {'id': id, 'result': 'done'});
    await tester.pump();
    expect(result, 'done');
    expect(controller.isOpen, isFalse);
  });

  testWidgets('in a sheet engine, appeared turns true once the sheet has slid up', variant: ios, (tester) async {
    VeneerBridge.instance.isSheetEngine = true;
    addTearDown(() => VeneerBridge.instance.isSheetEngine = false);
    var waited = false;
    unawaited(NativeSheet.untilAppeared().then((_) => waited = true));

    await nativeEvent('sheetPresented', {'payload': null});
    await tester.pump();
    expect((NativeSheet.appeared.value, waited), (false, false));

    await nativeEvent('sheetAppeared', {});
    await tester.pump();
    expect((NativeSheet.appeared.value, waited), (true, true));

    await nativeEvent('sheetHidden', {});
    expect(NativeSheet.appeared.value, isFalse);
  });

  test('outside a native sheet, untilAppeared completes at once', () async {
    await NativeSheet.untilAppeared();
    expect(NativeSheet.appeared.value, isFalse);
  });

  testWidgets('in a sheet engine, messages from the app arrive in NativeSheet.messages', variant: ios, (tester) async {
    VeneerBridge.instance.isSheetEngine = true;
    addTearDown(() => VeneerBridge.instance.isSheetEngine = false);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final messages = <Object?>[];
    final subscription = NativeSheet.messages(tester.element(find.byType(SizedBox))).listen(messages.add);
    addTearDown(subscription.cancel);

    await nativeEvent('sheetMessage', {
      'message': {'busy': false},
    });
    await tester.pump();
    expect(messages, [
      {'busy': false},
    ]);
  });

  testWidgets('in a sheet engine, NativeSheetContent reports its height above the home indicator', variant: ios, (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    VeneerBridge.instance.isSheetEngine = true;
    addTearDown(() => VeneerBridge.instance.isSheetEngine = false);

    var extent = 200.0;
    late StateSetter grow;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeSheetContent(
          child: StatefulBuilder(
            builder: (context, setState) {
              grow = setState;
              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                child: SizedBox(height: extent),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(sent('sheetContentHeight').last['height'], 200);

    grow(() => extent = 260);
    await tester.pump();
    await tester.pump();
    expect(sent('sheetContentHeight').last['height'], 260);
  });

  testWidgets('NativeSheetContent reports nothing until its view has a width', variant: ios, (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(0, 852);
    tester.view.display.size = const Size(393, 852);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.display.reset);
    VeneerBridge.instance.isSheetEngine = true;
    addTearDown(() => VeneerBridge.instance.isSheetEngine = false);

    // Squeezed to no width, wrapping content grows as tall as the screen.
    await tester.pumpWidget(
      MaterialApp(
        home: NativeSheetContent(
          child: LayoutBuilder(
            builder: (context, constraints) => SizedBox(height: constraints.maxWidth > 0 ? 120 : 852),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(sent('sheetContentHeight'), isEmpty);

    tester.view.physicalSize = const Size(393, 852);
    await tester.pump();
    await tester.pump();
    expect(sent('sheetContentHeight').map((call) => call['height']), [120]);
  });

  testWidgets('NativeSheetContent measures past a sheet that is still too short for it', variant: ios, (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 300);
    tester.view.display.size = const Size(393, 852);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.display.reset);
    VeneerBridge.instance.isSheetEngine = true;
    addTearDown(() => VeneerBridge.instance.isSheetEngine = false);

    await tester.pumpWidget(const MaterialApp(home: NativeSheetContent(child: SizedBox(height: 520))));
    await tester.pump();
    expect(sent('sheetContentHeight').last['height'], 520);
  });

  testWidgets('NativeSheetContent taller than its sheet scrolls within the sheet', variant: ios, (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 790);
    tester.view.display.size = const Size(393, 852);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.display.reset);
    VeneerBridge.instance.isSheetEngine = true;
    addTearDown(() => VeneerBridge.instance.isSheetEngine = false);

    await tester.pumpWidget(
      MaterialApp(
        home: NativeSheetContent(
          child: ListView(children: [for (var i = 0; i < 30; i++) SizedBox(height: 60, child: Text('row $i'))]),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(ListView)).height, moreOrLessEquals(790, epsilon: 0.1));

    await tester.dragUntilVisible(find.text('row 29'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('row 29')).dy, lessThanOrEqualTo(790.1));
  });

  testWidgets('the bar edge effect follows content scrolled under it', variant: ios, (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NativeNavigationBar(
          title: const NativeBarTitle(title: 'Page'),
          child: ListView(
            controller: controller,
            children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i'))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sent('setNavigationBar').last['scrolled'], isFalse);

    controller.jumpTo(200);
    await tester.pump();
    expect(sent('navigationBarScrolled').last['scrolled'], isTrue);

    controller.jumpTo(0);
    await tester.pump();
    expect(sent('navigationBarScrolled').last['scrolled'], isFalse);
    expect(sent('navigationBarScrolled').length, 2);
  });

  testWidgets('an explicit scrolled state drives the edge effect instead of the child', variant: ios, (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Widget page({required bool scrolled}) => MaterialApp(
      home: NativeNavigationBar(
        title: const NativeBarTitle(title: 'Page'),
        scrolled: scrolled,
        child: ListView(
          controller: controller,
          children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i'))],
        ),
      ),
    );

    await tester.pumpWidget(page(scrolled: true));
    await tester.pumpAndSettle();
    expect(sent('setNavigationBar').last['scrolled'], isTrue);

    controller.jumpTo(200);
    controller.jumpTo(0);
    await tester.pump();
    expect(sent('navigationBarScrolled'), isEmpty, reason: 'the child no longer decides');

    await tester.pumpWidget(page(scrolled: false));
    await tester.pump();
    expect(sent('navigationBarScrolled').single['scrolled'], isFalse);
  });

  testWidgets('NativeSheetContent keeps its height while the sheet grows to it', variant: ios, (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 466);
    tester.view.display.size = const Size(393, 852);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.display.reset);
    VeneerBridge.instance.isSheetEngine = true;
    addTearDown(() => VeneerBridge.instance.isSheetEngine = false);
    VeneerBridge.instance.sheetMaximumHeight.value = 780;
    addTearDown(() => VeneerBridge.instance.sheetMaximumHeight.value = null);

    await tester.pumpWidget(
      const MaterialApp(
        home: NativeSheetContent(
          child: Column(mainAxisSize: MainAxisSize.min, children: [SizedBox(height: 520)]),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Column)).height, 520);
    expect(sent('sheetContentHeight').last['height'], 520);
  });

  testWidgets('glass shape menus are sent natively and picks come back', (tester) async {
    var picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GlassShape(
            width: 44,
            height: 44,
            icon: const NativeIcon.symbol('ellipsis'),
            menu: [
              NativeMenuItem(title: 'Share', onSelected: () => picked = 0),
              NativeMenuItem(title: 'Delete', destructive: true, onSelected: () => picked = 1),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final config = sent('configureShape').last;
    expect((config['menu']! as List).last, {'title': 'Delete', 'icon': null, 'destructive': true});
    await nativeEvent('shapeMenu', {'id': config['id'], 'index': 1});
    expect(picked, 1);
  });

  testWidgets('context menu registers its region, picks come back, and the child hides while it is up', (tester) async {
    var picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NativeContextMenu(
            borderRadius: BorderRadius.circular(16),
            items: [
              NativeMenuItem(title: 'Reply', onSelected: () => picked = 0),
              NativeMenuItem(title: 'Delete', destructive: true, onSelected: () => picked = 1),
            ],
            child: const SizedBox(width: 200, height: 60, child: Text('bubble')),
          ),
        ),
      ),
    );
    await tester.pump();
    final config = sent('configureContextMenu').last;
    expect(config['radii'], [16.0, 16.0, 16.0, 16.0]);
    expect((config['menu']! as List).first, {'title': 'Reply', 'icon': null, 'destructive': false});

    await nativeEvent('contextMenuShown', {'id': config['id']});
    await tester.pump();
    expect(tester.widget<Opacity>(find.ancestor(of: find.text('bubble'), matching: find.byType(Opacity))).opacity, 0);
    await nativeEvent('contextMenuItem', {'id': config['id'], 'index': 1});
    await nativeEvent('contextMenuHidden', {'id': config['id']});
    await tester.pump();
    expect(picked, 1);
    expect(tester.widget<Opacity>(find.ancestor(of: find.text('bubble'), matching: find.byType(Opacity))).opacity, 1);

    await tester.pumpWidget(const SizedBox());
    expect(sent('removeContextMenu').single['id'], config['id']);
  });

  testWidgets('voice recording: commands go native, the clip comes back', variant: ios, (tester) async {
    final controller = NativeComposerController();
    NativeVoiceRecording? clip;
    await tester.pumpWidget(
      MaterialApp(
        home: NativePromptComposer(
          controller: controller,
          recordingCancelLabel: 'Cancel',
          recordingDoneLabel: 'Done',
          onVoiceRecorded: (recording) => clip = recording,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(sent('setComposer').last['recordingDoneLabel'], 'Done');

    controller.startVoiceRecording(maxDuration: const Duration(minutes: 2));
    await tester.pump();
    expect(sent('composerCommand').last, containsPair('command', 'startRecording'));
    expect(sent('composerCommand').last['maxDuration'], 120.0);

    await nativeEvent('composerRecording', {'state': 'started'});
    expect(controller.isRecording, isTrue);
    await nativeEvent('composerRecording', {'state': 'finished', 'path': '/tmp/voice.m4a', 'durationMs': 2500});
    expect(controller.isRecording, isFalse);
    expect(clip?.path, '/tmp/voice.m4a');
    expect(clip?.duration, const Duration(milliseconds: 2500));
  });

  testWidgets('a composer taking over the native view sends its own text', variant: ios, (tester) async {
    final first = NativeComposerController(text: '@');
    final second = NativeComposerController();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: NativePromptComposer(controller: first, child: const SizedBox.expand()),
      ),
    );
    await tester.pump();
    calls.clear();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => NativePromptComposer(controller: second, child: const SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();
    expect(sent('composerCommand').where((c) => c['command'] == 'setText').last['text'], '');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(sent('composerCommand').where((c) => c['command'] == 'setText').last['text'], '@');
  });

  test('tab bar rejects more items than UIKit shows without a More tab', () {
    expect(
      () => NativeChromeScope(
        tabs: [for (var i = 0; i < 5; i++) NativeTabItem(title: '$i', icon: const NativeIcon.symbol('circle'))],
        trailingAction: NativeTabAction(icon: const NativeIcon.symbol('plus'), onPressed: () {}),
        selectedIndex: 0,
        onTabSelected: (_) {},
        child: const SizedBox(),
      ),
      throwsAssertionError,
    );
  });
}
