import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../core/anchor_geometry.dart';
import '../core/veneer_bridge.dart';

/// Collects the on-screen rect of every [RenderGlassAnchor] once per Flutter
/// frame and pushes them to the native glass layer in one packed buffer.
///
/// Runs as a persistent frame callback registered after the renderer's, so
/// it sees final layout *and* paint for the frame that was just composited.
/// Geometry is resolved by walking the render tree ([resolveAnchorGeometry])
/// rather than during `paint`, because a scroll only moves repaint-boundary
/// layers and never re-paints the anchor itself.
///
/// Buffer layout — `[frameNumber, count, shape * count]`, each shape:
///   0 id · 1–4 rect LTWH · 5 visible · 6 clip id · 7 clip flags (1 rect, 2 rrect)
///   8–11 clip rect LTWH · 12–15 clip rrect LTWH · 16–19 radii TL TR BR BL
///
/// One extra entry, id [composerHostId], carries how far the active
/// composer's page has moved from where it rests (entry fields 1–2: dx, dy),
/// so the native composer rides its page — a sheet sliding up or dragged
/// down, a route sliding in — in the same frame.
class GlassCoordinator {
  GlassCoordinator._() {
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
    VeneerBridge.instance.onAttached = markDirty;
  }

  static final GlassCoordinator instance = GlassCoordinator._();

  static const int stride = 20;
  static const int composerHostId = -1;

  final Map<Object, (int, Offset Function())> _composerHosts = {};

  /// Registers a composer widget that's showing; [offset] reports its page's
  /// displacement from rest each frame. The most recently shown one
  /// ([activation] is higher) drives the native composer, so a covered page
  /// that re-attaches mid-transition can't take it back.
  void setComposerHost(Object host, int activation, Offset Function() offset) {
    _composerHosts[host] = (activation, offset);
    markDirty();
  }

  void clearComposerHost(Object host) {
    if (_composerHosts.remove(host) != null) markDirty();
  }

  Offset Function()? get _composerOffset {
    (int, Offset Function())? best;
    for (final entry in _composerHosts.values) {
      if (best == null || entry.$1 > best.$1) best = entry;
    }
    return best?.$2;
  }

  final Map<int, RenderGlassAnchor> _anchors = {};
  Float64List _last = Float64List(0);
  bool _dirty = false;
  int _frameNumber = 0;

  void add(RenderGlassAnchor anchor) {
    _anchors[anchor.shapeId] = anchor;
    markDirty();
  }

  void remove(RenderGlassAnchor anchor) {
    if (_anchors[anchor.shapeId] == anchor) _anchors.remove(anchor.shapeId);
    markDirty();
  }

  /// Forces the next frame to resend geometry, e.g. after the native side
  /// created a shape that missed earlier frames.
  void markDirty() {
    _dirty = true;
    SchedulerBinding.instance.scheduleFrame();
  }

  void _onFrame(Duration _) {
    final hostOffset = _composerOffset?.call();
    if (_anchors.isEmpty && hostOffset == null && _last.isEmpty) return;
    _frameNumber++;

    final entries = _anchors.length + (hostOffset == null ? 0 : 1);
    final frame = Float64List(2 + entries * stride)
      ..[0] = _frameNumber.toDouble()
      ..[1] = entries.toDouble();
    var o = 2;
    if (hostOffset != null) {
      frame[o] = composerHostId.toDouble();
      frame[o + 1] = hostOffset.dx;
      frame[o + 2] = hostOffset.dy;
      o += stride;
    }
    for (final anchor in _anchors.values) {
      frame[o] = anchor.shapeId.toDouble();
      if (anchor.attached && anchor.hasSize) {
        final g = resolveAnchorGeometry(anchor);
        _put(frame, o + 1, g.rect);
        frame[o + 5] = anchor.shouldShow && g.painted && !g.fullyClipped ? 1 : 0;
        frame[o + 6] = g.clipId.toDouble();
        var flags = 0;
        if (g.clipRect case final clip?) {
          flags |= 1;
          _put(frame, o + 8, clip);
        }
        if (g.clipRRect case final rr?) {
          flags |= 2;
          _put(frame, o + 12, rr.outerRect);
          // Native corners are circular; elliptical radii use the smaller axis.
          frame[o + 16] = math.min(rr.tlRadiusX, rr.tlRadiusY);
          frame[o + 17] = math.min(rr.trRadiusX, rr.trRadiusY);
          frame[o + 18] = math.min(rr.brRadiusX, rr.brRadiusY);
          frame[o + 19] = math.min(rr.blRadiusX, rr.blRadiusY);
        }
        frame[o + 7] = flags.toDouble();
      }
      o += stride;
    }

    if (!_dirty && _sameGeometry(frame, _last)) return;
    _dirty = false;
    _last = frame;
    VeneerBridge.instance.applyFrame(frame);
  }

  static void _put(Float64List f, int o, Rect r) {
    f[o] = r.left;
    f[o + 1] = r.top;
    f[o + 2] = r.width;
    f[o + 3] = r.height;
  }

  static bool _sameGeometry(Float64List a, Float64List b) {
    if (a.length != b.length) return false;
    for (var i = 1; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Invisible render box that marks where a native glass shape should be.
/// Paints nothing: the glass is drawn by UIKit above the Flutter surface.
class RenderGlassAnchor extends RenderProxyBox {
  RenderGlassAnchor({required this.shapeId, required bool shouldShow})
    : _shouldShow = shouldShow; // ignore: prefer_initializing_formals

  final int shapeId;

  bool get shouldShow => _shouldShow;
  bool _shouldShow;
  set shouldShow(bool value) {
    if (value == _shouldShow) return;
    _shouldShow = value;
    GlassCoordinator.instance.markDirty();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    GlassCoordinator.instance.add(this);
  }

  @override
  void detach() {
    GlassCoordinator.instance.remove(this);
    super.detach();
  }
}
