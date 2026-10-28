import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veneer/veneer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    VeneerBridge.instance.debugReset();
    VeneerBridge.instance.debugIsSupportedOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('veneer'),
      (call) async {
        calls.add(call);
        return call.method == 'attach' ? <String, Object?>{} : null;
      },
    );
  });

  tearDown(() => VeneerBridge.instance.debugIsSupportedOverride = null);

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  Future<void> native(String method, Map<String, Object?> args) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'veneer',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  List<Map<String, Object?>> configs() => [
    for (final c in calls.where((c) => c.method == 'setSearchToolbar')) (c.arguments as Map).cast<String, Object?>(),
  ];

  List<Object?> commands() => [
    for (final c in calls.where((c) => c.method == 'searchToolbarCommand')) (c.arguments as Map)['command'],
  ];

  testWidgets('shows the native bar, then focuses it once it exists', variant: ios, (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativeSearchToolbar(placeholder: 'Search places', child: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    expect(configs().single, {'placeholder': 'Search places', 'text': '', 'hidden': false});
    final setIndex = calls.indexWhere((c) => c.method == 'setSearchToolbar');
    final focusIndex = calls.indexWhere((c) => c.method == 'searchToolbarCommand');
    expect(focusIndex, greaterThan(setIndex));
    expect(commands(), ['focus']);
  });

  testWidgets('native edits reach the controller without echoing back', variant: ios, (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];
    final submits = <String>[];
    final focus = <bool>[];
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeSearchToolbar(
          placeholder: 'Search',
          controller: controller,
          autofocus: false,
          onChanged: changes.add,
          onSubmitted: submits.add,
          onFocusChanged: focus.add,
          onClose: () => closed++,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await native('searchToolbar', {'kind': 'focus', 'value': true});
    await native('searchToolbar', {'kind': 'text', 'value': 'kitchen'});
    await native('searchToolbar', {'kind': 'submit', 'value': 'kitchen'});
    await native('searchToolbar', {'kind': 'close', 'value': true});

    expect(controller.text, 'kitchen');
    expect(changes, ['kitchen']);
    expect(submits, ['kitchen']);
    expect(focus, [true]);
    expect(closed, 1);
    expect(commands(), isEmpty);

    controller.text = 'sink';
    await tester.pump();
    final setText = calls.lastWhere((c) => c.method == 'searchToolbarCommand').arguments as Map;
    expect(setText, {'command': 'setText', 'text': 'sink'});
  });

  testWidgets('pads the child for the space the bar reports', variant: ios, (tester) async {
    late double bottom;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeSearchToolbar(
          placeholder: 'Search',
          autofocus: false,
          child: Builder(
            builder: (context) {
              bottom = MediaQuery.paddingOf(context).bottom;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await native('searchToolbarLayout', {'bottom': 380.0});
    await tester.pumpAndSettle();

    expect(bottom, 380);
  });

  testWidgets('hides the bar while its page is covered and removes it with the page', variant: ios, (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const NativeSearchToolbar(placeholder: 'Search', autofocus: false, child: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
    await tester.pumpAndSettle();
    expect(configs().last['hidden'], isTrue);
    expect(calls.where((c) => c.method == 'removeSearchToolbar'), isEmpty);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(configs().last['hidden'], isFalse);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'removeSearchToolbar'), hasLength(1));
  });

  testWidgets('falls back to a Flutter search field and close button', (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = false;
    var closed = 0;
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeSearchToolbar(
            placeholder: 'Search',
            closeLabel: 'Close',
            autofocus: false,
            onChanged: changes.add,
            onClose: () => closed++,
            child: const SizedBox(),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'roof');
    await tester.tap(find.bySemanticsLabel('Close'));

    expect(changes, ['roof']);
    expect(closed, 1);
    expect(calls.where((c) => c.method == 'setSearchToolbar'), isEmpty);
  });
}
