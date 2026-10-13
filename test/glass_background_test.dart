import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veneer/veneer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platformViewCalls = <MethodCall>[];

  setUp(() {
    platformViewCalls.clear();
    VeneerBridge.instance.debugReset();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('veneer'), (call) async {
      return call.method == 'attach' ? <String, Object?>{} : null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      platformViewCalls.add(call);
      return null;
    });
  });

  tearDown(() => VeneerBridge.instance.debugIsSupportedOverride = null);

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('native: a glass platform view sized to the child, under it', variant: ios, (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = true;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GlassBackground(cornerRadius: 20, child: SizedBox(width: 200, height: 60, child: Text('dock'))),
        ),
      ),
    );
    await tester.pump();

    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'veneer/glass_background');
    expect(view.creationParams, {'style': 'regular', 'tint': null, 'cornerRadius': 20.0, 'tappable': false});
    expect(view.hitTestBehavior, PlatformViewHitTestBehavior.transparent);
    expect(tester.getSize(find.byType(UiKitView)), const Size(200, 60));
    expect(find.text('dock'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('dock')),
      tester.getTopLeft(find.byType(UiKitView)),
      reason: 'the child is laid over the glass',
    );
  });

  testWidgets('native: stays glass inside a fallback scope (a Flutter-drawn sheet)', variant: ios, (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = true;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: VeneerFallbackScope(
          child: Center(child: GlassBackground(child: SizedBox(width: 80, height: 40))),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(UiKitView), findsOneWidget);
  });

  testWidgets('native: a tappable background takes the tap natively and reports it', variant: ios, (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = true;
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GlassBackground(onTap: () => taps++, child: const SizedBox(width: 44, height: 44)),
        ),
      ),
    );
    await tester.pump();

    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect((view.creationParams! as Map)['tappable'], isTrue);
    expect((view.creationParams! as Map)['cornerRadius'], isNull, reason: 'capsule');
    expect(view.hitTestBehavior, PlatformViewHitTestBehavior.opaque);

    final created = platformViewCalls.firstWhere((call) => call.method == 'create');
    final id = (created.arguments as Map)['id'] as int;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'veneer/glass_background_$id',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('tap')),
      (_) {},
    );
    expect(taps, 1);
  });

  testWidgets('replica: the fallback surface around the child, tappable when asked', (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = false;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GlassBackground(
            tint: const Color(0xFF112233),
            cornerRadius: 12,
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 40, child: Text('pill')),
          ),
        ),
      ),
    );

    expect(find.byType(UiKitView), findsNothing);
    final box = tester.widget<DecoratedBox>(
      find.ancestor(of: find.text('pill'), matching: find.byType(DecoratedBox)).first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF112233));
    expect(decoration.borderRadius, BorderRadius.circular(12));
    await tester.tap(find.text('pill'));
    expect(taps, 1);
  });
}
