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

  const segments = [
    GlassSegment(icon: NativeIcon.symbol('clock')),
    GlassSegment(icon: NativeIcon.symbol('leaf')),
    GlassSegment(label: '✋'),
  ];

  Map<String, Object?> lastConfig() => calls
      .where((c) => c.method == 'configureShape')
      .map((c) => (c.arguments as Map).cast<String, Object?>())
      .lastWhere((a) => a['segments'] != null);

  Future<void> native(String method, Map<String, Object?> args) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'veneer',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  testWidgets('sends its segments and sizes itself from them', variant: ios, (tester) async {
    final picked = <int>[];
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return GlassSegmentBar(
                segments: segments,
                selectedIndex: selected,
                segmentWidth: 36,
                height: 40,
                onSelected: picked.add,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(GlassSegmentBar)), const Size(36 * 3 + 8, 40));
    final config = lastConfig();
    final sent = config['segments']! as Map;
    expect(sent['selected'], 0);
    expect(sent['items'], [
      {
        'icon': {'type': 'symbol', 'name': 'clock'},
        'label': null,
      },
      {
        'icon': {'type': 'symbol', 'name': 'leaf'},
        'label': null,
      },
      {'icon': null, 'label': '✋'},
    ]);

    await native('shapeSegment', {'id': config['id'], 'index': 2});
    await native('shapeSegment', {'id': config['id'], 'index': 9});
    expect(picked, [2]);

    update(() => selected = 2);
    await tester.pump();
    expect((lastConfig()['segments']! as Map)['selected'], 2);
  });

  testWidgets('falls back to a Flutter capsule that highlights the selection', (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = false;
    final picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GlassSegmentBar(segments: segments, selectedIndex: 1, segmentWidth: 36, onSelected: picked.add),
        ),
      ),
    );

    await tester.tap(find.text('✋'));
    expect(picked, [2]);
    expect(calls.where((c) => c.method == 'configureShape'), isEmpty);

    final highlight = tester.getRect(find.byType(AnimatedPositioned));
    final bar = tester.getRect(find.byType(GlassSegmentBar));
    expect(highlight.left - bar.left, GlassSegmentBar.padding + 36);
  });
}
