import 'package:flutter/cupertino.dart';

import '../core/veneer_bridge.dart';
import 'native_control_view.dart';

/// UIKit's `UISlider` on iOS 26, laid out by Flutter (it works inside
/// Flutter-drawn sheets too); [CupertinoSlider] elsewhere. It fills the
/// width it's given.
class NativeSlider extends StatelessWidget {
  const NativeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.onChangeStart,
    this.onChangeEnd,
    this.activeColor,
    this.thumbColor,
  });

  final double value;

  /// Null disables the slider.
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor;
  final Color? thumbColor;

  static const double _height = 31;

  @override
  Widget build(BuildContext context) {
    if (!VeneerBridge.instance.isSupported) {
      return CupertinoSlider(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        activeColor: activeColor,
        thumbColor: thumbColor ?? CupertinoColors.white,
      );
    }
    return SizedBox(
      height: _height,
      child: NativeControlView(
        kind: 'slider',
        config: {
          'value': value,
          'min': min,
          'max': max,
          'enabled': onChanged != null,
          'activeColor': activeColor?.toARGB32(),
          'thumbColor': thumbColor?.toARGB32(),
        },
        onEvent: (method, arguments) {
          final value = (arguments['value']! as num).toDouble();
          switch (method) {
            case 'valueChanged':
              onChanged?.call(value);
            case 'changeStart':
              onChangeStart?.call(value);
            case 'changeEnd':
              onChangeEnd?.call(value);
          }
        },
      ),
    );
  }
}
