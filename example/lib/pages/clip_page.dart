import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

/// Native glass honouring Flutter clips: a rounded card with a vertical list
/// scrolling glass pills out through its corners, a capsule card with a
/// horizontal list of chips, and a ClipOval. The toggle sets every clip to
/// `Clip.none` for comparison.
class ClipPage extends StatefulWidget {
  const ClipPage({super.key});

  @override
  State<ClipPage> createState() => _ClipPageState();
}

class _ClipPageState extends State<ClipPage> {
  bool _clip = true;

  Clip get _behavior => _clip ? Clip.antiAlias : Clip.none;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F2027), Color(0xFF2C5364), Color(0xFF4CA1AF)],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, padding.top + 16, 20, padding.bottom + 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GlassGroup(
                zIndex: 1,
                child: GlassShape(
                  width: 170,
                  height: 48,
                  icon: _clip
                      ? const NativeIcon.svgAsset('assets/icons/scissors.svg')
                      : const NativeIcon.icon(Icons.content_cut),
                  label: _clip ? 'Clips on' : 'Clips off',
                  onTap: () => setState(() => _clip = !_clip),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _Caption('ClipRRect(32) › vertical ListView'),
            ClipRRect(
              borderRadius: BorderRadius.circular(32),
              clipBehavior: _behavior,
              child: Container(
                height: 240,
                color: Colors.white.withValues(alpha: 0.12),
                child: ListView.builder(
                  clipBehavior: _behavior,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: 30,
                  itemBuilder: (context, i) => SizedBox(
                    height: 64,
                    child: Center(
                      child: i.isEven
                          ? GlassShape(width: 240, height: 48, icon: NativeIcon.symbol('drop.fill'), label: 'Item $i')
                          : Text('Item $i', style: const TextStyle(color: Colors.white70, fontSize: 18)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const _Caption('ClipRRect(capsule) › horizontal ListView'),
            ClipRRect(
              borderRadius: BorderRadius.circular(44),
              clipBehavior: _behavior,
              child: Container(
                height: 88,
                color: Colors.white.withValues(alpha: 0.12),
                child: ListView.separated(
                  clipBehavior: _behavior,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                  itemCount: 12,
                  separatorBuilder: (_, _) => const SizedBox(width: 24),
                  itemBuilder: (context, i) =>
                      GlassShape(width: 110, height: 56, icon: NativeIcon.symbol('tag.fill'), label: 'Chip $i'),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const _Caption('ClipOval'),
            Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: ClipOval(
                  clipBehavior: _behavior,
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.12),
                    child: OverflowBox(
                      maxWidth: 320,
                      child: const Center(
                        child: GlassShape(
                          width: 300,
                          height: 64,
                          icon: NativeIcon.symbol('circle.lefthalf.filled'),
                          label: 'Oval',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontFamily: 'Menlo'),
    ),
  );
}
