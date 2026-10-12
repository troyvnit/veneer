import 'package:flutter/widgets.dart';

import '../core/native_menu.dart';
import '../glass/glass_shape.dart';

/// Tapping [child] opens a menu of [items], growing out of it.
///
/// For a trigger Flutter draws itself — a text row with a chevron, a filled
/// pill, an icon — where [GlassShape.menu] would need the trigger to be glass.
/// On iOS 26 it's UIKit's own `UIMenu`: an invisible native button
/// ([GlassStyle.none]) sits over [child] and takes the tap, so [child] gets
/// no touches of its own. Elsewhere (Android, iOS 15–25) a tap opens the
/// Flutter replica of a native menu next to [child].
class NativeMenuAnchor extends StatelessWidget {
  const NativeMenuAnchor({super.key, required this.items, required this.child});

  /// Empty disables the menu; [child] then gets its own touches.
  final List<NativeMenuItem> items;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: GlassShape(style: GlassStyle.none, menu: items),
        ),
      ],
    );
  }
}
