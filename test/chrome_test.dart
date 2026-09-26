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
            NativeNavigationBar(title: NativeBarTitle(title: 'hidden')),
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
