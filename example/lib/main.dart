import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:veneer/veneer.dart';

import 'pages/chat_page.dart';
import 'pages/clip_page.dart';
import 'pages/diagnostics_page.dart';
import 'pages/morph_page.dart';
import 'pages/sync_test_page.dart';

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

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veneer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
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
    // Scripted measurement runs (tool/measure_sync.py) open the sync test directly.
    if (launchMeasureMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openSyncTest(context));
    }
  }

  static const _trailingIcons = {
    TrailingIconKind.symbol: NativeIcon.symbol('plus'),
    TrailingIconKind.iconData: NativeIcon.icon(Icons.add),
    TrailingIconKind.svg: NativeIcon.svgAsset('assets/icons/plus_circle.svg'),
  };

  void _compose() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(
        height: 240,
        child: Center(child: Text('Trailing action pressed', style: TextStyle(fontSize: 18))),
      ),
    );
  }

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
            icon: NativeIcon.symbol('bubble.left.and.bubble.right'),
            selectedIcon: NativeIcon.symbol('bubble.left.and.bubble.right.fill'),
          ),
          NativeTabItem(
            title: 'Morph',
            icon: NativeIcon.icon(Icons.water_drop_outlined),
            selectedIcon: NativeIcon.icon(Icons.water_drop),
          ),
          NativeTabItem(title: 'Clip', icon: NativeIcon.svgAsset('assets/icons/scissors.svg')),
          NativeTabItem(title: 'Lab', icon: NativeIcon.icon(CupertinoIcons.gauge), badge: '3'),
        ],
        scrollEdgeEffect: NativeScrollEdgeEffect.soft,
        trailingAction: NativeTabAction(icon: _trailingIcons[kind]!, title: 'New', onPressed: _compose),
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
