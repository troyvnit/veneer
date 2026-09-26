import 'dart:async';

import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../main.dart' show TrailingIconKind, trailingIconKind;

/// Transport A/B switch, native apply stats, and overlay edge cases
/// (Flutter dialog over native chrome, pushed route over glass).
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Map<String, Object?> _stats = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted || !VeneerBridge.instance.isAttached) return;
      final stats = await VeneerBridge.instance.stats();
      if (mounted) setState(() => _stats = stats);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(Object? v) => v is double ? v.toStringAsFixed(3) : '$v';

  @override
  Widget build(BuildContext context) {
    final bridge = VeneerBridge.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        // An explicit padding replaces ListView's automatic MediaQuery
        // padding, so add the native tab bar's inset back.
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          const Text('Geometry transport', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<VeneerTransport>(
            segments: const [
              ButtonSegment(value: VeneerTransport.ffi, label: Text('FFI')),
              ButtonSegment(value: VeneerTransport.channel, label: Text('Channel')),
              ButtonSegment(value: VeneerTransport.delayedChannel, label: Text('+1 frame')),
            ],
            selected: {bridge.transport},
            onSelectionChanged: (s) => setState(() => bridge.transport = s.first),
          ),
          const SizedBox(height: 24),
          const Text('Trailing tab button icon', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: trailingIconKind,
            builder: (context, kind, _) => SegmentedButton<TrailingIconKind>(
              segments: const [
                ButtonSegment(value: TrailingIconKind.symbol, label: Text('SF Symbol')),
                ButtonSegment(value: TrailingIconKind.iconData, label: Text('IconData')),
                ButtonSegment(value: TrailingIconKind.svg, label: Text('SVG')),
              ],
              selected: {kind},
              onSelectionChanged: (s) => trailingIconKind.value = s.first,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text('Native apply stats', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(onPressed: bridge.resetStats, child: const Text('Reset')),
            ],
          ),
          for (final e in _stats.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            ListTile(dense: true, title: Text(e.key), trailing: Text(_fmt(e.value))),
          const Text(
            'offMainApplies > 0 means the Dart UI thread is not merged with the '
            'platform thread, so FFI falls back to an async hop.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 24),
          const Text('Overlay edge cases', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Flutter dialog'),
                content: const Text('Native chrome and glass should fade out while this is open.'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
              ),
            ),
            child: const Text('Show Flutter dialog'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const SizedBox(height: 280, child: Center(child: Text('Flutter bottom sheet'))),
            ),
            child: const Text('Show Flutter bottom sheet'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Pushed route')),
                  body: const Center(
                    child: GlassShape(
                      width: 220,
                      height: 56,
                      icon: NativeIcon.symbol('checkmark'),
                      label: 'Glass on route 2',
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Push route'),
          ),
        ],
      ),
    );
  }
}
