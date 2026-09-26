import 'package:flutter/material.dart';

import 'fallback_style.dart';
import 'native_icon.dart';

/// An item in a native `UIMenu`, opened by tapping a button that has a
/// `menu` (e.g. `NativeComposerButton.menu`, `NativeBarButton.menu`).
///
/// On iOS 26 the menu is UIKit's own: it grows out of the button in Liquid
/// Glass and dismisses natively. Elsewhere a Flutter replica opens at the
/// button with iOS metrics: 250 pt wide, 14 pt radius, 44 pt rows, the title
/// leading and the icon trailing.
@immutable
class NativeMenuItem {
  const NativeMenuItem({required this.title, this.icon, this.onSelected, this.destructive = false});

  final String title;
  final NativeIcon? icon;
  final VoidCallback? onSelected;

  /// Shown in red, for actions like Delete.
  final bool destructive;

  Map<String, Object?> encode() => {'title': title, 'icon': icon?.encode(), 'destructive': destructive};
}

/// Encodes [menu] and registers each item's callback in [handlers] under
/// `"<id>.menu<i>"`, the id the native side reports when it's picked.
List<Map<String, Object?>>? encodeMenu(String id, List<NativeMenuItem>? menu, Map<String, VoidCallback?> handlers) {
  if (menu == null || menu.isEmpty) return null;
  for (final (i, item) in menu.indexed) {
    handlers['$id.menu$i'] = item.onSelected;
  }
  return [for (final item in menu) item.encode()];
}

/// Opens the Flutter replica of a native menu next to the widget at [context].
Future<void> showFallbackMenu(BuildContext context, List<NativeMenuItem> items) async {
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final style = VeneerFallbackStyle.of(context);
  // Above the button when it's in the lower half, as UIKit does.
  final above = rect.center.dy > overlay.size.height / 2;
  final height = items.length * 44.0;
  final top = above ? rect.top - height - 8 : rect.bottom + 8;
  final picked = await showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(rect.left, top, overlay.size.width - rect.left, overlay.size.height - top - height),
    color: style.surface,
    elevation: 12,
    menuPadding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 250),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    items: [
      for (final (i, item) in items.indexed)
        PopupMenuItem<int>(
          value: i,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(fontSize: 17, color: item.destructive ? style.badge : style.label),
                ),
              ),
              if (item.icon case final icon?)
                NativeIconView(icon, size: 20, color: item.destructive ? style.badge : style.label),
            ],
          ),
        ),
    ],
  );
  if (picked != null) items[picked].onSelected?.call();
}
