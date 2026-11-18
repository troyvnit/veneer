import 'package:flutter/widgets.dart';

/// One column of a split layout (a list beside its detail, say), with its
/// own native chrome.
///
/// Native chrome inside a pane stays within the pane's columns: each pane
/// gets its own `UINavigationBar` and scroll edge effects, and a
/// [NativeChromeScope] tab bar or a composer is laid out for the pane's width
/// instead of the screen's. Without a pane, chrome spans the screen as usual.
///
/// [left] and [width] are in logical pixels from the left edge of the
/// Flutter view, where the pane rests: chrome doesn't follow a route
/// transition sliding the pane's content.
///
/// Pair it with [NativePaneRoute] for routes that show in one pane, so a page
/// in another pane isn't treated as covered by them.
class NativeChromePane extends InheritedWidget {
  const NativeChromePane({super.key, required this.id, required this.left, required this.width, required super.child});

  /// Names the pane; chrome in panes with the same id is one set of chrome.
  final String id;
  final double left;
  final double width;

  static NativeChromePane? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NativeChromePane>();

  /// The pane's wire form, or null for the whole screen. Doesn't register a
  /// dependency (callable from `initState`); depend through [maybeOf].
  static Map<String, Object?>? encodeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NativeChromePane>()?._encode();

  Map<String, Object?> _encode() => {'id': id, 'left': left, 'width': width};

  @override
  bool updateShouldNotify(NativeChromePane oldWidget) =>
      id != oldWidget.id || left != oldWidget.left || width != oldWidget.width;
}

/// A route that shows in one [NativeChromePane] of a split layout rather
/// than over the whole screen.
///
/// Pages in other panes stay uncovered while it's on top: their navigation
/// bars, tab bar, composer and glass stay up. The route's navigator needs a
/// `VeneerNavigatorObserver` to tell which routes sit above a page.
mixin NativePaneRoute<T> on ModalRoute<T> {
  /// The id of the pane this route shows in, or null while it covers the
  /// whole screen (a narrow layout, say).
  String? get nativePane;
}
