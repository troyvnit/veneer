import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import 'app_icons.dart';
import 'data/travel.dart';

/// Renders the whole app with Veneer's Flutter replicas (what Android and
/// iOS 15–25 show) instead of native UIKit, switchable at runtime from
/// Explore's profile menu and the Components tab.
final ValueNotifier<bool> flutterReplicas = ValueNotifier(false);

/// Places saved with the heart button, by id.
final ValueNotifier<Set<String>> savedPlaces = ValueNotifier({'kyoto', 'moraine'});

void toggleSaved(String id) {
  final next = {...savedPlaces.value};
  if (!next.remove(id)) next.add(id);
  savedPlaces.value = next;
}

/// A native in-app banner on iOS 26; a snack bar under the Flutter replicas.
Future<void> notify(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String body,
  IconData glyph = AppIcons.compassFill,
}) async {
  if (useNativeLayer(context)) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shown = await showNativeBanner(
      title: title,
      subtitle: subtitle,
      body: body,
      trailing: 'now',
      icon: NativeIcon.icon(glyph),
      style: NativeBannerStyle(
        dark: dark,
        iconBackground: accent,
        titleStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
    if (shown) return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('$title — $body'), behavior: SnackBarBehavior.floating));
}

/// The tint for glass laid over photos. Native glass blurs and darkens what
/// is behind it, so a light tint is enough; the flat Flutter replica needs a
/// stronger one to keep white text readable.
Color photoGlassTint(BuildContext context) =>
    useNativeLayer(context) ? const Color(0x33000000) : const Color(0x8C000000);
