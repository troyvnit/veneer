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
              NativeBarButton(icon: const NativeIcon.symbol('headphones'), title: 'Huddle', onPressed: () => huddle++),
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

    // Rebuilding with an identical bar (e.g. every keyboard frame) sends nothing.
    await tester.pumpWidget(page(1));
    await tester.pumpAndSettle();
    expect(sent('setNavigationBar'), hasLength(1));

    await nativeEvent('navItemPressed', {'id': 'trailing1'});
    expect(huddle, 1);
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

  testWidgets('prompt composer: config, menus, side actions and attachment removal', variant: ios, (tester) async {
    final events = <String>[];
    var removed = 0;
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

    for (final id in ['leading.menu0', 'action0', 'primary', 'side0']) {
      await nativeEvent('composerButton', {'id': id});
    }
    expect(events, ['photos', 'dictate', 'voice', 'mute']);

    await nativeEvent('composerAttachmentRemoved', {'id': 'p1'});
    expect(removed, 1);

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
