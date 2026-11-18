import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../app_icons.dart';
import 'diagnostics_page.dart';
import 'search_page.dart';
import 'split_page.dart';

/// A tour of the smaller components: UIKit controls, alerts and banners,
/// menus from Flutter-drawn triggers, glass behind Flutter content, the
/// segment bar and search field, and pages for the search toolbar and split
/// layouts.
class ComponentsPage extends StatefulWidget {
  const ComponentsPage({super.key});

  @override
  State<ComponentsPage> createState() => _ComponentsPageState();
}

enum _Status {
  available('Available', 'Shown as active'),
  focusing('Focusing', 'Notifications paused'),
  away('Away', 'Back in an hour');

  const _Status(this.label, this.detail);

  final String label;
  final String detail;
}

class _ComponentsPageState extends State<ComponentsPage> {
  bool _notifications = true;
  double _volume = 0.6;
  int _role = 0;
  _Status _status = _Status.available;
  int _category = 0;
  final TextEditingController _query = TextEditingController();
  final GlobalKey<NativeSearchFieldState> _search = GlobalKey();

  static const _categories = [
    GlassSegment(icon: NativeIcon.symbol('clock'), label: 'Recent'),
    GlassSegment(icon: NativeIcon.symbol('face.smiling'), label: 'Smileys'),
    GlassSegment(icon: NativeIcon.symbol('leaf'), label: 'Nature'),
    GlassSegment(icon: NativeIcon.symbol('fork.knife'), label: 'Food'),
    GlassSegment(icon: NativeIcon.symbol('airplane'), label: 'Travel'),
  ];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _showAlert() async {
    final picked = await showNativeAlert(
      context: context,
      title: 'Leave launch-crew?',
      message: 'You won’t get its messages until someone adds you back.',
      tint: Theme.of(context).colorScheme.primary,
      actions: const [
        NativeAlertAction(title: 'Leave', style: NativeAlertActionStyle.destructive, preferred: true),
        NativeAlertAction(title: 'Cancel', style: NativeAlertActionStyle.cancel),
      ],
    );
    if (picked == 0) _snack('Left the channel');
  }

  Future<void> _showBanner() async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final shown = await showNativeBanner(
      title: 'launch-crew',
      trailing: 'now',
      subtitle: 'Maya Chen',
      body: 'The build is green — shipping the beta to testers this afternoon. 🚀',
      icon: const NativeIcon.icon(AppIcons.chatsCircleFill),
      badge: const NativeIcon.symbol('heart.circle.fill'),
      style: NativeBannerStyle(
        dark: dark,
        iconBackground: scheme.primaryContainer,
        titleStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      onTap: () => _snack('Opened the message'),
    );
    // No Flutter replica: elsewhere the app draws its own.
    if (!shown) _snack('Maya Chen in launch-crew: the build is green 🚀');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(context),
      body: NativeNavigationBar(
        title: const NativeBarTitle(title: 'Components'),
        trailing: [
          NativeBarButton(
            icon: const NativeIcon.icon(AppIcons.gauge),
            title: 'Lab',
            onPressed: () => _push(const DiagnosticsPage()),
          ),
        ],
        // Keeps the rows clear of a tab bar shown as a side column.
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            children: [
              CupertinoListSection.insetGrouped(
                header: const Text('Controls'),
                footer: const _Footer('UIKit’s own switch, slider and segmented control, laid out by Flutter.'),
                children: [
                  CupertinoListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Notifications'),
                    trailing: NativeSwitch(
                      value: _notifications,
                      activeColor: scheme.primary,
                      onChanged: (v) => setState(() => _notifications = v),
                    ),
                  ),
                  CupertinoListTile(
                    leading: const Icon(AppIcons.speakerHigh),
                    title: SizedBox(
                      height: 32,
                      child: NativeSlider(
                        value: _volume,
                        activeColor: scheme.primary,
                        onChanged: (v) => setState(() => _volume = v),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: NativeSegmentedControl(
                      labels: const ['Member', 'Admin', 'Owner'],
                      selectedIndex: _role,
                      onValueChanged: (i) => setState(() => _role = i),
                    ),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('Menus'),
                footer: const _Footer('Tap the status row for a native menu; long-press the card for a context menu.'),
                children: [
                  NativeMenuAnchor(
                    title: 'Set a status',
                    items: [
                      for (final status in _Status.values)
                        NativeMenuItem(
                          title: status.label,
                          subtitle: status.detail,
                          checked: status == _status,
                          onSelected: () => setState(() => _status = status),
                        ),
                    ],
                    child: CupertinoListTile(
                      leading: const Icon(AppIcons.circleFill, color: CupertinoColors.systemGreen),
                      title: const Text('Status'),
                      additionalInfo: Text(_status.label),
                      trailing: const Icon(CupertinoIcons.chevron_up_chevron_down, size: 16),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: NativeContextMenu(
                      borderRadius: BorderRadius.circular(18),
                      items: [
                        NativeMenuItem(
                          title: 'Reply',
                          icon: const NativeIcon.symbol('arrowshape.turn.up.left'),
                          onSelected: () => _snack('Reply'),
                        ),
                        NativeMenuItem(
                          title: 'Copy',
                          icon: const NativeIcon.icon(AppIcons.copy),
                          onSelected: () => _snack('Copied'),
                        ),
                        const NativeMenuItem.divider(),
                        NativeMenuItem(
                          title: 'Delete',
                          icon: const NativeIcon.icon(AppIcons.trash),
                          destructive: true,
                          onSelected: () => _snack('Deleted'),
                        ),
                      ],
                      child: const _MessageCard(),
                    ),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('Alerts and banners'),
                footer: const _Footer(
                  'The banner drops in above the tab bar, bars and sheets, in a window of its own.',
                ),
                children: [
                  CupertinoListTile(
                    leading: const Icon(AppIcons.trash),
                    title: const Text('Show an alert'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _showAlert,
                  ),
                  CupertinoListTile(
                    leading: const Icon(AppIcons.chatsCircle),
                    title: const Text('Show a banner'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: _showBanner,
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('Glass'),
                footer: const _Footer(
                  'Liquid Glass behind Flutter text, a segment bar with a sliding highlight, and a real '
                  'UISearchTextField on glass.',
                ),
                children: [
                  _GlassStage(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 16,
                      children: [
                        GlassBackground(
                          onTap: () => _snack('Now playing'),
                          child: const IgnorePointer(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(12, 10, 20, 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 10,
                                children: [
                                  Icon(AppIcons.playFill, color: Colors.white),
                                  Text(
                                    'Golden hour · Lakeside',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        GlassSegmentBar(
                          segments: _categories,
                          selectedIndex: _category,
                          onSelected: (i) => setState(() => _category = i),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: NativeSearchField(
                      key: _search,
                      placeholder: 'Search messages',
                      controller: _query,
                      onSubmitted: (q) {
                        _search.currentState?.unfocus();
                        _snack('Searching for “$q”');
                      },
                    ),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('Pages'),
                children: [
                  CupertinoListTile(
                    leading: const Icon(CupertinoIcons.search),
                    title: const Text('Search toolbar'),
                    subtitle: const Text('The system search at the bottom of the screen'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => _push(const SearchPage()),
                  ),
                  CupertinoListTile(
                    leading: const Icon(AppIcons.squaresFour),
                    title: const Text('Split layout'),
                    subtitle: const Text('A navigation bar per column'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => _push(const SplitPage()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section footer in the system's secondary label colour.
class _Footer extends StatelessWidget {
  const _Footer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 13, color: CupertinoColors.secondaryLabel.resolveFrom(context)));
}

/// A chat bubble for the context menu to lift.
class _MessageCard extends StatelessWidget {
  const _MessageCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primary,
              child: Text('MC', style: TextStyle(color: scheme.onPrimary, fontSize: 13)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    'Maya Chen',
                    style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer),
                  ),
                  Text(
                    'Long-press me for the native context menu.',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A photo for the glass to refract.
class _GlassStage extends StatelessWidget {
  const _GlassStage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/lake.jpg', fit: BoxFit.cover),
          Center(child: child),
        ],
      ),
    );
  }
}
