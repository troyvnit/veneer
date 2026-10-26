import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veneer/veneer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  const channel = MethodChannel('veneer');
  var shown = true;

  setUp(() {
    calls.clear();
    shown = true;
    VeneerBridge.instance.debugReset();
    VeneerBridge.instance.debugIsSupportedOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'showBanner' ? shown : null;
    });
  });

  tearDown(() => VeneerBridge.instance.debugIsSupportedOverride = null);

  Future<void> nativeEvent(String method, Map<String, Object?> args) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'veneer',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  test('sends the content and style, and routes the tap and dismissal back', () async {
    final events = <String>[];
    final result = await showNativeBanner(
      title: 'Your response is ready',
      subtitle: 'Leaky faucet',
      body: 'Thursday works.',
      trailing: '10:41 AM',
      icon: const NativeIcon.symbol('sparkles'),
      badge: const NativeIcon.symbol('exclamationmark.circle.fill'),
      bodyMaxLines: 2,
      duration: const Duration(milliseconds: 4500),
      style: const NativeBannerStyle(
        dark: true,
        titleStyle: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, height: 20 / 15),
        tint: Color(0xCCF5F5F5),
      ),
      onTap: () => events.add('tap'),
      onDismissed: () => events.add('dismissed'),
    );

    expect(result, isTrue);
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['title'], 'Your response is ready');
    expect(args['trailing'], '10:41 AM');
    expect(args['bodyMaxLines'], 2);
    expect(args['duration'], 4.5);
    expect(args['dark'], isTrue);
    expect(args['tint'], 0xCCF5F5F5);
    expect((args['titleStyle']! as Map)['weight'], 500);
    expect((args['icon']! as Map)['name'], 'sparkles');

    final id = args['id'];
    await nativeEvent('bannerTapped', {'id': id});
    await nativeEvent('bannerDismissed', {'id': id});
    await nativeEvent('bannerDismissed', {'id': id});
    expect(events, ['tap', 'dismissed']);
  });

  test('answers false without calling native code where it is unsupported', () async {
    VeneerBridge.instance.debugIsSupportedOverride = false;
    expect(await showNativeBanner(title: 'Hi'), isFalse);
    await hideNativeBanner();
    expect(calls, isEmpty);
  });

  test('forgets the handlers of a banner native code refused', () async {
    shown = false;
    var dismissed = 0;
    expect(await showNativeBanner(title: 'Hi', onDismissed: () => dismissed++), isFalse);
    await nativeEvent('bannerDismissed', {'id': (calls.single.arguments as Map)['id']});
    expect(dismissed, 0);
  });
}
