import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:veneer/veneer.dart';

import 'app_icons.dart';
import 'app_state.dart';
import 'data/travel.dart';
import 'pages/assistant_page.dart';
import 'pages/components_page.dart';
import 'pages/explore_page.dart';
import 'pages/journal_page.dart';
import 'pages/stay_sheet.dart';
import 'pages/sync_test_page.dart';
import 'pages/trips_page.dart';

/// Launch arguments (see ios/Runner/AppDelegate.swift) let
/// `tool/measure_sync.py` runs be scripted:
///   -VENEER_TRANSPORT ffi|channel|delayedChannel
///   -VENEER_MEASURE 1   → Sync page starts in measure mode, auto-scrolling
bool launchMeasureMode = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = await const MethodChannel('example/launch_config').invokeMapMethod<String, String?>('get');
    final transport = config?['transport'];
    if (transport != null) VeneerBridge.instance.transport = VeneerTransport.values.byName(transport);
    launchMeasureMode = config?['measure'] == '1';
    // -VENEER_FALLBACK 1: preview the Android / iOS 15–25 UI on iOS 26.
    Veneer.debugForceFallback = config?['fallback'] == '1';
  } on MissingPluginException {
    // Not running the example's iOS runner.
  }
  runApp(const ExampleApp());
}

/// The assistant sheet's own engine (see `openAssistant`): on iOS 26 the
/// sheet is a real UIKit sheet, and its Flutter content starts here.
@pragma('vm:entry-point')
void assistantSheet() => runNativeSheet(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: exampleTheme(Brightness.light),
    darkTheme: exampleTheme(Brightness.dark),
    home: const AssistantPage(),
  ),
);

/// The stay sheet's own engine (see `openStaySheet`); the place arrives as
/// the sheet's payload.
@pragma('vm:entry-point')
void staySheet() => runNativeSheet(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: exampleTheme(Brightness.light),
    darkTheme: exampleTheme(Brightness.dark),
    home: const StaySheet(),
  ),
);

ThemeData exampleTheme(Brightness brightness) =>
    ThemeData(colorSchemeSeed: accent, brightness: brightness, splashFactory: NoSplash.splashFactory);

/// Wander, a travel journal: the showcase for every Veneer component.
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  /// Off for the one frame between taking the app down and bringing it back.
  bool _mounted = true;

  @override
  void initState() {
    super.initState();
    flutterReplicas.value = Veneer.debugForceFallback;
    flutterReplicas.addListener(_switchRendering);
  }

  @override
  void dispose() {
    flutterReplicas.removeListener(_switchRendering);
    super.dispose();
  }

  /// Flipping between native UIKit and the Flutter replicas rebuilds the app
  /// from scratch: it comes down for a frame while the native layer is still
  /// on (so its native chrome is removed), then mounts again with
  /// [Veneer.debugForceFallback] set the new way.
  void _switchRendering() {
    setState(() => _mounted = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Veneer.debugForceFallback = flutterReplicas.value;
      setState(() => _mounted = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_mounted) return const ColoredBox(color: Colors.black);
    return MaterialApp(
      key: ValueKey(flutterReplicas.value),
      title: 'Wander',
      debugShowCheckedModeBanner: false,
      theme: exampleTheme(Brightness.light),
      darkTheme: exampleTheme(Brightness.dark),
      navigatorObservers: [VeneerNavigatorObserver()],
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// Which icon type the tab bar's trailing button uses; switchable from the
/// Diagnostics page to compare SF Symbol, IconData and SVG side by side.
enum TrailingIconKind { symbol, iconData, svg }

final ValueNotifier<TrailingIconKind> trailingIconKind = ValueNotifier(TrailingIconKind.svg);

class _HomePageState extends State<HomePage> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // The sheets' engines start now, so they open with content.
    NativeSheet.prewarm('assistantSheet');
    NativeSheet.prewarm('staySheet');
    // Scripted measurement runs (tool/measure_sync.py) open the sync test directly.
    if (launchMeasureMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openSyncTest(context));
    }
  }

  // The AI button: a gradient SVG in its own colours by default.
  static const _trailingIcons = {
    TrailingIconKind.symbol: NativeIcon.symbol('sparkles'),
    TrailingIconKind.iconData: NativeIcon.icon(AppIcons.sparkleFill),
    TrailingIconKind.svg: NativeIcon.svgAsset('assets/icons/ai_sparkle.svg', tinted: false),
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: trailingIconKind,
      builder: (context, kind, _) => NativeChromeScope(
        tabs: const [
          NativeTabItem(
            title: 'Explore',
            icon: NativeIcon.icon(AppIcons.compass),
            selectedIcon: NativeIcon.icon(AppIcons.compassFill),
          ),
          NativeTabItem(
            title: 'Trips',
            icon: NativeIcon.icon(AppIcons.suitcaseRolling),
            selectedIcon: NativeIcon.icon(AppIcons.suitcaseRollingFill),
          ),
          NativeTabItem(
            title: 'Journal',
            icon: NativeIcon.icon(AppIcons.bookOpenText),
            selectedIcon: NativeIcon.icon(AppIcons.bookOpenTextFill),
            badge: '3',
          ),
          NativeTabItem(title: 'Components', icon: NativeIcon.icon(AppIcons.squaresFour)),
        ],
        tintColor: accent,
        scrollEdgeEffect: NativeScrollEdgeEffect.soft,
        trailingAction: NativeTabAction(
          icon: _trailingIcons[kind]!,
          title: 'Assistant',
          onPressed: () => openAssistant(context),
        ),
        selectedIndex: _index,
        onTabSelected: (i) => setState(() => _index = i),
        child: IndexedStack(
          index: _index,
          children: const [ExplorePage(), TripsPage(), JournalPage(), ComponentsPage()],
        ),
      ),
    );
  }
}

/// Pushes the glass sync-lag test (see tool/measure_sync.py).
void openSyncTest(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SyncTestPage()));
}
