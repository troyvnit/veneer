import 'package:flutter/widgets.dart';

import '../controls/native_control_view.dart';
import '../core/fallback_scope.dart';
import '../core/native_menu.dart';
import '../core/veneer_bridge.dart';
import '../glass/glass_shape.dart';

/// Tapping [child] opens a menu of [items], growing out of it.
///
/// For a trigger Flutter draws itself — a text row with a chevron, a filled
/// pill, an icon — where [GlassShape.menu] would need the trigger to be glass.
/// On iOS 26 it's UIKit's own `UIMenu`: an invisible native button
/// ([GlassStyle.none]) sits over [child] and takes the tap, so [child] gets
/// no touches of its own. Inside content the overlay can't follow (a
/// [VeneerFallbackScope], such as a Flutter-drawn sheet) that button is a
/// platform view instead, so the menu is still UIKit's. Elsewhere (Android,
/// iOS 15–25) a tap opens the Flutter replica of a native menu next to
/// [child].
class NativeMenuAnchor extends StatelessWidget {
  const NativeMenuAnchor({super.key, required this.items, required this.child, this.title});

  /// Empty disables the menu; [child] then gets its own touches.
  final List<NativeMenuItem> items;
  final Widget child;

  /// Heads the menu, as UIKit draws a menu's title.
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return child;
    final inPlatformView = VeneerBridge.instance.isSupported && !useNativeLayer(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: inPlatformView
              ? NativeControlView(
                  kind: 'menu',
                  config: {'menu': encodeMenu('menu', items, {}), 'menuTitle': title},
                  onEvent: (method, arguments) {
                    final index = arguments['index'];
                    if (method == 'menuItem' && index is int && index < items.length) {
                      items[index].onSelected?.call();
                    }
                  },
                )
              : GlassShape(style: GlassStyle.none, menu: items, menuTitle: title),
        ),
      ],
    );
  }
}
