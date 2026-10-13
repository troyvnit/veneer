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
  const NativeMenuItem({
    required this.title,
    this.subtitle,
    this.icon,
    this.onSelected,
    this.destructive = false,
    this.checked = false,
    this.enabled = true,
  }) : isDivider = false;

  /// Separates the items before it from those after, as UIKit's inline menu
  /// sections do.
  const NativeMenuItem.divider()
    : title = '',
      subtitle = null,
      icon = null,
      onSelected = null,
      destructive = false,
      checked = false,
      enabled = true,
      isDivider = true;

  final String title;

  /// A second, smaller line under [title].
  final String? subtitle;
  final NativeIcon? icon;
  final VoidCallback? onSelected;

  /// Shown in red, for actions like Delete.
  final bool destructive;

  /// Shows a checkmark, as UIKit does for an action whose state is on — the
  /// current choice in a picker-style menu.
  final bool checked;

  /// False shows the item dimmed; it can't be picked.
  final bool enabled;

  final bool isDivider;

  Map<String, Object?> encode() => isDivider
      ? {'divider': true}
      : {
          'title': title,
          'icon': icon?.encode(),
          'destructive': destructive,
          if (subtitle != null) 'subtitle': subtitle,
          if (checked) 'checked': true,
          if (!enabled) 'enabled': false,
        };
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
Future<void> showFallbackMenu(BuildContext context, List<NativeMenuItem> items, {String? title}) async {
  const width = 250.0;
  const rowHeight = 44.0;
  const subtitledRowHeight = 58.0;
  const sectionGap = 8.0;
  const titleHeight = 36.0;
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final style = VeneerFallbackStyle.of(context);
  final screen = overlay.size;
  final above = rect.center.dy > screen.height / 2;
  double heightOf(NativeMenuItem item) =>
      item.isDivider ? sectionGap : (item.subtitle == null ? rowHeight : subtitledRowHeight);
  final height = items.fold<double>(title == null ? 0 : titleHeight, (sum, item) => sum + heightOf(item));
  // UIKit indents every row when any of them carries a checkmark.
  final hasChecks = items.any((item) => item.checked);
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
      if (title != null) _MenuTitle(title: title, color: style.secondaryLabel, height: titleHeight),
      for (final (i, item) in items.indexed)
        if (item.isDivider)
          _MenuSectionGap(color: band, height: sectionGap)
        else
          PopupMenuItem<int>(
            value: i,
            enabled: item.enabled,
            height: heightOf(item),
            padding: EdgeInsets.only(left: hasChecks ? 8 : 16, right: 16),
            child: _FallbackMenuRow(item: item, style: style, hasChecks: hasChecks),
          ),
    ],
  );
  if (picked != null) items[picked].onSelected?.call();
}

class _FallbackMenuRow extends StatelessWidget {
  const _FallbackMenuRow({required this.item, required this.style, required this.hasChecks});

  final NativeMenuItem item;
  final VeneerFallbackStyle style;
  final bool hasChecks;

  @override
  Widget build(BuildContext context) {
    final color = !item.enabled ? style.disabled : (item.destructive ? style.badge : style.label);
    return Row(
      children: [
        if (hasChecks) SizedBox(width: 26, child: item.checked ? Icon(Icons.check, size: 17, color: color) : null),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, color: color),
              ),
              if (item.subtitle case final subtitle?)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: item.enabled ? style.secondaryLabel : style.disabled),
                ),
            ],
          ),
        ),
        if (item.icon case final icon?) NativeIconView(icon, size: 20, color: color),
      ],
    );
  }
}

/// A menu's title, as UIKit draws it above the items.
class _MenuTitle extends PopupMenuEntry<int> {
  const _MenuTitle({required this.title, required this.color, required this.height});

  final String title;
  final Color color;

  @override
  final double height;

  @override
  bool represents(int? value) => false;

  @override
  State<_MenuTitle> createState() => _MenuTitleState();
}

class _MenuTitleState extends State<_MenuTitle> {
  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: widget.color),
        ),
      ),
    ),
  );
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
