import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:veneer/veneer.dart';

import 'pages/assistant_page.dart';
import 'pages/chat_page.dart';
import 'pages/clip_page.dart';
import 'pages/diagnostics_page.dart';
import 'pages/morph_page.dart';
import 'pages/sync_test_page.dart';
import 'app_icons.dart';

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

ThemeData exampleTheme(Brightness brightness) => ThemeData(colorSchemeSeed: Colors.indigo, brightness: brightness);

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veneer',
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
    // The assistant sheet's engine starts now, so the sheet opens with content.
    NativeSheet.prewarm('assistantSheet');
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
        // One of each icon type: SF Symbol, Material IconData (with a selected
        // variant), an SVG asset, and Cupertino IconData from a package font.
        tabs: const [
          NativeTabItem(
            title: 'Chat',
            icon: NativeIcon.icon(AppIcons.chatsCircle),
            selectedIcon: NativeIcon.icon(AppIcons.chatsCircleFill),
          ),
          NativeTabItem(
            title: 'Morph',
            icon: NativeIcon.icon(AppIcons.drop),
            selectedIcon: NativeIcon.icon(AppIcons.dropFill),
          ),
          NativeTabItem(title: 'Clip', icon: NativeIcon.svgAsset('assets/icons/scissors.svg')),
          NativeTabItem(title: 'Lab', icon: NativeIcon.icon(AppIcons.gauge), badge: '3'),
        ],
        scrollEdgeEffect: NativeScrollEdgeEffect.soft,
        trailingAction: NativeTabAction(
          icon: _trailingIcons[kind]!,
          title: 'Assistant',
          onPressed: () => openAssistant(context),
        ),
        selectedIndex: _index,
        onTabSelected: (i) => setState(() => _index = i),
        child: IndexedStack(index: _index, children: const [ChatPage(), MorphPage(), ClipPage(), DiagnosticsPage()]),
      ),
    );
  }
}

/// Pushes the glass sync-lag test (see tool/measure_sync.py).
void openSyncTest(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SyncTestPage()));
}
