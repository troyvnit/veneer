import 'dart:convert';

import 'package:flutter/widgets.dart';

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

/// A native `UINavigationBar` shown while this widget's page is visible.
///
/// Place it anywhere in a page under a [NativeChromeScope]; it renders
/// nothing in Flutter. The bar's height is added to `MediaQuery` top padding
/// so content starts below it and scrolls under it, fading into the
/// [scrollEdgeEffect].
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
  });

  final NativeBarButton? leading;
  final NativeBarTitle? title;

  /// In reading order; UIKit shares one glass capsule between them.
  final List<NativeBarButton> trailing;
  final Color? tintColor;
  final NativeScrollEdgeEffect scrollEdgeEffect;

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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
