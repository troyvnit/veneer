import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoDynamicColor;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veneer/veneer.dart';

/// The Flutter replicas used where the native layer isn't available
/// (Android, iOS 15–25): same API, Flutter widgets, no platform calls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    VeneerBridge.instance.debugReset();
    VeneerBridge.instance.debugIsSupportedOverride = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('veneer'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
  });

  tearDown(() => VeneerBridge.instance.debugIsSupportedOverride = null);

  testWidgets('tab bar replica: tabs, badge, create-style trailing action, content padding', (tester) async {
    var selected = 0;
    var created = 0;
    late EdgeInsets contentPadding;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => NativeChromeScope(
            tabs: const [
              NativeTabItem(title: 'Chat', icon: NativeIcon.symbol('bubble.left')),
              NativeTabItem(title: 'Lab', icon: NativeIcon.icon(Icons.science), badge: '3'),
            ],
            trailingAction: NativeTabAction(
              icon: const NativeIcon.symbol('plus'),
              title: 'New',
              onPressed: () => created++,
            ),
            selectedIndex: selected,
            onTabSelected: (i) => setState(() => selected = i),
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

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'badge');
    expect(contentPadding.bottom, greaterThanOrEqualTo(61), reason: 'content scrolls under the floating bar');

    await tester.tap(find.text('Lab'));
    await tester.pumpAndSettle();
    expect(selected, 1);

    await tester.tap(find.bySemanticsLabel('New'));
    expect(created, 1);
    expect(selected, 1, reason: 'the create action does not change the selection');
    expect(calls, isEmpty, reason: 'no platform calls off iOS 26');
  });

  testWidgets('navigation bar replica: title, subtitle, buttons, top padding', (tester) async {
    var huddle = 0;
    late EdgeInsets contentPadding;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeNavigationBar(
          leading: const NativeBarButton(icon: NativeIcon.symbol('chevron.left'), title: 'Back'),
          title: const NativeBarTitle(title: 'launch-crew', subtitle: '6 members', capsule: true),
          trailing: [
            NativeBarButton(icon: const NativeIcon.symbol('headphones'), title: 'Huddle', onPressed: () => huddle++),
          ],
          child: Builder(
            builder: (context) {
              contentPadding = MediaQuery.paddingOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    expect(find.text('launch-crew'), findsOneWidget);
    expect(find.text('6 members'), findsOneWidget);
    expect(contentPadding.top, greaterThanOrEqualTo(44), reason: 'content starts below the floating bar');

    await tester.tap(find.bySemanticsLabel('Huddle'));
    expect(huddle, 1);
  });

  testWidgets('navigation bar replica: a titled button shows its icon and title in a capsule', (tester) async {
    var archived = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeNavigationBar(
          trailing: [
            NativeBarButton(
              icon: const NativeIcon.icon(Icons.archive_outlined),
              title: 'Archived',
              showsTitle: true,
              titleStyle: const TextStyle(fontWeight: FontWeight.w500),
              onPressed: () => archived++,
            ),
          ],
          child: const SizedBox.expand(),
        ),
      ),
    );
    final title = find.text('Archived');
    expect(title, findsOneWidget);
    expect(tester.widget<Text>(title).style?.fontWeight, FontWeight.w500);
    expect(tester.getSize(find.bySemanticsLabel('Archived')).width, greaterThan(44));

    await tester.tap(find.bySemanticsLabel('Archived'));
    expect(archived, 1);
  });

  test('a sheet request in the fallback calls the app handler directly', () async {
    NativeSheet.setRequestHandler((name, arguments) async => '$name:$arguments');
    addTearDown(() => NativeSheet.setRequestHandler(null));

    expect(await NativeSheet.request('token', 1), 'token:1');
    expect(calls.where((call) => call.method == 'sheetRequest'), isEmpty);
  });

  testWidgets('composer replica: same controller drives text, focus and send', (tester) async {
    final controller = NativeComposerController();
    final sent = <String>[];
    Widget app({double keyboard = 0}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: NativeComposer(
            controller: controller,
            placeholder: 'Message launch-crew',
            onSend: sent.add,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    expect(find.text('Message launch-crew'), findsOneWidget);

    controller.focus();
    await tester.pump();
    expect(controller.hasFocus, isTrue);

    controller.text = 'hello';
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'from the replica');
    expect(controller.text, 'from the replica');

    // Expanded (focused with the keyboard up): send is live.
    await tester.pumpWidget(app(keyboard: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump();
    expect(sent, ['from the replica']);
    expect(controller.text, isEmpty, reason: 'clearOnSend');

    controller.unfocus();
    await tester.pump();
    expect(controller.hasFocus, isFalse);
    expect(calls, isEmpty);
  });

  testWidgets('prompt composer replica: many attachments scroll inside the composer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800), padding: EdgeInsets.only(bottom: 34)),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: NativePromptComposer(
              attachments: [
                for (var i = 0; i < 12; i++)
                  NativeComposerAttachment(id: '$i', thumbnail: const NativeIcon.symbol('photo')),
              ],
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final strip = find.byType(ListView);
    expect(tester.widget<ListView>(strip).clipBehavior, Clip.hardEdge);
    final capsule = tester.getRect(find.byType(AnimatedContainer).first);
    final stripRect = tester.getRect(strip);
    expect(stripRect.left, greaterThanOrEqualTo(capsule.left));
    expect(stripRect.right, lessThanOrEqualTo(capsule.right));
  });

  testWidgets('prompt composer replica: unfocused, attachments fold into a count pill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800), padding: EdgeInsets.only(bottom: 34)),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: NativePromptComposer(
              leading: const NativeComposerButton(icon: NativeIcon.symbol('plus'), title: 'Add'),
              attachmentSummary: const NativeComposerAttachmentSummary(),
              attachments: const [
                NativeComposerAttachment(id: 'a', title: 'plan.pdf'),
                NativeComposerAttachment(id: 'b', title: 'site.jpg'),
              ],
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double capsuleHeight() => tester.getSize(find.byType(AnimatedContainer).first).height;
    expect(capsuleHeight(), 48, reason: 'one row while unfocused');
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('2 attachments'));
    await tester.pumpAndSettle();
    expect(capsuleHeight(), greaterThan(48), reason: 'focused, the attachments show again');
    expect(find.text('plan.pdf'), findsOneWidget);
  });

  testWidgets('prompt composer replica: an audio attachment is a full-width clip row', (tester) async {
    var toggled = 0;
    var removed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800), padding: EdgeInsets.only(bottom: 34)),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: NativePromptComposer(
              attachments: [
                NativeComposerAttachment(
                  id: 'clip',
                  onTap: () => toggled++,
                  onRemove: () => removed++,
                  audio: const NativeComposerAudio(waveform: [0.4, 0.9, 0.2], progress: 0.3, duration: '0:10'),
                ),
              ],
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final capsule = tester.getRect(find.byType(AnimatedContainer).first);
    final row = tester.getRect(find.ancestor(of: find.text('0:10'), matching: find.byType(Container)).first);
    expect(row.height, 56);
    expect(row.left - capsule.left, moreOrLessEquals(8, epsilon: 0.5), reason: 'inside the hairline border');
    expect(row.top - capsule.top, moreOrLessEquals(8, epsilon: 0.5));
    expect(capsule.right - row.right, moreOrLessEquals(8, epsilon: 0.5));
    expect(find.text('0:10'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Play'));
    expect(toggled, 1);
    await tester.tap(find.bySemanticsLabel('Remove'));
    expect(removed, 1);
  });

  testWidgets('prompt composer replica: voice button becomes send, side actions, attachments', (tester) async {
    final controller = NativeComposerController();
    final sent = <String>[];
    var voice = 0;
    var ended = 0;
    var removed = 0;
    var tapped = 0;
    Widget app({bool side = false, bool attached = false}) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800), padding: EdgeInsets.only(bottom: 34)),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: NativePromptComposer(
            controller: controller,
            placeholder: 'Ask anything',
            leading: const NativeComposerButton(icon: NativeIcon.symbol('plus'), title: 'Add'),
            actions: const [NativeComposerButton(icon: NativeIcon.symbol('mic'), title: 'Dictate')],
            primaryAction: NativeComposerButton(
              icon: const NativeIcon.symbol('waveform'),
              title: 'Voice mode',
              onPressed: () => voice++,
            ),
            sideActions: [
              NativeComposerButton(
                icon: const NativeIcon.symbol('xmark'),
                title: 'End',
                prominent: true,
                onPressed: () => ended++,
              ),
            ],
            showSideActions: side,
            attachments: [
              if (attached)
                NativeComposerAttachment(
                  id: 'f',
                  title: 'trip-plan.pdf',
                  subtitle: 'PDF',
                  thumbnail: const NativeIcon.symbol('doc.fill'),
                  onRemove: () => removed++,
                  onTap: () => tapped++,
                ),
            ],
            onSend: sent.add,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    expect(find.text('Ask anything'), findsOneWidget);
    final idleHeight = tester.getSize(find.byType(AnimatedContainer).first).height;
    expect(idleHeight, 48);

    await tester.tap(find.bySemanticsLabel('Voice mode'));
    expect(voice, 1);

    await tester.pumpWidget(app(side: true));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('End'));
    expect(ended, 1);

    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Send'), findsOneWidget, reason: 'the voice button turned into send');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    expect(sent, ['hello']);

    // A line break or an attachment switches to the taller multi-line layout.
    await tester.enterText(find.byType(TextField), 'one\ntwo');
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AnimatedContainer).first).height, greaterThan(idleHeight));

    await tester.pumpWidget(app(attached: true));
    await tester.pumpAndSettle();
    expect(find.text('trip-plan.pdf'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('trip-plan.pdf, PDF'));
    expect(tapped, 1);
    expect(removed, 0, reason: 'a tap on the attachment is not a remove');
    await tester.tap(find.bySemanticsLabel('Remove'));
    expect(removed, 1);
    expect(tapped, 1, reason: 'the remove button stays on top of the tap area');
    expect(calls, isEmpty);
  });

  testWidgets('native sheet: detents, drag to the next detent, drag down to dismiss', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final detents = <NativeSheetDetent>[];
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    showNativeSheet<void>(
      context: navigator.currentContext!,
      detents: const [NativeSheetDetent.medium, NativeSheetDetent.large],
      onDetentChanged: detents.add,
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: NativeNavigationBar(
          leading: NativeBarButton(
            icon: const NativeIcon.symbol('xmark'),
            title: 'Close',
            onPressed: () => closed = true,
          ),
          title: const NativeBarTitle(title: 'Sheet'),
          child: const Center(child: Text('content')),
        ),
      ),
    ).then((_) => closed = true);
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsOneWidget);

    final screen = tester.getSize(find.byType(Navigator)).height;
    double sheetTop() => tester.getTopLeft(find.text('Sheet')).dy;
    final mediumTop = sheetTop();
    expect(mediumTop, greaterThan(screen * 0.4), reason: 'opens at the first detent, medium');

    // Drag up past halfway: settles at large.
    await tester.drag(find.text('content'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(sheetTop(), lessThan(mediumTop - 200));
    expect(detents, [NativeSheetDetent.large]);

    // Drag all the way down: dismissed.
    await tester.drag(find.text('content'), Offset(0, screen));
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsNothing);
    expect(closed, isTrue);
  });

  testWidgets('glass shape replica with a menu opens the menu replica', (tester) async {
    var picked = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GlassShape(
            width: 44,
            height: 44,
            icon: const NativeIcon.symbol('ellipsis'),
            label: 'More',
            menu: [
              NativeMenuItem(title: 'Share', onSelected: () => picked = 'share'),
              NativeMenuItem(title: 'Delete', destructive: true, onSelected: () => picked = 'delete'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(GlassShape));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(picked, 'delete');
  });

  testWidgets('glass shape replica: label, icon and tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GlassShape(
            width: 160,
            height: 48,
            icon: const NativeIcon.symbol('star.fill'),
            label: 'Star',
            onTap: () => taps++,
          ),
        ),
      ),
    );
    expect(find.text('Star'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget, reason: 'SF Symbol mapped to Material');
    expect(tester.getSize(find.byType(GlassShape)), const Size(160, 48));
    await tester.tap(find.text('Star'));
    expect(taps, 1);
  });

  for (final large in [false, true]) {
    testWidgets('native sheet safe area (${large ? 'large' : 'floating'}): '
        'grabber on top, home indicator and keyboard less the sheet inset', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.reset);

      late MediaQueryData inside;
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('page'))));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            NativeSheetRoute<void>(
              detents: [large ? NativeSheetDetent.large : const NativeSheetDetent.height(300)],
              builder: (context) {
                inside = MediaQuery.of(context);
                return const SizedBox.expand();
              },
            ),
          );
      await tester.pumpAndSettle();

      final inset = large ? 0.0 : 8.0;
      expect(inside.padding.top, 6);
      expect(inside.padding.bottom, 34 - inset);
      expect(inside.viewPadding.bottom, 34 - inset);

      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pumpAndSettle();
      final keyboardInset = large ? 0.0 : 8.0;
      expect(inside.viewInsets.bottom, 336 - keyboardInset);
    });
  }

  testWidgets('a rising keyboard never squeezes a collapsed sheet below its content', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);

    const collapsed = 300.0;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('page'))));
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          NativeSheetRoute<void>(
            detents: const [NativeSheetDetent.height(collapsed), NativeSheetDetent.large],
            builder: (context) => Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: const Column(
                children: [
                  Expanded(child: SizedBox.expand()),
                  SizedBox(key: Key('bar'), height: 120),
                ],
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();

    double sheetHeight() =>
        tester.getBottomLeft(find.byKey(const Key('bar'))).dy - tester.getTopLeft(find.byType(Column)).dy;
    final before = sheetHeight();
    for (var keyboard = 0.0; keyboard <= 336; keyboard += 28) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      expect(sheetHeight(), greaterThanOrEqualTo(before - 0.5));
    }
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(Column)).dy, lessThan(80));
  });

  for (final large in [true, false]) {
    testWidgets('status bar over a ${large ? 'large' : 'floating'} sheet', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('page'))));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            NativeSheetRoute<void>(
              detents: [large ? NativeSheetDetent.large : const NativeSheetDetent.height(300)],
              builder: (context) => const SizedBox.expand(),
            ),
          );
      await tester.pumpAndSettle();

      final regions = tester
          .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(find.byType(AnnotatedRegion<SystemUiOverlayStyle>))
          .where((r) => r.value.statusBarIconBrightness == Brightness.light);
      expect(regions, large ? isNotEmpty : isEmpty);
    });
  }

  testWidgets('dragging a sheet across the status bar switch keeps its content and settles', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);

    var mounts = 0;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('page'))));
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          NativeSheetRoute<void>(
            detents: const [NativeSheetDetent.height(300), NativeSheetDetent.large],
            initialDetent: NativeSheetDetent.large,
            builder: (context) => _MountCounter(onMount: () => mounts++),
          ),
        );
    await tester.pumpAndSettle();
    expect(mounts, 1);

    await tester.drag(find.byType(_MountCounter), const Offset(0, 420));
    await tester.pumpAndSettle();

    expect(mounts, 1);
    expect(tester.getTopLeft(find.byType(_MountCounter)).dy, greaterThan(852 - 300 - 30));
    final light = tester
        .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(find.byType(AnnotatedRegion<SystemUiOverlayStyle>))
        .where((r) => r.value.statusBarIconBrightness == Brightness.light);
    expect(light, isEmpty);
  });

  for (final chosen in [true, false]) {
    testWidgets('a floating sheet is ${chosen ? 'solid in its chosen colour' : 'translucent by default'}', (
      tester,
    ) async {
      const colour = Color(0xFFF7F7F8);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('page'))));
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            NativeSheetRoute<void>(
              detents: const [NativeSheetDetent.height(300)],
              backgroundColor: chosen ? colour : null,
              builder: (context) => const SizedBox.expand(),
            ),
          );
      await tester.pumpAndSettle();

      final surfaces = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .map((b) => b.color)
          .where((c) => c.a > 0.5 && (c.r > 0.9));
      expect(surfaces, chosen ? contains(colour) : isNot(contains(colour)));
      if (!chosen) expect(surfaces.any((c) => c.a < 1), isTrue);
      expect(find.byWidgetPredicate((w) => w is BackdropFilter && w.enabled), chosen ? findsNothing : findsOneWidget);
    });
  }

  testWidgets('a dynamic sheet colour follows the theme while the sheet is open', (tester) async {
    const light = Color(0xFFFFFFFF);
    const dark = Color(0xFF1B1B1D);
    Widget app(ThemeMode mode) => MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      themeMode: mode,
      home: const Scaffold(body: Text('page')),
    );
    await tester.pumpWidget(app(ThemeMode.dark));
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          NativeSheetRoute<void>(
            detents: const [NativeSheetDetent.height(300)],
            backgroundColor: const CupertinoDynamicColor.withBrightness(color: light, darkColor: dark),
            builder: (context) => const SizedBox.expand(),
          ),
        );
    await tester.pumpAndSettle();
    Iterable<Color> surfaces() => tester.widgetList<ColoredBox>(find.byType(ColoredBox)).map((b) => b.color);
    expect(surfaces(), contains(dark));

    await tester.pumpWidget(app(ThemeMode.light));
    await tester.pumpAndSettle();
    expect(surfaces(), contains(light));
    expect(surfaces(), isNot(contains(dark)));
  });

  testWidgets('a content-sized sheet follows its content as it grows', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);

    var extent = 120.0;
    late StateSetter grow;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('page'))));
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          NativeSheetRoute<void>(
            detents: const [NativeSheetDetent.content()],
            builder: (context) => StatefulBuilder(
              builder: (context, setState) {
                grow = setState;
                return SizedBox(key: const Key('content'), height: extent);
              },
            ),
          ),
        );
    await tester.pumpAndSettle();
    double top() => tester.getTopLeft(find.byKey(const Key('content'))).dy;
    final before = top();

    grow(() => extent = 320);
    await tester.pumpAndSettle();
    expect(top(), lessThan(before - 150));
  });

  testWidgets('a sheet under another sheet steps back behind it and returns', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('page'))));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      NativeSheetRoute<void>(showGrabber: true, builder: (context) => const SizedBox.expand(key: Key('back'))),
    );
    await tester.pumpAndSettle();
    final alone = tester.getRect(find.byKey(const Key('back')));
    double grabberOpacity() => tester.widgetList<Opacity>(find.byType(Opacity)).first.opacity;
    expect(grabberOpacity(), 1);

    navigator.push(
      NativeSheetRoute<void>(
        detents: const [NativeSheetDetent.content()],
        builder: (context) => const SizedBox(key: Key('front'), height: 700),
      ),
    );
    await tester.pumpAndSettle();
    final behind = tester.getRect(find.byKey(const Key('back')));
    expect(behind.top, moreOrLessEquals(alone.top));
    expect(behind.width, moreOrLessEquals(alone.width * 0.91));
    expect(grabberOpacity(), 0);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('back'))), alone);
    expect(grabberOpacity(), 1);
  });

  testWidgets('a large sheet meets the status bar, and one over it stops 10pt lower', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('page'))));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(NativeSheetRoute<void>(builder: (context) => const SizedBox.expand(key: Key('first'))));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('first'))).top, 59);

    navigator.push(NativeSheetRoute<void>(builder: (context) => const SizedBox.expand(key: Key('second'))));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('second'))).top, 69);
    expect(tester.getRect(find.byKey(const Key('first'))).top, moreOrLessEquals(59));
  });

  testWidgets('the replica bar fades its content only once scrolled under it', (tester) async {
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
    double fade() => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(fade(), 0);

    controller.jumpTo(200);
    await tester.pumpAndSettle();
    expect(fade(), 1);

    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(fade(), 0);
  });

  testWidgets('prompt composer replica: caret, replaceRange and highlighted mentions', (tester) async {
    final controller = NativeComposerController();
    const tint = Color(0xFF5B5BD6);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: NativePromptComposer(
            controller: controller,
            tintColor: tint,
            highlights: const ['@Kat QA', '@Kat QA Technician'],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hi @ka');
    await tester.pump();
    expect(controller.text, 'Hi @ka');
    expect(controller.selection.baseOffset, 6);

    controller.replaceRange(3, 6, '@Kat QA Technician ');
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Hi @Kat QA Technician ');
    expect(field.controller!.selection, const TextSelection.collapsed(offset: 22));

    final span = field.controller!.buildTextSpan(context: tester.element(find.byType(TextField)), withComposing: false);
    final tinted = span.children!.whereType<TextSpan>().where((c) => c.style?.color == tint).map((c) => c.text);
    expect(tinted, ['@Kat QA Technician'], reason: 'the longer mention wins over the one inside it');
  });

  testWidgets('a style\'s shadows replace the default under fallback surfaces', (tester) async {
    const shadows = [BoxShadow(color: Color(0x14000000), offset: Offset(0, 8), blurRadius: 16, spreadRadius: -4)];
    final style = VeneerFallbackStyle.iosLight.copyWith(shadows: shadows);
    expect(style.surfaceDecoration().boxShadow, shadows);
    expect(VeneerFallbackStyle.iosLight.surfaceDecoration().boxShadow!.single.blurRadius, 24);
    expect(style.lerp(style, 0.5).shadow.single.blurRadius, 16);
  });

  test('isSupported needs iOS 26: the test host is not', () {
    VeneerBridge.instance.debugIsSupportedOverride = null;
    expect(Veneer.isSupported, isFalse);
  });

  testWidgets('context menu replica opens on long press', (tester) async {
    var picked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: NativeContextMenu(
            items: [NativeMenuItem(title: 'Copy', onSelected: () => picked = true)],
            child: const SizedBox(width: 200, height: 60, child: Text('bubble')),
          ),
        ),
      ),
    );
    await tester.longPress(find.text('bubble'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(picked, isTrue);
    expect(calls, isEmpty);
  });

  testWidgets('voice recording on the replica reports it is unavailable', (tester) async {
    final controller = NativeComposerController();
    NativeVoiceRecordingFailure? failure;
    await tester.pumpWidget(
      MaterialApp(
        home: NativePromptComposer(
          controller: controller,
          onVoiceRecordingFailed: (reason) => failure = reason,
          child: const SizedBox.expand(),
        ),
      ),
    );
    controller.startVoiceRecording();
    expect(failure, NativeVoiceRecordingFailure.unavailable);
    expect(controller.isRecording, isFalse);
  });

  testWidgets('a controller sends a Flutter sheet messages and closes it with a result', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('page'))));
    final controller = NativeSheetController();
    final messages = <Object?>[];
    Object? result;
    unawaited(
      showNativeSheet<Object?>(
        context: tester.element(find.text('page')),
        controller: controller,
        builder: (context) => _MessageLog(stream: NativeSheet.messages(context), into: messages),
      ).then((r) => result = r),
    );
    await tester.pumpAndSettle();
    expect(controller.isOpen, isTrue);

    await controller.send('refreshed');
    await tester.pump();
    expect(messages, ['refreshed']);

    await controller.close('done');
    await tester.pumpAndSettle();
    expect(result, 'done');
    expect(controller.isOpen, isFalse);
    expect(find.byType(_MessageLog), findsNothing);
  });
}

class _MountCounter extends StatefulWidget {
  const _MountCounter({required this.onMount});

  final VoidCallback onMount;

  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _MessageLog extends StatefulWidget {
  const _MessageLog({required this.stream, required this.into});

  final Stream<Object?> stream;
  final List<Object?> into;

  @override
  State<_MessageLog> createState() => _MessageLogState();
}

class _MessageLogState extends State<_MessageLog> {
  late final StreamSubscription<Object?> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.stream.listen(widget.into.add);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
