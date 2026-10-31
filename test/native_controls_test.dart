import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veneer/veneer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final veneerCalls = <MethodCall>[];
  final controlCalls = <String, List<MethodCall>>{};
  var nextViewId = 0;

  setUp(() {
    veneerCalls.clear();
    controlCalls.clear();
    VeneerBridge.instance.debugReset();
    messenger.setMockMethodCallHandler(const MethodChannel('veneer'), (call) async {
      veneerCalls.add(call);
      return call.method == 'showAlert' ? 1 : null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      if (call.method != 'create') return null;
      final args = call.arguments as Map;
      final channel = '${args['viewType']}_${args['id']}';
      nextViewId = args['id'] as int;
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        controlCalls.putIfAbsent(channel, () => []).add(call);
        return null;
      });
      return null;
    });
  });

  tearDown(() => VeneerBridge.instance.debugIsSupportedOverride = null);

  Future<void> nativeEvent(String channel, String method, Map<String, Object?> args) => messenger.handlePlatformMessage(
    channel,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );

  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  Future<void> pumpLtr(WidgetTester tester, Widget child) =>
      tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: child));

  testWidgets('native switch: a UISwitch configured from Dart, controlled like Flutter\'s', variant: ios, (
    tester,
  ) async {
    VeneerBridge.instance.debugIsSupportedOverride = true;
    var value = false;
    final changes = <bool>[];
    late StateSetter setState;
    await pumpLtr(
      tester,
      Center(
        child: StatefulBuilder(
          builder: (context, set) {
            setState = set;
            return NativeSwitch(
              value: value,
              activeColor: const Color(0xFF5047B8),
              onChanged: (next) => changes.add(next),
            );
          },
        ),
      ),
    );
    await tester.pump();

    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'veneer/switch');
    expect(view.creationParams, {'value': false, 'enabled': true, 'activeColor': 0xFF5047B8, 'thumbColor': null});
    expect(tester.getSize(find.byType(NativeSwitch)), const Size(63, 29));

    final channel = 'veneer/switch_$nextViewId';
    await nativeEvent(channel, 'valueChanged', {'value': true});
    expect(changes, [true]);
    await tester.pump();
    expect(
      controlCalls[channel]!.last.arguments,
      containsPair('value', false),
      reason: 'the parent kept false, so the switch is put back',
    );

    setState(() => value = true);
    await tester.pump();
    expect(controlCalls[channel]!.last.arguments, containsPair('value', true));
  });

  testWidgets('native slider: range, enabled, and start/change/end events', variant: ios, (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = true;
    final events = <String>[];
    await pumpLtr(
      tester,
      Center(
        child: SizedBox(
          width: 200,
          child: NativeSlider(
            value: 1,
            max: 4,
            onChangeStart: (v) => events.add('start $v'),
            onChanged: (v) => events.add('change $v'),
            onChangeEnd: (v) => events.add('end $v'),
          ),
        ),
      ),
    );
    await tester.pump();

    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'veneer/slider');
    expect((view.creationParams! as Map)['max'], 4.0);
    expect(tester.getSize(find.byType(NativeSlider)), const Size(200, 31));

    final channel = 'veneer/slider_$nextViewId';
    await nativeEvent(channel, 'changeStart', {'value': 1.0});
    await nativeEvent(channel, 'valueChanged', {'value': 2.5});
    await nativeEvent(channel, 'changeEnd', {'value': 3.0});
    expect(events, ['start 1.0', 'change 2.5', 'end 3.0']);
  });

  testWidgets('native segmented control: labels, colours and picks', variant: ios, (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = true;
    final picks = <int>[];
    await pumpLtr(
      tester,
      Center(
        child: SizedBox(
          width: 240,
          child: NativeSegmentedControl(
            labels: const ['Member', 'Admin'],
            selectedIndex: 0,
            selectedColor: const Color(0xFFFFFFFF),
            textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500),
            selectedTextStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
            height: 40,
            onValueChanged: picks.add,
          ),
        ),
      ),
    );
    await tester.pump();

    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'veneer/segmented');
    expect((view.creationParams! as Map)['labels'], ['Member', 'Admin']);
    expect((view.creationParams! as Map)['font'], {'family': 'Inter', 'size': 15.0, 'weight': 500});
    expect((view.creationParams! as Map)['selectedFont'], {'family': 'Inter', 'size': 15.0, 'weight': 600});
    expect(tester.getSize(find.byType(NativeSegmentedControl)), const Size(240, 40));

    await nativeEvent('veneer/segmented_$nextViewId', 'valueChanged', {'index': 1});
    expect(picks, [1]);
  });

  testWidgets('menu anchor inside a Flutter-drawn sheet: a platform-view UIMenu button', variant: ios, (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = true;
    var picked = -1;
    await pumpLtr(
      tester,
      VeneerFallbackScope(
        child: Center(
          child: NativeMenuAnchor(
            title: 'Add',
            items: [
              NativeMenuItem(title: 'Take a photo', onSelected: () => picked = 0),
              NativeMenuItem(title: 'Upload a file', onSelected: () => picked = 1),
            ],
            child: const SizedBox(width: 60, height: 32),
          ),
        ),
      ),
    );
    await tester.pump();

    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'veneer/menu');
    expect((view.creationParams! as Map)['menuTitle'], 'Add');
    expect(((view.creationParams! as Map)['menu']! as List).map((item) => (item as Map)['title']), [
      'Take a photo',
      'Upload a file',
    ]);
    expect(tester.getSize(find.byType(UiKitView)), const Size(60, 32));
    expect(veneerCalls.where((call) => call.method == 'configureShape'), isEmpty);

    await nativeEvent('veneer/menu_$nextViewId', 'menuItem', {'index': 1});
    expect(picked, 1);
  });

  testWidgets('menu anchor outside a fallback scope stays on the overlay', variant: ios, (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = true;
    await pumpLtr(
      tester,
      Center(
        child: NativeMenuAnchor(
          items: [NativeMenuItem(title: 'Share', onSelected: () {})],
          child: const SizedBox(width: 60, height: 32),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(UiKitView), findsNothing);
    expect(veneerCalls.where((call) => call.method == 'configureShape'), isNotEmpty);
  });

  testWidgets('navigation bar inside a Flutter-drawn sheet: the real bar as a platform view', variant: ios, (
    tester,
  ) async {
    VeneerBridge.instance.debugIsSupportedOverride = true;
    var closed = 0;
    late EdgeInsets contentPadding;
    await pumpLtr(
      tester,
      MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: VeneerFallbackScope(
          child: NativeNavigationBar(
            leading: NativeBarButton(icon: const NativeIcon.symbol('xmark'), onPressed: () => closed++),
            title: const NativeBarTitle(title: 'New Event'),
            child: Builder(
              builder: (context) {
                contentPadding = MediaQuery.paddingOf(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'veneer/navbar');
    final config = view.creationParams! as Map;
    expect((config['leading'] as Map)['id'], 'leading');
    expect((config['title'] as Map)['title'], 'New Event');
    expect(config['hidden'], isFalse);
    expect(find.text('New Event'), findsNothing, reason: 'the native bar draws the title, not the replica');
    expect(contentPadding.top, greaterThan(40), reason: 'content still starts below the bar');
    expect(veneerCalls.where((call) => call.method == 'setNavigationBar'), isEmpty);

    await nativeEvent('veneer/navbar_$nextViewId', 'navItemPressed', {'id': 'leading'});
    expect(closed, 1);
  });

  testWidgets('native alert: sent to UIKit, answers with the picked index', variant: ios, (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = true;
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    final picked = await showNativeAlert(
      context: context,
      title: 'Delete?',
      message: 'This can\'t be undone.',
      tint: const Color(0xFF5047B8),
      actions: const [
        NativeAlertAction(title: 'Delete', style: NativeAlertActionStyle.destructive, preferred: true),
        NativeAlertAction(title: 'Cancel', style: NativeAlertActionStyle.cancel),
      ],
    );
    expect(picked, 1);
    expect(veneerCalls.single.method, 'showAlert');
    expect(veneerCalls.single.arguments, {
      'title': 'Delete?',
      'message': 'This can\'t be undone.',
      'tint': 0xFF5047B8,
      'actions': [
        {'title': 'Delete', 'style': 'destructive', 'preferred': true},
        {'title': 'Cancel', 'style': 'cancel', 'preferred': false},
      ],
    });
  });

  testWidgets('replicas: Cupertino controls and alert off iOS 26', (tester) async {
    VeneerBridge.instance.debugIsSupportedOverride = false;
    var on = false;
    var segment = 0;
    late BuildContext context;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (c) {
            context = c;
            return Column(
              children: [
                NativeSwitch(value: on, onChanged: (v) => on = v),
                NativeSlider(value: 0.5, onChanged: (_) {}),
                NativeSegmentedControl(labels: const ['A', 'B'], selectedIndex: 0, onValueChanged: (i) => segment = i),
              ],
            );
          },
        ),
      ),
    );
    expect(find.byType(UiKitView), findsNothing);
    expect(find.byType(CupertinoSwitch), findsOneWidget);
    expect(find.byType(CupertinoSlider), findsOneWidget);
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(on, isTrue);
    expect(segment, 1);

    final result = showNativeAlert(
      context: context,
      title: 'Leave?',
      actions: const [
        NativeAlertAction(title: 'Stay'),
        NativeAlertAction(title: 'Leave', preferred: true),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(await result, 1);
  });
}
