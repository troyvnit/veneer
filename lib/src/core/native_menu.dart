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
  const NativeMenuItem({required this.title, this.icon, this.onSelected, this.destructive = false}) : isDivider = false;

  /// Separates the items before it from those after, as UIKit's inline menu
  /// sections do.
  const NativeMenuItem.divider() : title = '', icon = null, onSelected = null, destructive = false, isDivider = true;

  final String title;
  final NativeIcon? icon;
  final VoidCallback? onSelected;

  /// Shown in red, for actions like Delete.
  final bool destructive;

  final bool isDivider;

  Map<String, Object?> encode() =>
      isDivider ? {'divider': true} : {'title': title, 'icon': icon?.encode(), 'destructive': destructive};
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
///
/// Like UIKit: 250 pt wide, aligned to the button's leading edge (its
/// trailing edge for a button in the trailing half), below it (above it in
/// the lower half of the screen), an opaque surface, and dividers drawn as
/// the thin section bands between groups.
Future<void> showFallbackMenu(BuildContext context, List<NativeMenuItem> items) async {
  const width = 250.0;
  const rowHeight = 44.0;
  const sectionGap = 8.0;
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final style = VeneerFallbackStyle.of(context);
  final screen = overlay.size;
  final above = rect.center.dy > screen.height / 2;
  final height = items.fold<double>(0, (sum, item) => sum + (item.isDivider ? sectionGap : rowHeight));
  final top = above ? rect.top - height - 8 : rect.bottom + 8;
  final trailing = rect.center.dx > screen.width / 2;
  final left = (trailing ? rect.right - width : rect.left).clamp(8.0, screen.width - width - 8);
  // Glass-like surfaces may be translucent; a menu over content needs its
  // own opaque backing (iOS blurs, which showMenu can't).
  final surface = Color.alphaBlend(style.surface, Theme.of(context).scaffoldBackgroundColor);
  final band = Color.alphaBlend(style.border, Color.alphaBlend(Colors.black.withValues(alpha: 0.12), surface));
  final picked = await showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(left, top, screen.width - left - width, screen.height - top - height),
    color: surface,
    elevation: 12,
    menuPadding: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    constraints: const BoxConstraints.tightFor(width: width),
    shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
    items: [
      for (final (i, item) in items.indexed)
        if (item.isDivider)
          _MenuSectionGap(color: band, height: sectionGap)
        else
          PopupMenuItem<int>(
            value: i,
            height: rowHeight,
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

/// The band between menu sections.
class _MenuSectionGap extends PopupMenuEntry<int> {
  const _MenuSectionGap({required this.color, required this.height});

  final Color color;

  @override
  final double height;

  @override
  bool represents(int? value) => false;

  @override
  State<_MenuSectionGap> createState() => _MenuSectionGapState();
}

class _MenuSectionGapState extends State<_MenuSectionGap> {
  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: ColoredBox(color: widget.color),
  );
}
