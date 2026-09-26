import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veneer/src/core/anchor_geometry.dart';

/// Stand-in anchor so geometry can be tested without the native bridge.
class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({super.key, super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) => RenderProxyBox();
}

AnchorGeometry _geometryOf(WidgetTester tester, Key key) =>
    resolveAnchorGeometry(tester.renderObject<RenderBox>(find.byKey(key, skipOffstage: false)));

Widget _app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  final probe = GlobalKey();

  testWidgets('clips are kept even when the anchor sits inside them', (tester) async {
    // Dropping them would move the native shape between clip scopes as it
    // scrolls across a clip edge.
    await tester.pumpWidget(
      _app(
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 200,
            height: 100,
            child: Center(
              child: _Probe(key: probe, child: const SizedBox(width: 100, height: 40)),
            ),
          ),
        ),
      ),
    );
    final g = _geometryOf(tester, probe);
    expect(g.rect, const Rect.fromLTWH(50, 30, 100, 40));
    expect(g.clipId, isNot(0));
    expect(g.clipRRect, RRect.fromLTRBR(0, 0, 200, 100, const Radius.circular(20)));
    expect(g.fullyClipped, isFalse);
  });

  testWidgets('anchors under the same clip share a clip id, others differ', (tester) async {
    final a = GlobalKey(), b = GlobalKey(), c = GlobalKey(), free = GlobalKey();
    Widget card(List<Widget> children) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: 200, height: 60, child: Row(children: children)),
    );
    await tester.pumpWidget(
      _app(
        Column(
          children: [
            card([
              _Probe(key: a, child: const SizedBox(width: 40, height: 40)),
              _Probe(key: b, child: const SizedBox(width: 40, height: 40)),
            ]),
            card([_Probe(key: c, child: const SizedBox(width: 40, height: 40))]),
            _Probe(key: free, child: const SizedBox(width: 40, height: 40)),
          ],
        ),
      ),
    );
    expect(_geometryOf(tester, a).clipId, _geometryOf(tester, b).clipId);
    expect(_geometryOf(tester, a).clipId, isNot(_geometryOf(tester, c).clipId));
    expect(_geometryOf(tester, free).clipId, 0);
  });

  testWidgets('screen-covering clips (Navigator, Overlay, full-screen lists) are ignored', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          children: [_Probe(key: probe, child: const SizedBox(height: 40))],
        ),
      ),
    );
    final g = _geometryOf(tester, probe);
    expect(g.clipId, 0);
    expect(g.clipRect, isNull);
  });

  testWidgets('rounded clip is reported in global coordinates when it cuts in', (tester) async {
    await tester.pumpWidget(
      _app(
        Padding(
          padding: const EdgeInsets.only(left: 10, top: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 200,
              height: 100,
              child: OverflowBox(
                maxWidth: 300,
                child: Center(
                  child: _Probe(key: probe, child: const SizedBox(width: 300, height: 40)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final g = _geometryOf(tester, probe);
    expect(g.rect, const Rect.fromLTWH(-40, 50, 300, 40));
    expect(g.clipRRect, RRect.fromLTRBR(10, 20, 210, 120, const Radius.circular(20)));
  });

  testWidgets('scroll viewport clip combines with an outer rounded clip', (tester) async {
    await tester.pumpWidget(
      _app(
        ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: SizedBox(
            width: 300,
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                const SizedBox(width: 250),
                _Probe(key: probe, child: const SizedBox(width: 100, height: 80)),
              ],
            ),
          ),
        ),
      ),
    );
    final g = _geometryOf(tester, probe);
    expect(g.rect, const Rect.fromLTWH(250, 0, 100, 80));
    expect(g.clipRect, const Rect.fromLTWH(0, 0, 300, 80), reason: 'viewport clip');
    expect(g.clipRRect, isNotNull, reason: 'card corners cut into the probe');
  });

  testWidgets('anchor scrolled out of its clip is fully clipped', (tester) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 300,
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
            children: [
              const SizedBox(width: 400),
              _Probe(key: probe, child: const SizedBox(width: 100, height: 80)),
            ],
          ),
        ),
      ),
    );
    expect(_geometryOf(tester, probe).fullyClipped, isTrue);
  });

  testWidgets('ClipOval becomes a rounded clip with half-extent radii', (tester) async {
    await tester.pumpWidget(
      _app(
        ClipOval(
          child: SizedBox(
            width: 100,
            height: 100,
            child: OverflowBox(
              maxWidth: 200,
              child: Center(
                child: _Probe(key: probe, child: const SizedBox(width: 200, height: 20)),
              ),
            ),
          ),
        ),
      ),
    );
    final rr = _geometryOf(tester, probe).clipRRect!;
    expect(rr.outerRect, const Rect.fromLTWH(0, 0, 100, 100));
    expect(rr.tlRadiusX, 50);
  });
}
