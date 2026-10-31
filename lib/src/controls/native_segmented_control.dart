import 'package:flutter/cupertino.dart';

import '../core/veneer_bridge.dart';
import 'native_control_view.dart';

/// UIKit's `UISegmentedControl` with text segments on iOS 26, laid out by
/// Flutter (it works inside Flutter-drawn sheets too);
/// [CupertinoSlidingSegmentedControl] elsewhere. It fills the width it's
/// given. For icon segments on glass, see [GlassSegmentBar].
class NativeSegmentedControl extends StatelessWidget {
  const NativeSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    this.enabled = true,
    this.selectedColor,
    this.textColor,
    this.selectedTextColor,
    this.textStyle,
    this.selectedTextStyle,
    this.height = 32,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onValueChanged;
  final bool enabled;

  /// The selected segment's fill.
  final Color? selectedColor;
  final Color? textColor;
  final Color? selectedTextColor;

  /// The segments' font: family, size and weight. Without one, UIKit's
  /// 13 pt system font.
  final TextStyle? textStyle;

  /// The selected segment's font; defaults to [textStyle].
  final TextStyle? selectedTextStyle;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!VeneerBridge.instance.isSupported) {
      return SizedBox(
        height: height,
        child: CupertinoSlidingSegmentedControl<int>(
          groupValue: selectedIndex,
          thumbColor: selectedColor ?? CupertinoColors.white,
          onValueChanged: (index) {
            if (enabled && index != null) onValueChanged(index);
          },
          children: {
            for (final (index, label) in labels.indexed)
              index: Text(
                label,
                style: ((index == selectedIndex ? selectedTextStyle ?? textStyle : textStyle) ?? const TextStyle())
                    .copyWith(color: index == selectedIndex ? selectedTextColor : textColor),
              ),
          },
        ),
      );
    }
    return SizedBox(
      height: height,
      child: NativeControlView(
        kind: 'segmented',
        config: {
          'labels': labels,
          'selectedIndex': selectedIndex,
          'enabled': enabled,
          'selectedColor': selectedColor?.toARGB32(),
          'textColor': textColor?.toARGB32(),
          'selectedTextColor': selectedTextColor?.toARGB32(),
          'font': _encodeFont(textStyle),
          'selectedFont': _encodeFont(selectedTextStyle ?? textStyle),
        },
        onEvent: (method, arguments) {
          if (method == 'valueChanged') onValueChanged(arguments['index']! as int);
        },
      ),
    );
  }
}

Map<String, Object?>? _encodeFont(TextStyle? style) =>
    style == null ? null : {'family': style.fontFamily, 'size': style.fontSize, 'weight': style.fontWeight?.value};
