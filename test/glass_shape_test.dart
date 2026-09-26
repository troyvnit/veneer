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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('veneer'),
      (call) async {
        calls.add(call);
        // No applyFrameAddress: the bridge falls back to the channel transport.
        return call.method == 'attach' ? <String, Object?>{} : null;
      },
    );
  });

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('GlassShape occupies its size and streams geometry', variant: ios, (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: 10, top: 20),
            child: GlassShape(width: 120, height: 44, icon: NativeIcon.symbol('star'), label: 'Star'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();

    expect(tester.getSize(find.byType(GlassShape)), const Size(120, 44));

    final configure = calls.firstWhere((c) => c.method == 'configureShape');
    expect((configure.arguments as Map)['icon'], {'type': 'symbol', 'name': 'star'});

    final frame = calls.lastWhere((c) => c.method == 'applyFrame').arguments as Float64List;
    // [frameNumber, count, id, x, y, w, h, visible]
    expect(frame[1], 1);
    expect(frame.sublist(3, 8), [10, 20, 120, 44, 1]);
  });

  testWidgets('GlassShape inside a non-selected IndexedStack child is hidden', variant: ios, (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: IndexedStack(
          index: 0,
          children: [
            SizedBox(),
            Center(child: GlassShape(width: 50, height: 50)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();

    final frame = calls.lastWhere((c) => c.method == 'applyFrame').arguments as Float64List;
    expect(frame[7], 0, reason: 'visible flag');
  });

  Map<String, Object?> shapeConfig(String label) => calls
      .where((c) => c.method == 'configureShape')
      .map((c) => (c.arguments as Map).cast<String, Object?>())
      .lastWhere((a) => a['label'] == label);

  testWidgets('shapes join their GlassGroup, others share the route group', variant: ios, (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: const [
            GlassShape(width: 40, height: 40, label: 'a'),
            GlassShape(width: 40, height: 40, label: 'b'),
            GlassGroup(zIndex: 1, spacing: 8, child: GlassShape(width: 40, height: 40, label: 'c')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final a = shapeConfig('a')['group']! as int;
    final b = shapeConfig('b')['group']! as int;
    final c = shapeConfig('c')['group']! as int;
    expect(a, b, reason: 'ungrouped shapes on one route share its default group');
    expect(a, isNegative, reason: 'route default group ids are negative');
    expect(c, isNot(a));

    final groupCall = calls.indexWhere((m) => m.method == 'configureGroup');
    final cCall = calls.indexWhere((m) => m.method == 'configureShape' && (m.arguments as Map)['label'] == 'c');
    expect(groupCall, lessThan(cCall), reason: 'group must exist natively before its first shape');
    expect((calls[groupCall].arguments as Map)['id'], c);
    expect((calls[groupCall].arguments as Map)['zIndex'], 1);
  });

  testWidgets('re-parenting a shape into a group keeps its id and changes its group', variant: ios, (tester) async {
    final key = GlobalKey();
    Widget build({required bool grouped}) {
      final shape = GlassShape(key: key, width: 40, height: 40, label: 'm');
      return MaterialApp(
        home: Center(child: grouped ? GlassGroup(child: shape) : shape),
      );
    }

    await tester.pumpWidget(build(grouped: false));
    await tester.pumpAndSettle();
    final before = shapeConfig('m');

    await tester.pumpWidget(build(grouped: true));
    await tester.pumpAndSettle();
    final after = shapeConfig('m');

    expect(after['id'], before['id']);
    expect(after['group'], isNot(before['group']));
    expect(calls.where((m) => m.method == 'removeShape'), isEmpty);
  });
}
