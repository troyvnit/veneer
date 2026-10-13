import 'package:flutter/cupertino.dart';

import '../core/veneer_bridge.dart';

enum NativeAlertActionStyle { normal, cancel, destructive }

/// A button in a [showNativeAlert].
@immutable
class NativeAlertAction {
  const NativeAlertAction({required this.title, this.style = NativeAlertActionStyle.normal, this.preferred = false});

  final String title;
  final NativeAlertActionStyle style;

  /// Emphasised as the default action — UIKit's `preferredAction`.
  final bool preferred;
}

/// Shows an alert and answers with the index of the action picked, or null
/// if it was dismissed some other way.
///
/// On iOS 26 it is UIKit's `UIAlertController`, presented over whatever the
/// app or sheet is showing; [tint] colours its buttons (e.g. a brand colour
/// for the preferred action). Only one action can be
/// [NativeAlertActionStyle.cancel]; extras become normal actions. Elsewhere
/// (Android, iOS 15–25) it is Flutter's [CupertinoAlertDialog].
Future<int?> showNativeAlert({
  required BuildContext context,
  required String title,
  String? message,
  required List<NativeAlertAction> actions,
  Color? tint,
}) async {
  final bridge = VeneerBridge.instance;
  if (bridge.isSupported) {
    return bridge.showAlert({
      'title': title,
      'message': message,
      'tint': tint?.toARGB32(),
      'actions': [
        for (final action in actions)
          {'title': action.title, 'style': action.style.name, 'preferred': action.preferred},
      ],
    });
  }
  return showCupertinoDialog<int>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        for (final (index, action) in actions.indexed)
          CupertinoDialogAction(
            isDefaultAction: action.preferred,
            isDestructiveAction: action.style == NativeAlertActionStyle.destructive,
            onPressed: () => Navigator.of(context).pop(index),
            child: Text(action.title),
          ),
      ],
    ),
  );
}
