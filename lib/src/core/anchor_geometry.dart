import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Where an anchor is on screen this frame, and how Flutter clips it.
///
/// All values are in global logical pixels (== UIKit points, relative to the
/// FlutterView). Clips are already reduced for the native side:
///   * [clipId] — identifies the innermost clipping ancestor; 0 when nothing
///     clips. Anchors under the same clip share an id and so a native clip
///     scope (one masked glass container), which keeps them able to merge.
///     It's stable while the clip moves, so shapes don't hop containers.
///   * [clipRect] — intersection of every rectangular ancestor clip (and the
///     bounds of any rounded clip that isn't the innermost one).
///   * [clipRRect] — the innermost rounded clip (`ClipRRect`, `ClipOval`).
///
/// Clips covering the whole screen (Navigator, Overlay) are ignored.
@immutable
class AnchorGeometry {
  const AnchorGeometry({required this.rect, required this.painted, this.clipId = 0, this.clipRect, this.clipRRect});

  final Rect rect;

  /// Whether every ancestor paints this anchor (Offstage, zero opacity, …).
  final bool painted;

  final int clipId;
  final Rect? clipRect;
  final RRect? clipRRect;

  /// Nothing of [rect] survives the clips.
  bool get fullyClipped =>
      (clipRect != null && !clipRect!.overlaps(rect)) || (clipRRect != null && !clipRRect!.outerRect.overlaps(rect));
}

/// Resolves [anchor]'s global rect, paint visibility and effective clip in
/// one walk up the render tree.
///
/// Transforms compose top-down exactly like `getTransformTo(null)` — the root
/// view's own (device-pixel) transform is excluded — so each ancestor's clip,
/// reported by `describeApproximatePaintClip` in that ancestor's space, maps
/// to global coordinates with the transform accumulated so far.
AnchorGeometry resolveAnchorGeometry(RenderBox anchor) {
  final chain = <RenderObject>[anchor];
  for (var p = anchor.parent; p != null; p = p.parent) {
    chain.add(p);
  }

  final root = chain.last;
  final screen = root is RenderView ? Offset.zero & root.size : null;

  var painted = true;
  Rect? clipRect;
  RRect? innerRRect;
  RenderObject? innermostClip;
  final transform = Matrix4.identity(); // chain[k] local → global

  for (var k = chain.length - 2; k >= 1; k--) {
    final parent = chain[k];
    final child = chain[k - 1];
    if (!parent.paintsChild(child)) painted = false;

    final rounded = _roundedClip(parent);
    if (rounded != null) {
      // Only one rounded clip goes native; outer ones degrade to their bounds.
      if (innerRRect != null) clipRect = _intersect(clipRect, innerRRect.outerRect);
      innerRRect = _transformRRect(transform, rounded);
      innermostClip = parent;
    } else if (parent.describeApproximatePaintClip(child) case final local?) {
      final clip = MatrixUtils.transformRect(transform, local);
      if (screen == null || !_containsRect(clip, screen)) {
        clipRect = _intersect(clipRect, clip);
        innermostClip = parent;
      }
    }
    parent.applyPaintTransform(child, transform);
  }

  final rect = MatrixUtils.transformRect(transform, Offset.zero & anchor.size);

  // Clips are kept even when they don't cut into this anchor: dropping them
  // would move the shape between native containers as it scrolls across a
  // clip edge.
  return AnchorGeometry(
    rect: rect,
    painted: painted,
    clipId: innermostClip == null ? 0 : _clipIds[innermostClip] ??= _nextClipId++,
    clipRect: clipRect,
    clipRRect: innerRRect,
  );
}

final Expando<int> _clipIds = Expando('clipId');
int _nextClipId = 1;

RRect? _roundedClip(RenderObject node) {
  if (node is RenderClipRRect && node.clipBehavior != Clip.none) {
    return node.clipper?.getClip(node.size) ??
        node.borderRadius.resolve(node.textDirection).toRRect(Offset.zero & node.size);
  }
  if (node is RenderClipOval && node.clipBehavior != Clip.none) {
    final r = node.clipper?.getClip(node.size) ?? Offset.zero & node.size;
    return RRect.fromRectXY(r, r.width / 2, r.height / 2);
  }
  return null;
}

RRect _transformRRect(Matrix4 m, RRect rr) {
  final rect = MatrixUtils.transformRect(m, rr.outerRect);
  final sx = rr.width == 0 ? 1.0 : rect.width / rr.width;
  final sy = rr.height == 0 ? 1.0 : rect.height / rr.height;
  Radius scale(double x, double y) => Radius.elliptical(x * sx, y * sy);
  return RRect.fromRectAndCorners(
    rect,
    topLeft: scale(rr.tlRadiusX, rr.tlRadiusY),
    topRight: scale(rr.trRadiusX, rr.trRadiusY),
    bottomRight: scale(rr.brRadiusX, rr.brRadiusY),
    bottomLeft: scale(rr.blRadiusX, rr.blRadiusY),
  );
}

Rect _intersect(Rect? a, Rect b) => a == null ? b : a.intersect(b);

bool _containsRect(Rect outer, Rect inner) =>
    outer.left <= inner.left + 0.01 &&
    outer.top <= inner.top + 0.01 &&
    outer.right >= inner.right - 0.01 &&
    outer.bottom >= inner.bottom - 0.01;
