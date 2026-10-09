import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/fallback_scope.dart';
import '../core/fallback_style.dart';
import '../core/native_icon.dart';
import '../core/native_menu.dart';
import '../core/route_visibility.dart';
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
  const NativeBarButton({
    this.icon,
    this.title,
    this.onPressed,
    this.menu,
    this.badge,
    this.prominent = false,
    this.tint,
    this.group = 0,
    this.iconSize,
    this.iconPadding,
    this.showsTitle = false,
    this.titleStyle,
  }) : assert(icon != null || title != null, 'A bar button needs an icon or a title'),
       assert(iconPadding == null || (icon != null && !showsTitle), 'iconPadding needs an icon and no shown title'),
       assert(!showsTitle || (icon != null && title != null), 'showsTitle needs both an icon and a title');

  /// Without an icon, the button shows [title] as text.
  final NativeIcon? icon;

  /// VoiceOver label for icon buttons; the label of text buttons.
  final String? title;
  final VoidCallback? onPressed;

  /// Tapping opens this menu (a native `UIMenu`) instead of [onPressed].
  final List<NativeMenuItem>? menu;

  /// A badge on the button (`UIBarButtonItem.Badge`): a number or text, or
  /// an empty string for a dot.
  final String? badge;

  /// Tinted glass (`UIBarButtonItem.Style.prominent`), e.g. a primary action.
  final bool prominent;

  /// The colour of a [prominent] button's glass, e.g. the app's primary
  /// colour. Defaults to the bar's [NativeNavigationBar.tintColor], then the
  /// system tint.
  final Color? tint;

  /// Trailing buttons with the same group share a glass capsule; a new group
  /// starts a separate one.
  final int group;

  /// Side of a non-symbol icon's box (default 20 pt) — e.g. larger for an
  /// avatar image.
  final double? iconSize;

  /// Space between [icon] and its glass on every side, instead of UIKit's
  /// bar-button insets, which widen a large icon's glass into a capsule. A
  /// 42 pt avatar with 1 pt padding fills a 44 pt circle. Badges aren't shown
  /// on padded buttons.
  final double? iconPadding;

  /// Shows [title] beside [icon] in a glass capsule, like a labelled
  /// toolbar button, instead of using it only for VoiceOver. A single
  /// titled button gets its own capsule; badges aren't shown on it.
  final bool showsTitle;

  /// Font family, size, weight and colour of a [showsTitle] button's title,
  /// natively too. Default: the system's 17 pt semibold label.
  final TextStyle? titleStyle;
}

/// Where a plain (non-capsule) title sits: centred on the bar, as
/// `UINavigationBar` does by default, or leading, right after the leading
/// button.
enum NativeBarTitleAlignment { center, leading }

/// The bar's title. By default the system's centred title and subtitle; with
/// [capsule], a tappable glass capsule after the leading button holding
/// [icon], [title] and [subtitle] — a channel header.
@immutable
class NativeBarTitle {
  const NativeBarTitle({
    required this.title,
    this.subtitle,
    this.icon,
    this.accessory,
    this.capsule = false,
    this.fill = false,
    this.iconSize,
    this.alignment = NativeBarTitleAlignment.center,
    this.style,
    this.subtitleStyle,
    this.onPressed,
  });

  final String title;
  final String? subtitle;
  final NativeIcon? icon;

  /// In a [capsule], a small glyph after the title, e.g. a chevron for a
  /// title that opens something.
  final NativeIcon? accessory;

  /// For a plain title; ignored for a [capsule].
  final NativeBarTitleAlignment alignment;

  /// Font family, size, weight, line height and colour for the title and
  /// subtitle, natively too (families come from the app's fonts). Default:
  /// the system's.
  final TextStyle? style;
  final TextStyle? subtitleStyle;
  final bool capsule;

  /// A [capsule] that spans all the space between the leading and trailing
  /// buttons, as a chat header does, instead of hugging its text.
  final bool fill;

  /// Side of a non-symbol [icon] in a [capsule] (default 18 pt), e.g. 40
  /// for a group avatar that fills the capsule's height.
  final double? iconSize;
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
    this.scrolled,
    required this.child,
  });

  final NativeBarButton? leading;
  final NativeBarTitle? title;

  /// In reading order; UIKit shares one glass capsule between them.
  final List<NativeBarButton> trailing;
  final Color? tintColor;
  final NativeScrollEdgeEffect scrollEdgeEffect;

  /// Whether content has scrolled under the bar, for a bar that isn't an
  /// ancestor of the scrolling content (e.g. a `Scaffold.appBar`). Null
  /// detects it from [child]'s scroll notifications.
  final bool? scrolled;

  /// The page content.
  final Widget child;

  @override
  State<NativeNavigationBar> createState() => _NativeNavigationBarState();
}

Map<String, Object?>? _encodeStyle(TextStyle? style) => style == null
    ? null
    : {
        'family': style.fontFamily,
        'size': style.fontSize,
        'weight': style.fontWeight?.value,
        'height': style.height,
        'color': style.color?.toARGB32(),
      };

class _NativeNavigationBarState extends State<NativeNavigationBar> {
  static _NativeNavigationBarState? _active;
  static String? _lastSent;
  bool _visible = false;
  bool _native = false;

  /// Whether the page's content has scrolled under the bar: its scroll edge
  /// effect shows only then, as UIKit's does.
  bool _scrolled = false;

  bool get _isScrolled => widget.scrolled ?? _scrolled;

  bool _onScroll(Notification notification) {
    if (widget.scrolled != null) return false;
    final (metrics, depth) = switch (notification) {
      final ScrollNotification n => (n.metrics, n.depth),
      final ScrollMetricsNotification n => (n.metrics, n.depth),
      _ => (null, 0),
    };
    if (metrics == null || depth != 0 || metrics.axis != Axis.vertical) return false;
    final scrolled = metrics.pixels > metrics.minScrollExtent + 0.5;
    if (scrolled == _scrolled) return false;
    _scrolled = scrolled;
    if (_native) {
      if (_visible && _active == this) _bridge.setNavigationBarScrolled(scrolled);
    } else {
      setState(() {});
    }
    return false;
  }

  VeneerBridge get _bridge => VeneerBridge.instance;
  late final RouteChainWatcher _routes = RouteChainWatcher(() {
    if (mounted) _refresh();
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routes.update(context);
    _refresh();
  }

  @override
  void didUpdateWidget(NativeNavigationBar old) {
    super.didUpdateWidget(old);
    _refresh(resend: true);
    final scrolled = widget.scrolled;
    if (scrolled != null && scrolled != old.scrolled && _native && _visible && _active == this) {
      _bridge.setNavigationBarScrolled(scrolled);
    }
  }

  /// Checked against the live route: a covered page can rebuild before it
  /// hears it's no longer current, and must not take the bar back.
  void _refresh({bool resend = false}) {
    _native = useNativeLayer(context);
    if (!_native) return;
    final visible = Visibility.of(context) && isRouteOnTop(context);
    if (visible != _visible) {
      _visible = visible;
      _push();
    } else if (resend && _visible) {
      _push();
    }
  }

  void _push() {
    if (!_native) return;
    if (_visible) {
      _active = this;
    } else if (_active != this) {
      return; // another bar owns the native view
    }
    final handlers = <String, VoidCallback?>{};
    Map<String, Object?> button(String id, NativeBarButton b) {
      handlers[id] = b.onPressed;
      return {
        'id': id,
        'icon': b.icon?.encode(),
        'title': b.title,
        'menu': encodeMenu(id, b.menu, handlers),
        'badge': b.badge,
        'prominent': b.prominent,
        'tint': b.tint?.toARGB32(),
        'group': b.group,
        'iconSize': b.iconSize,
        'iconPadding': b.iconPadding,
        'showsTitle': b.showsTitle,
        'titleStyle': _encodeStyle(b.titleStyle),
      };
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
              'accessory': title.accessory?.encode(),
              'alignment': title.alignment.name,
              'style': _encodeStyle(title.style),
              'subtitleStyle': _encodeStyle(title.subtitleStyle),
              'capsule': title.capsule,
              'fill': title.fill,
              'iconSize': title.iconSize,
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
    _bridge.setNavigationBar({...config, 'scrolled': _isScrolled}, (id) => handlers[id]?.call());
  }

  @override
  void dispose() {
    _routes.dispose();
    if (_active == this) {
      _active = null;
      _lastSent = null;
      _bridge.removeNavigationBar();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = NotificationListener<Notification>(onNotification: _onScroll, child: widget.child);
    if (!_native) return _FallbackNavigationBar(widget, scrolled: _isScrolled, child: child);
    // Content starts below the bar and scrolls under it. Inside a
    // NativeChromeScope this is already applied; elsewhere (a pushed page,
    // a native sheet) the bar supplies it.
    return ValueListenableBuilder<double>(
      valueListenable: _bridge.chromeTopInset,
      builder: (context, top, child) {
        // Always the same tree shape: swapping in a MediaQuery only once the
        // inset arrives would rebuild the page's state from scratch.
        final mq = MediaQuery.of(context);
        final inset = math.max(mq.padding.top, top);
        return MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(top: inset),
            viewPadding: mq.viewPadding.copyWith(top: math.max(mq.viewPadding.top, inset)),
          ),
          child: child!,
        );
      },
      child: child,
    );
  }
}

/// Flutter replica of the native bar, for Android and iOS 15–25: the same
/// 44 pt glass-style controls — a back circle 16 pt from the edge, the title
/// capsule 12 pt after it, trailing buttons sharing one capsule — solid
/// instead of glass, floating over the content with a fade standing in for
/// the scroll edge effect. Content gets top padding for it, as natively.
/// An avatar-sized icon sits 2 pt from the capsule's edge, concentric with
/// it; a glyph gets the capsule's own padding.
bool _hasLargeIcon(NativeBarTitle title) => title.icon != null && (title.iconSize ?? 18) >= 32;

EdgeInsets _capsulePadding(NativeBarTitle title) =>
    _hasLargeIcon(title) ? const EdgeInsets.only(left: 2, right: 8) : const EdgeInsets.only(left: 14, right: 16);

class _FallbackNavigationBar extends StatelessWidget {
  const _FallbackNavigationBar(this.bar, {required this.scrolled, required this.child});

  final bool scrolled;
  final Widget child;

  /// Adjacent buttons with the same [NativeBarButton.group].
  static List<List<NativeBarButton>> _groups(List<NativeBarButton> buttons) {
    final groups = <List<NativeBarButton>>[];
    for (final b in buttons) {
      if (groups.isEmpty || groups.last.last.group != b.group) {
        groups.add([b]);
      } else {
        groups.last.add(b);
      }
    }
    return groups;
  }

  final NativeNavigationBar bar;

  static const double item = 44;
  static const double margin = 16;
  static const double spacing = 12;
  static const double titledPadding = 16;
  static const double titledGap = 8;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final style = VeneerFallbackStyle.of(context);
    final foreground = bar.tintColor ?? style.label;
    final top = mq.padding.top + 2;
    final barBottom = top + item + 6;
    final title = bar.title;
    final background = Theme.of(context).scaffoldBackgroundColor;

    // A prominent button is tinted glass with a white label, as
    // `UIBarButtonItem.Style.prominent` draws it.
    Color? fill(NativeBarButton b) => b.prominent ? b.tint ?? bar.tintColor ?? style.accent : null;
    Color labelColor(NativeBarButton b) => b.prominent ? const Color(0xFFFFFFFF) : foreground;

    // A titled button, or a lone text button: a capsule hugging its label.
    Widget titledButton(NativeBarButton b) => Semantics(
      button: true,
      label: b.title,
      excludeSemantics: true,
      child: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: b.menu?.isNotEmpty ?? false ? () => showFallbackMenu(context, b.menu!) : b.onPressed,
          child: Container(
            height: item,
            padding: const EdgeInsets.symmetric(horizontal: titledPadding),
            decoration: style.surfaceDecoration(radius: BorderRadius.circular(item / 2), color: fill(b)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: titledGap,
              children: [
                if (b.icon case final icon? when b.showsTitle)
                  NativeIconView(icon, size: b.iconSize ?? 24, color: labelColor(b)),
                Text(
                  b.title!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: labelColor(b),
                  ).merge(b.showsTitle ? b.titleStyle : null),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Widget iconButton(NativeBarButton b, {double width = item, Color? color}) => Semantics(
      button: true,
      label: b.title,
      excludeSemantics: true,
      child: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: b.menu?.isNotEmpty ?? false ? () => showFallbackMenu(context, b.menu!) : b.onPressed,
          child: SizedBox(
            width: width,
            height: item,
            child: Center(
              child: b.icon == null
                  ? Text(
                      b.title!,
                      maxLines: 1,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color ?? foreground),
                    )
                  : NativeIconView(b.icon!, size: 24, color: color ?? foreground),
            ),
          ),
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
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: style.label,
            height: 1.2,
          ).merge(title.style),
        ),
        if ((title.subtitle ?? '').isNotEmpty)
          Text(
            title.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: style.secondaryLabel, height: 1.2).merge(title.subtitleStyle),
          ),
      ],
    );

    final capsuleRadius = BorderRadius.circular(item / 2);
    final groups = _groups(bar.trailing);
    final trailingWidth = groups.fold<double>(
      groups.isEmpty ? 0 : -spacing,
      (sum, g) => sum + spacing + (g.length == 1 ? item : 6 + 48.0 * g.length),
    );
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
                    width: title.fill ? double.infinity : null,
                    padding: _capsulePadding(title),
                    decoration: style.surfaceDecoration(radius: capsuleRadius),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title.icon case final icon?) ...[
                          NativeIconView(icon, size: title.iconSize ?? 18, color: style.label),
                          SizedBox(width: _hasLargeIcon(title) ? 8 : 10),
                        ],
                        Flexible(child: titleText(CrossAxisAlignment.start)),
                        if (title.accessory case final accessory?) ...[
                          const SizedBox(width: 6),
                          NativeIconView(accessory, size: 16, color: style.label),
                        ],
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
        // Per group: one icon button is a 44 pt circle, like the leading one,
        // and one text or titled button a capsule; several share a capsule.
        for (final (i, group) in groups.indexed) ...[
          if (i > 0) const SizedBox(width: spacing),
          if (group.length == 1 && (group.single.showsTitle || group.single.icon == null))
            titledButton(group.single)
          else if (group.length == 1)
            DecoratedBox(
              decoration: style.surfaceDecoration(shape: BoxShape.circle, color: fill(group.single)),
              child: iconButton(group.single, color: labelColor(group.single)),
            )
          else
            Container(
              height: item,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: style.surfaceDecoration(radius: capsuleRadius),
              child: Row(mainAxisSize: MainAxisSize.min, children: [for (final b in group) iconButton(b, width: 48)]),
            ),
        ],
      ],
    );

    // The bar spans its parent, as a UINavigationBar does, even where the
    // parent's width is loose (a Column).
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(top: barBottom),
              viewPadding: mq.viewPadding.copyWith(top: barBottom),
            ),
            child: child,
          ),
          if (bar.scrollEdgeEffect != NativeScrollEdgeEffect.none)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: barBottom + 24,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: scrolled ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: DecoratedBox(
                    // Opaque through the status bar, then fading out below the bar.
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        // Opaque behind the controls' row (where iOS blurs
                        // the content most), easing out below the bar.
                        colors: [
                          background,
                          background,
                          background.withValues(alpha: 0.9),
                          background.withValues(alpha: 0),
                        ],
                        stops: [0, (top + item) / (barBottom + 24), barBottom / (barBottom + 24), 1],
                      ),
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
          // The system's plain title: centred on the bar, clear of the
          // buttons on both sides.
          if (title != null && !title.capsule)
            Positioned(
              left: margin,
              right: margin,
              top: top,
              height: item,
              child: IgnorePointer(
                child: Material(
                  type: MaterialType.transparency,
                  child: CustomSingleChildLayout(
                    delegate: _TitleLayout(
                      leading: bar.leading == null ? 0 : item + spacing,
                      trailing: trailingWidth > 0 ? trailingWidth + spacing : 0,
                      centred: title.alignment == NativeBarTitleAlignment.center,
                    ),
                    child: titleText(
                      title.alignment == NativeBarTitleAlignment.center
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// UINavigationBar's title placement: centred on the bar while it fits,
/// otherwise moved into the space the buttons leave.
class _TitleLayout extends SingleChildLayoutDelegate {
  const _TitleLayout({required this.leading, required this.trailing, required this.centred});

  final double leading;
  final double trailing;

  /// Otherwise leading-aligned, right after the leading button.
  final bool centred;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    maxWidth: math.max(0, constraints.maxWidth - leading - trailing),
    maxHeight: constraints.maxHeight,
  );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final ideal = centred ? (size.width - childSize.width) / 2 : leading;
    final x = ideal.clamp(leading, math.max(leading, size.width - trailing - childSize.width)).toDouble();
    return Offset(x, (size.height - childSize.height) / 2);
  }

  @override
  bool shouldRelayout(_TitleLayout old) => old.leading != leading || old.trailing != trailing || old.centred != centred;
}
