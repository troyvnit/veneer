import 'package:flutter/foundation.dart';
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

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  Future<void> native(String method, Map<String, Object?> args) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'veneer',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  Map<String, Object?> lastSearchConfig() => calls
      .where((c) => c.method == 'configureShape')
      .map((c) => (c.arguments as Map).cast<String, Object?>())
      .lastWhere((a) => a['search'] != null);

  testWidgets('configures a search shape and streams its geometry', variant: ios, (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 300, child: NativeSearchField(placeholder: 'Search emoji')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();

    final config = lastSearchConfig();
    expect(config['interactive'], isTrue);
    expect(config['search'], {'placeholder': 'Search emoji', 'text': ''});

    final frame = calls.lastWhere((c) => c.method == 'applyFrame').arguments as Float64List;
    expect(frame.sublist(5, 7), [300, 44]);
  });

  testWidgets('native edits reach the controller without echoing back', variant: ios, (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];
    final submits = <String>[];
    final focus = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NativeSearchField(
          placeholder: 'Search',
          controller: controller,
          onChanged: changes.add,
          onSubmitted: submits.add,
          onFocusChanged: focus.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final id = lastSearchConfig()['id']!;
    final configures = calls.where((c) => c.method == 'configureShape').length;

    await native('shapeSearch', {'id': id, 'kind': 'focus', 'value': true});
    await native('shapeSearch', {'id': id, 'kind': 'text', 'value': 'wav'});
    await native('shapeSearch', {'id': id, 'kind': 'submit', 'value': 'wav'});

    expect(controller.text, 'wav');
    expect(changes, ['wav']);
    expect(submits, ['wav']);
    expect(focus, [true]);
    expect(calls.where((c) => c.method == 'configureShape').length, configures);

    controller.clear();
    await tester.pump();
    expect(lastSearchConfig()['search'], {'placeholder': 'Search', 'text': ''});
  });

  testWidgets('focus and unfocus drive the native field', variant: ios, (tester) async {
    final key = GlobalKey<NativeSearchFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: NativeSearchField(key: key, placeholder: 'Search'),
      ),
    );
    await tester.pumpAndSettle();
    final id = lastSearchConfig()['id'];

    key.currentState!.focus();
    key.currentState!.unfocus();
    await tester.pump();

    final commands = calls.where((c) => c.method == 'searchCommand').map((c) => c.arguments).toList();
    expect(commands, [
      {'id': id, 'command': 'focus'},
      {'id': id, 'command': 'blur'},
    ]);
  });

  testWidgets('falls back to a Flutter field with a clear button', (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = false;
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeSearchField(placeholder: 'Search', onChanged: changes.add),
        ),
      ),
    );

    expect(find.text('Search'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsNothing);

    await tester.enterText(find.byType(TextField), 'fire');
    await tester.pump();
    expect(changes, ['fire']);

    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();
    expect(changes, ['fire', '']);
    expect(find.text('fire'), findsNothing);
    expect(calls.where((c) => c.method == 'configureShape'), isEmpty);
  });
}
