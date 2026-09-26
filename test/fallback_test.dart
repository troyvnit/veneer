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

  testWidgets('prompt composer replica: voice button becomes send, side actions, attachments', (tester) async {
    final controller = NativeComposerController();
    final sent = <String>[];
    var voice = 0;
    var ended = 0;
    var removed = 0;
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
    await tester.tap(find.bySemanticsLabel('Remove'));
    expect(removed, 1);
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

  test('isSupported needs iOS 26: the test host is not', () {
    VeneerBridge.instance.debugIsSupportedOverride = null;
    expect(Veneer.isSupported, isFalse);
  });
}
