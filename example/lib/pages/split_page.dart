import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../app_icons.dart';

/// A split layout: two [NativeChromePane]s side by side, each with its own
/// native navigation bar spanning only its column. Widest on an iPad or an
/// unfolded iPhone Duo; it still fits a phone in portrait.
class SplitPage extends StatefulWidget {
  const SplitPage({super.key});

  @override
  State<SplitPage> createState() => _SplitPageState();
}

class _SplitPageState extends State<SplitPage> {
  int _selected = 0;

  static const _places = [
    ('Lakeside', 'assets/images/lake.jpg', 'A still morning on the water, mist lifting off the far shore.'),
    ('Coastline', 'assets/images/coast.jpg', 'Cliffs and surf at golden hour, the light low and warm.'),
    ('Alpine lake', 'assets/images/lake.jpg', 'Snowmelt-blue water under the ridge, an hour above the trailhead.'),
    ('Harbour', 'assets/images/coast.jpg', 'Fishing boats coming in as the fog burns off the bay.'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final listWidth = math.min(320.0, (width * 0.42).roundToDouble());
    const divider = 1.0;
    final (title, image, caption) = _places[_selected];
    final detailWidth = width - listWidth - divider;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: listWidth,
            child: NativeChromePane(
              id: 'list',
              left: 0,
              width: listWidth,
              child: NativeNavigationBar(
                leading: NativeBarButton(
                  icon: const NativeIcon.icon(AppIcons.caretLeft),
                  title: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: const NativeBarTitle(title: 'Places'),
                child: ListView(
                  children: [
                    for (final (i, (name, _, _)) in _places.indexed)
                      CupertinoListTile(
                        title: Text(name),
                        backgroundColor: i == _selected ? Theme.of(context).colorScheme.primaryContainer : null,
                        onTap: () => setState(() => _selected = i),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: divider, thickness: divider),
          Expanded(
            child: NativeChromePane(
              id: 'detail',
              left: listWidth + divider,
              width: detailWidth,
              child: NativeNavigationBar(
                title: NativeBarTitle(title: title),
                trailing: [
                  NativeBarButton(icon: const NativeIcon.icon(AppIcons.share), title: 'Share', onPressed: () {}),
                ],
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 12,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AspectRatio(
                              aspectRatio: detailWidth > 500 ? 16 / 9 : 3 / 4,
                              child: Image.asset(image, fit: BoxFit.cover),
                            ),
                          ),
                          Text(caption, style: Theme.of(context).textTheme.bodyLarge),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
