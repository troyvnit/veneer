import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/native_icon.dart';
import '../core/veneer_bridge.dart';

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
  }) : assert(selectable || onPressed != null, 'A non-selectable action needs onPressed');

  final NativeIcon icon;

  /// Used for VoiceOver and the large content viewer.
  final String? title;
  final NativeIcon? selectedIcon;
  final String? badge;
  final VoidCallback? onPressed;
  final bool selectable;

  Map<String, Object?> _encode() => {
    'title': title,
    'icon': icon.encode(),
    'selectedIcon': selectedIcon?.encode(),
    'badge': badge,
    'selectable': selectable,
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
/// should respect the bar.
class NativeChromeScope extends StatefulWidget {
  const NativeChromeScope({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    this.trailingAction,
    this.tintColor,
    required this.child,
  });

  final List<NativeTabItem> tabs;

  /// Index into [tabs], or `tabs.length` for a selectable [trailingAction].
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  /// Adds the split layout's detached trailing button.
  final NativeTabAction? trailingAction;
  final Color? tintColor;
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
    _push();
  }

  @override
  void didUpdateWidget(NativeChromeScope old) {
    super.didUpdateWidget(old);
    _push();
  }

  void _push() {
    _bridge.setTabBar(
      {
        'items': [for (final t in widget.tabs) t._encode()],
        'action': widget.trailingAction?._encode(),
        'selectedIndex': widget.selectedIndex,
        'tintColor': widget.tintColor?.toARGB32(),
      },
      onSelected: (i) => widget.onTabSelected(i),
      onAction: () => widget.trailingAction?.onPressed?.call(),
    );
  }

  void _onInset() => setState(() {});

  @override
  void dispose() {
    _bridge.chromeBottomInset.removeListener(_onInset);
    _bridge.removeTabBar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = math.max(mq.padding.bottom, _bridge.chromeBottomInset.value);
    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(bottom: bottom),
        viewPadding: mq.viewPadding.copyWith(bottom: math.max(mq.viewPadding.bottom, bottom)),
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
