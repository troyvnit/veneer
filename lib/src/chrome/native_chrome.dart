import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/fallback_style.dart';
import '../core/native_icon.dart';
import '../core/route_visibility.dart';
import '../core/veneer_bridge.dart';
import 'native_navigation_bar.dart' show NativeScrollEdgeEffect;

/// A tab in the native tab bar.
@immutable
class NativeTabItem {
  const NativeTabItem({required this.title, required this.icon, this.selectedIcon, this.badge});

  final String title;

  /// SF Symbol, IconData or SVG — see [NativeIcon].
  final NativeIcon icon;

  /// Shown while selected (iOS 26.1+), e.g. the `.fill` variant.
  final NativeIcon? selectedIcon;

  /// Badge text; an empty string shows a dot-sized badge.
  final String? badge;

  Map<String, Object?> _encode() => {
    'title': title,
    'icon': icon.encode(),
    'selectedIcon': selectedIcon?.encode(),
    'badge': badge,
  };
}

/// The trailing button of the tab bar's split layout: a separate glass
/// button at the trailing edge, like the Search tab in Apple's apps.
///
/// By default it's a button: tapping calls [onPressed] and the selected tab
/// doesn't change. With [selectable] it's a tab of its own, reported to
/// `onTabSelected` as index `tabs.length`.
@immutable
class NativeTabAction {
  const NativeTabAction({
    required this.icon,
    this.title,
    this.selectedIcon,
    this.badge,
    this.onPressed,
    this.selectable = false,
    this.iconSize,
  }) : assert(selectable || onPressed != null, 'A non-selectable action needs onPressed');

  final NativeIcon icon;

  /// Used for VoiceOver and the large content viewer.
  final String? title;
  final NativeIcon? selectedIcon;
  final String? badge;
  final VoidCallback? onPressed;
  final bool selectable;

  /// Side of a non-symbol icon's box (default 25 pt natively, 26 pt in the
  /// Flutter replica). SF Symbols keep the tab bar's own metrics.
  final double? iconSize;

  Map<String, Object?> _encode() => {
    'title': title,
    'icon': icon.encode(),
    'selectedIcon': selectedIcon?.encode(),
    'badge': badge,
    'selectable': selectable,
    'iconSize': iconSize,
  };
}

/// Shows a native tab bar above the Flutter surface and adds its height to
/// [MediaQuery] padding so Flutter content scrolls underneath it.
///
/// The bar is a real `UITabBarController` (its tabs host empty,
/// touch-transparent pages), not a platform view: the floating Liquid Glass
/// bar, selection animation, badges, split layout with [trailingAction],
/// VoiceOver and the large content viewer are all UIKit's.
///
/// Place below `MaterialApp`/`CupertinoApp` and above the `Scaffold`s that
/// should respect the bar. While another route covers the page holding the
/// scope (a pushed screen, a dialog), the bar slides away.
class NativeChromeScope extends StatefulWidget {
  const NativeChromeScope({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    this.trailingAction,
    this.tintColor,
    this.scrollEdgeEffect = NativeScrollEdgeEffect.none,
    required this.child,
  }) : assert(
         tabs.length + (trailingAction == null ? 0 : 1) <= 5,
         'UITabBarController shows at most 5 items on iPhone; more collapse into a "More" tab and the '
         'trailing split button disappears. Use up to 4 tabs with a trailingAction, or 5 without.',
       );

  final List<NativeTabItem> tabs;

  /// Index into [tabs], or `tabs.length` for a selectable [trailingAction].
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  /// Adds the split layout's detached trailing button.
  final NativeTabAction? trailingAction;
  final Color? tintColor;

  /// iOS 26's edge effect above the tab bar: content fades as it scrolls
  /// under the bar.
  final NativeScrollEdgeEffect scrollEdgeEffect;
  final Widget child;

  @override
  State<NativeChromeScope> createState() => _NativeChromeScopeState();
}

class _NativeChromeScopeState extends State<NativeChromeScope> {
  final VeneerBridge _bridge = VeneerBridge.instance;

  @override
  void initState() {
    super.initState();
    _bridge.chromeBottomInset.addListener(_onInset);
    _bridge.chromeTopInset.addListener(_onInset);
    _push();
  }

  @override
  void didUpdateWidget(NativeChromeScope old) {
    super.didUpdateWidget(old);
    _push();
  }

  String? _lastSent;

  void _push() {
    if (!_bridge.isSupported) return;
    final config = <String, Object?>{
      'items': [for (final t in widget.tabs) t._encode()],
      'action': widget.trailingAction?._encode(),
      'selectedIndex': widget.selectedIndex,
      'tintColor': widget.tintColor?.toARGB32(),
      'edgeEffect': widget.scrollEdgeEffect.name,
    };
    // Rebuilds (e.g. MediaQuery changes during keyboard animation) resend
    // nothing unless the bar actually changed.
    final encoded = jsonEncode(config);
    if (encoded == _lastSent) return;
    _lastSent = encoded;
    _bridge.setTabBar(
      config,
      onSelected: (i) => widget.onTabSelected(i),
      onAction: () => widget.trailingAction?.onPressed?.call(),
    );
  }

  void _onInset() => setState(() {});

  bool _covered = false;
  late final RouteChainWatcher _routes = RouteChainWatcher(() {
    if (mounted) _updateCovered();
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routes.update(context);
    _updateCovered();
  }

  void _updateCovered() {
    // A route pushed over this page hides the bar, as UIKit's
    // hidesBottomBarWhenPushed does; it slides back as the route pops.
    final covered = !isRouteOnTop(context);
    if (covered != _covered && _bridge.isSupported) {
      _covered = covered;
      _bridge.setTabBarCovered(covered);
    }
  }

  @override
  void dispose() {
    _routes.dispose();
    _bridge.chromeBottomInset.removeListener(_onInset);
    _bridge.chromeTopInset.removeListener(_onInset);
    if (_covered) _bridge.setTabBarCovered(false);
    _bridge.removeTabBar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_bridge.isSupported) return _FallbackChrome(widget);
    final mq = MediaQuery.of(context);
    final bottom = math.max(mq.padding.bottom, _bridge.chromeBottomInset.value);
    final top = math.max(mq.padding.top, _bridge.chromeTopInset.value);
    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(top: top, bottom: bottom),
        viewPadding: mq.viewPadding.copyWith(
          top: math.max(mq.viewPadding.top, top),
          bottom: math.max(mq.viewPadding.bottom, bottom),
        ),
      ),
      child: widget.child,
    );
  }
}

/// Fades native chrome out while a Flutter popup (dialog, bottom sheet,
/// menu) is showing, since Flutter cannot draw above native views.
class VeneerNavigatorObserver extends NavigatorObserver {
  int _popups = 0;

  void _update(int delta) {
    _popups = math.max(0, _popups + delta);
    VeneerBridge.instance.setChromeHidden(_popups > 0);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _update(1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _update(-1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _update(-1);
  }
}

/// Flutter replica of the native tab bar, for Android and iOS 15–25: the
/// same floating 61 pt capsule with 20 pt margins, a pill behind the
/// selected item, 24 pt icons over 10 pt labels, and the split layout's
/// separate 61 pt trailing circle 8 pt away — solid instead of glass. It
/// floats over the content, which gets bottom padding for it, as natively.
class _FallbackChrome extends StatelessWidget {
  const _FallbackChrome(this.scope);

  final NativeChromeScope scope;

  static const double barHeight = 61;
  static const double margin = 20;
  static const double splitGap = 8;

  /// Face ID iPhones place the bar ~22 pt above the screen edge
  /// (34 pt home-indicator inset − 12); other devices keep 12 pt. Android's
  /// gesture handle sits inside its inset, so the bar clears it.
  static double bottomGap(MediaQueryData mq) {
    final inset = mq.viewPadding.bottom;
    if (defaultTargetPlatform == TargetPlatform.android) return inset + 8;
    return inset > 0 ? math.max(inset - 12, 8) : 12;
  }

  /// UIKit sizes the tab group to its items, up to the width available.
  static const double tabWidth = 94;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final style = VeneerFallbackStyle.of(context);
    final accent = scope.tintColor ?? style.accent;
    final gap = bottomGap(mq);
    final inset = gap + barHeight;
    final action = scope.trailingAction;
    final actionIndex = scope.tabs.length;

    final capsule = DecoratedBox(
      decoration: style.surfaceDecoration(radius: BorderRadius.circular(barHeight / 2)),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final (i, tab) in scope.tabs.indexed)
              Expanded(
                child: _FallbackTabItem(
                  title: tab.title,
                  icon: i == scope.selectedIndex ? (tab.selectedIcon ?? tab.icon) : tab.icon,
                  badge: tab.badge,
                  selected: i == scope.selectedIndex,
                  accent: accent,
                  style: style,
                  onTap: () => scope.onTabSelected(i),
                ),
              ),
          ],
        ),
      ),
    );

    return Stack(
      children: [
        MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(bottom: math.max(mq.padding.bottom, inset)),
            viewPadding: mq.viewPadding.copyWith(bottom: math.max(mq.viewPadding.bottom, inset)),
          ),
          child: scope.child,
        ),
        Positioned(
          left: margin,
          right: margin,
          bottom: gap,
          height: barHeight,
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: action == null ? Alignment.center : Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: tabWidth * scope.tabs.length + 8),
                      child: capsule,
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: splitGap),
                  Semantics(
                    button: true,
                    selected: action.selectable && scope.selectedIndex == actionIndex,
                    label: action.title,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: action.selectable ? () => scope.onTabSelected(actionIndex) : action.onPressed,
                      child: Container(
                        width: barHeight,
                        height: barHeight,
                        decoration: style.surfaceDecoration(shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: _Badged(
                          badge: action.badge,
                          style: style,
                          child: NativeIconView(
                            action.selectable && scope.selectedIndex == actionIndex
                                ? (action.selectedIcon ?? action.icon)
                                : action.icon,
                            size: action.iconSize ?? 26,
                            color: action.selectable && scope.selectedIndex == actionIndex ? accent : style.label,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FallbackTabItem extends StatelessWidget {
  const _FallbackTabItem({
    required this.title,
    required this.icon,
    required this.badge,
    required this.selected,
    required this.accent,
    required this.style,
    required this.onTap,
  });

  final String title;
  final NativeIcon icon;
  final String? badge;
  final bool selected;
  final Color accent;
  final VeneerFallbackStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : style.label;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? style.selection : style.selection.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(27),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Badged(
                badge: badge,
                style: style,
                child: NativeIconView(icon, size: 26, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An iOS-style red badge at the icon's top trailing corner.
class _Badged extends StatelessWidget {
  const _Badged({required this.badge, required this.style, required this.child});

  final String? badge;
  final VeneerFallbackStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final badge = this.badge;
    if (badge == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -6,
          right: -10,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: EdgeInsets.symmetric(horizontal: badge.length > 1 ? 5 : 0),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: style.badge, borderRadius: BorderRadius.circular(9)),
            child: badge.isEmpty
                ? null
                : Text(
                    badge,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }
}
