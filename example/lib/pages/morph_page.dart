import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../app_icons.dart';

/// Cross-widget merging: separate [GlassShape] widgets become one glass body
/// when they come within the group's spacing. Drag the loose drop into the
/// cluster, toggle the cluster to split/join via a Flutter animation, or move
/// the drop into its own [GlassGroup] so it no longer fuses.
class MorphPage extends StatefulWidget {
  const MorphPage({super.key});

  @override
  State<MorphPage> createState() => _MorphPageState();
}

class _MorphPageState extends State<MorphPage> {
  Offset? _drop;
  bool _split = false;
  bool _dropOwnGroup = false;
  // Keeps the drop's State (and so its native shape) across the group
  // toggle, which changes its parent widget type.
  final GlobalKey _dropKey = GlobalKey();
  double _spacing = 24;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final center = Offset(size.width / 2, size.height * 0.42);
    final drop = _drop ?? center + const Offset(0, 190);
    const d = 72.0;
    final spread = _split ? 100.0 : 50.0;

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (e) => setState(() => _drop = e.localPosition),
        child: Stack(
          children: [
            const Positioned.fill(child: _Backdrop()),
            // One of each native icon type, fused into one glass body.
            for (final (i, icon) in const [
              (-1, NativeIcon.icon(AppIcons.heartFill)),
              (0, NativeIcon.svgAsset('assets/icons/star.svg')),
              (1, NativeIcon.icon(AppIcons.lightningFill)),
            ])
              AnimatedPositioned(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOutCubicEmphasized,
                left: center.dx - d / 2 + i * spread,
                top: center.dy - d / 2,
                child: GlassShape(width: d, height: d, icon: icon),
              ),
            Positioned(
              left: drop.dx - 44,
              top: drop.dy - 44,
              // Toggling reparents the same native shape between groups:
              // in its own group it glides over the cluster without fusing.
              child: _dropOwnGroup ? GlassGroup(zIndex: 1, child: _Drop(key: _dropKey)) : _Drop(key: _dropKey),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: padding.bottom + 16,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Spacing',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Expanded(
                        child: Slider(
                          value: _spacing,
                          max: 60,
                          onChanged: (v) {
                            setState(() => _spacing = v);
                            Veneer.setGlassSpacing(v);
                          },
                        ),
                      ),
                    ],
                  ),
                  GlassGroup(
                    zIndex: 2,
                    child: Row(
                      children: [
                        Expanded(
                          child: GlassShape(
                            height: 50,
                            icon: NativeIcon.icon(_split ? AppIcons.squaresFour : AppIcons.arrowsLeftRight),
                            label: _split ? 'Join' : 'Split',
                            onTap: () => setState(() => _split = !_split),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GlassShape(
                          width: 150,
                          height: 50,
                          icon: NativeIcon.icon(_dropOwnGroup ? AppIcons.stackFill : AppIcons.stack),
                          label: _dropOwnGroup ? 'Own group' : 'Shared',
                          onTap: () => setState(() => _dropOwnGroup = !_dropOwnGroup),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Drop extends StatelessWidget {
  const _Drop({super.key});

  @override
  Widget build(BuildContext context) =>
      const GlassShape(width: 88, height: 88, icon: NativeIcon.icon(AppIcons.handGrabbing), style: GlassStyle.clear);
}

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2A6C), Color(0xFFB21F1F), Color(0xFFFDBB2D)],
        ),
      ),
      child: GridView.count(
        crossAxisCount: 6,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 90; i++)
            Center(
              child: Icon(AppIcons.circleFill, size: 10, color: Colors.white.withValues(alpha: i.isEven ? 0.7 : 0.3)),
            ),
        ],
      ),
    );
  }
}
