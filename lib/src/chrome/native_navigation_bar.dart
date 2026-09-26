import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/fallback_style.dart';
import '../core/native_icon.dart';
import '../core/veneer_bridge.dart';

/// How content fades under native chrome: iOS 26's scroll edge effect.
enum NativeScrollEdgeEffect {
  none,

  /// The system's choice for the context.
  automatic,

  /// A progressive blur that content dissolves into (iOS default under bars).
  soft,

  /// A sharper divide with a subtle backing.
  hard,
}

/// A glass bar button: 44 pt, grouped with adjacent trailing buttons into one
/// capsule by UIKit.
@immutable
class NativeBarButton {
  const NativeBarButton({required this.icon, this.title, this.onPressed});

  final NativeIcon icon;

  /// VoiceOver label (shown instead of the icon only if the icon fails).
  final String? title;
  final VoidCallback? onPressed;
}

/// The bar's title. By default the system's centred title and subtitle; with
/// [capsule], a tappable glass capsule after the leading button holding
/// [icon], [title] and [subtitle] — a channel header.
@immutable
class NativeBarTitle {
  const NativeBarTitle({required this.title, this.subtitle, this.icon, this.capsule = false, this.onPressed});

  final String title;
  final String? subtitle;
  final NativeIcon? icon;
  final bool capsule;
  final VoidCallback? onPressed;
}

/// A navigation bar over [child]: a native `UINavigationBar` on iOS 26, an
/// `AppBar` elsewhere (Android, iOS 15–25).
///
/// Native: the bar floats over [child] (under a [NativeChromeScope]), and
/// its height is added to `MediaQuery` top padding so content starts below
/// it and scrolls under it, fading into the [scrollEdgeEffect].
/// Fallback: an `AppBar` above [child], with the same buttons and title.
///
/// One bar is shown at a time: the most recently visible
/// [NativeNavigationBar] wins, and it hides when its page is covered by
/// another route or hidden in an `IndexedStack`.
class NativeNavigationBar extends StatefulWidget {
  const NativeNavigationBar({
    super.key,
    this.leading,
    this.title,
    this.trailing = const [],
    this.tintColor,
    this.scrollEdgeEffect = NativeScrollEdgeEffect.soft,
    required this.child,
  });

  final NativeBarButton? leading;
  final NativeBarTitle? title;

  /// In reading order; UIKit shares one glass capsule between them.
  final List<NativeBarButton> trailing;
  final Color? tintColor;
  final NativeScrollEdgeEffect scrollEdgeEffect;

  /// The page content.
  final Widget child;

  @override
  State<NativeNavigationBar> createState() => _NativeNavigationBarState();
}

class _NativeNavigationBarState extends State<NativeNavigationBar> {
  static _NativeNavigationBarState? _active;
  static String? _lastSent;
  bool _visible = false;

  VeneerBridge get _bridge => VeneerBridge.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = Visibility.of(context) && (ModalRoute.isCurrentOf(context) ?? true);
    if (visible != _visible) {
      _visible = visible;
      _push();
    }
  }

  @override
  void didUpdateWidget(NativeNavigationBar old) {
    super.didUpdateWidget(old);
    if (_visible) _push();
  }

  void _push() {
    if (!_bridge.isSupported) return;
    if (_visible) {
      _active = this;
    } else if (_active != this) {
      return; // another bar owns the native view
    }
    final handlers = <String, VoidCallback?>{};
    Map<String, Object?> button(String id, NativeBarButton b) {
      handlers[id] = b.onPressed;
      return {'id': id, 'icon': b.icon.encode(), 'title': b.title};
    }

    final title = widget.title;
    if (title != null) handlers['title'] = title.onPressed;
    final config = <String, Object?>{
      'hidden': !_visible,
      'leading': widget.leading == null ? null : button('leading', widget.leading!),
      'title': title == null
          ? null
          : {
              'id': 'title',
              'title': title.title,
              'subtitle': title.subtitle,
              'icon': title.icon?.encode(),
              'capsule': title.capsule,
            },
      'trailing': [for (final (i, b) in widget.trailing.indexed) button('trailing$i', b)],
      'tintColor': widget.tintColor?.toARGB32(),
      'edgeEffect': widget.scrollEdgeEffect.name,
    };
    // Pages rebuild every frame while the keyboard animates; only send real
    // changes. Callbacks are refreshed locally either way.
    final encoded = jsonEncode(config);
    if (encoded == _lastSent) {
      _bridge.updateNavigationBarHandler((id) => handlers[id]?.call());
      return;
    }
    _lastSent = encoded;
    _bridge.setNavigationBar(config, (id) => handlers[id]?.call());
  }

  @override
  void dispose() {
    if (_active == this) {
      _active = null;
      _lastSent = null;
      _bridge.removeNavigationBar();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _bridge.isSupported ? widget.child : _FallbackNavigationBar(widget);
}

/// Flutter replica of the native bar, for Android and iOS 15–25: the same
/// 44 pt glass-style controls — a back circle 16 pt from the edge, the title
/// capsule 12 pt after it, trailing buttons sharing one capsule — solid
/// instead of glass, floating over the content with a fade standing in for
/// the scroll edge effect. Content gets top padding for it, as natively.
class _FallbackNavigationBar extends StatelessWidget {
  const _FallbackNavigationBar(this.bar);

  final NativeNavigationBar bar;

  static const double item = 44;
  static const double margin = 16;
  static const double spacing = 12;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final style = VeneerFallbackStyle.of(context);
    final foreground = bar.tintColor ?? style.label;
    final top = mq.padding.top + 2;
    final barBottom = top + item + 6;
    final title = bar.title;
    final background = Theme.of(context).scaffoldBackgroundColor;

    Widget iconButton(NativeBarButton b, {double width = item}) => Semantics(
      button: true,
      label: b.title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: b.onPressed,
        child: SizedBox(
          width: width,
          height: item,
          child: Center(child: NativeIconView(b.icon, size: 24, color: foreground)),
        ),
      ),
    );

    Widget titleText(CrossAxisAlignment align) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        Text(
          title!.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: style.label, height: 1.2),
        ),
        if ((title.subtitle ?? '').isNotEmpty)
          Text(
            title.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: style.secondaryLabel, height: 1.2),
          ),
      ],
    );

    final capsuleRadius = BorderRadius.circular(item / 2);
    final row = Row(
      children: [
        if (bar.leading case final leading?)
          DecoratedBox(
            decoration: style.surfaceDecoration(shape: BoxShape.circle),
            child: iconButton(leading),
          ),
        if (title != null && title.capsule) ...[
          if (bar.leading != null) const SizedBox(width: spacing),
          // Natural width, up to all the space the trailing group leaves.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: title.onPressed,
                  child: Container(
                    height: item,
                    padding: const EdgeInsets.only(left: 14, right: 16),
                    decoration: style.surfaceDecoration(radius: capsuleRadius),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title.icon case final icon?) ...[
                          NativeIconView(icon, size: 18, color: style.label),
                          const SizedBox(width: 10),
                        ],
                        Flexible(child: titleText(CrossAxisAlignment.start)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: spacing),
        ] else
          const Spacer(),
        if (bar.trailing.isNotEmpty)
          Container(
            height: item,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: style.surfaceDecoration(radius: capsuleRadius),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (final b in bar.trailing) iconButton(b, width: 48)],
            ),
          ),
      ],
    );

    return Stack(
      children: [
        MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(top: barBottom),
            viewPadding: mq.viewPadding.copyWith(top: barBottom),
          ),
          child: bar.child,
        ),
        if (bar.scrollEdgeEffect != NativeScrollEdgeEffect.none)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: barBottom + 24,
            child: IgnorePointer(
              child: DecoratedBox(
                // Opaque through the status bar, then fading out below the bar.
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      background,
                      background,
                      background.withValues(alpha: 0.8),
                      background.withValues(alpha: 0),
                    ],
                    stops: [0, top / (barBottom + 24), (top + item / 2) / (barBottom + 24), 1],
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: margin,
          right: margin,
          top: top,
          height: item,
          child: Material(type: MaterialType.transparency, child: row),
        ),
        // The system's plain centred title, when not a capsule.
        if (title != null && !title.capsule)
          Positioned(
            left: margin + item + spacing,
            right: margin + item + spacing,
            top: top,
            height: item,
            child: IgnorePointer(
              child: Material(
                type: MaterialType.transparency,
                child: Center(child: titleText(CrossAxisAlignment.center)),
              ),
            ),
          ),
      ],
    );
  }
}
