import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:veneer/veneer.dart';

import '../main.dart' show launchMeasureMode;

/// Measures how far native glass trails Flutter during scrolling.
///
/// Each glass pill has a red ring painted by *Flutter* 4pt outside it. The
/// ring is exactly where Flutter thinks the pill is this frame; any gap
/// between the ring and the glass during a scroll is sync lag. Auto-scroll
/// runs at a constant, known velocity so the gap converts directly to
/// frames: lag_frames = gap / (velocity / refresh_rate).
///
/// "Measure mode" swaps in flat colors so screenshots can be analysed.
class SyncTestPage extends StatefulWidget {
  const SyncTestPage({super.key});

  static const double scrollVelocity = 1200; // points per second

  @override
  State<SyncTestPage> createState() => _SyncTestPageState();
}

class _SyncTestPageState extends State<SyncTestPage> with SingleTickerProviderStateMixin {
  final ScrollController _controller = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  double _direction = 1;
  bool _measureMode = false;

  bool get _autoScrolling => _ticker.isActive;

  @override
  void initState() {
    super.initState();
    if (launchMeasureMode) {
      _measureMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleAutoScroll());
    }
  }

  void _toggleAutoScroll() {
    setState(() {
      if (_ticker.isActive) {
        _ticker.stop();
      } else {
        _lastTick = Duration.zero;
        _ticker.start();
      }
    });
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    var next = position.pixels + _direction * SyncTestPage.scrollVelocity * dt;
    if (next >= position.maxScrollExtent || next <= position.minScrollExtent) {
      _direction = -_direction;
      next = next.clamp(position.minScrollExtent, position.maxScrollExtent);
    }
    _controller.jumpTo(next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: _measureMode ? Colors.white : null,
      body: Stack(
        children: [
          ListView.builder(
            controller: _controller,
            padding: EdgeInsets.only(top: top + 72, bottom: MediaQuery.paddingOf(context).bottom + 16),
            itemCount: 120,
            itemBuilder: (context, i) => _Row(index: i, measureMode: _measureMode),
          ),
          Positioned(
            top: top + 12,
            left: 16,
            right: 16,
            // Floating controls get their own group above the content's
            // route group: pills scroll *under* them instead of fusing.
            child: GlassGroup(
              zIndex: 1,
              child: Row(
                children: [
                  GlassShape(
                    width: 170,
                    height: 48,
                    icon: NativeIcon.symbol(_autoScrolling ? 'pause.fill' : 'play.fill'),
                    label: _autoScrolling ? 'Stop' : 'Auto-scroll',
                    onTap: _toggleAutoScroll,
                  ),
                  const Spacer(),
                  GlassShape(
                    width: 48,
                    height: 48,
                    icon: NativeIcon.symbol(_measureMode ? 'ruler.fill' : 'ruler'),
                    onTap: () => setState(() => _measureMode = !_measureMode),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.index, required this.measureMode});

  final int index;
  final bool measureMode;

  @override
  Widget build(BuildContext context) {
    final hue = (index * 23) % 360;
    final color = HSLColor.fromAHSL(1, hue.toDouble(), 0.7, 0.55).toColor();
    final hasGlass = index % 4 == 1;

    return Container(
      height: 96,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: measureMode ? Colors.white : color,
        borderRadius: BorderRadius.circular(20),
        gradient: measureMode
            ? null
            : LinearGradient(colors: [color, HSLColor.fromColor(color).withHue((hue + 60) % 360).toColor()]),
      ),
      alignment: Alignment.center,
      child: hasGlass
          ? DecoratedBox(
              // The Flutter-painted reference ring.
              decoration: ShapeDecoration(
                shape: StadiumBorder(
                  side: BorderSide(color: const Color(0xFFFF0000), width: measureMode ? 3 : 2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: GlassShape(
                  width: 200,
                  height: 52,
                  icon: NativeIcon.symbol('sparkles'),
                  label: 'Row $index',
                  tint: measureMode ? const Color(0xE600C800) : null,
                ),
              ),
            )
          : Text(
              'Row $index',
              style: TextStyle(
                color: measureMode ? Colors.black26 : Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
