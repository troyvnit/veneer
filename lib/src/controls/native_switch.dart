import 'package:flutter/cupertino.dart';

import '../core/veneer_bridge.dart';
import 'native_control_view.dart';

/// UIKit's `UISwitch` on iOS 26, laid out by Flutter (it works inside
/// Flutter-drawn sheets too); [CupertinoSwitch] elsewhere.
class NativeSwitch extends StatelessWidget {
  const NativeSwitch({super.key, required this.value, required this.onChanged, this.activeColor, this.thumbColor});

  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? thumbColor;

  static const Size _size = Size(63, 29);

  @override
  Widget build(BuildContext context) {
    if (!VeneerBridge.instance.isSupported) {
      return CupertinoSwitch(value: value, onChanged: onChanged, activeTrackColor: activeColor, thumbColor: thumbColor);
    }
    return SizedBox.fromSize(
      size: _size,
      child: NativeControlView(
        kind: 'switch',
        config: {
          'value': value,
          'enabled': onChanged != null,
          'activeColor': activeColor?.toARGB32(),
          'thumbColor': thumbColor?.toARGB32(),
        },
        onEvent: (method, arguments) {
          if (method == 'valueChanged') onChanged?.call(arguments['value']! as bool);
        },
      ),
    );
  }
}
