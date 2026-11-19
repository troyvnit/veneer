import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../app_icons.dart';
import '../app_state.dart';
import '../data/travel.dart';
import 'explore_page.dart';
import 'stay_sheet.dart';

/// A place: the photo runs under the native navigation bar, whose glass
/// buttons sit right on it; a native segmented control switches sections;
/// and two glass buttons float over the page — one opens a native menu of
/// trips, the other a native sheet to book a stay.
class PlacePage extends StatefulWidget {
  const PlacePage({super.key, required this.place});

  final Place place;

  @override
  State<PlacePage> createState() => _PlacePageState();
}

class _PlacePageState extends State<PlacePage> {
  int _section = 0;

  Place get place => widget.place;

  void _addToTrip(Trip trip) => notify(
    context,
    title: trip.name,
    subtitle: 'Trip updated',
    body: '${place.name} was added to ${trip.name}.',
    glyph: AppIcons.suitcaseRollingFill,
  );

  Future<void> _bookStay() async {
    final result = await openStaySheet(context, place);
    if (result == null || !mounted) return;
    notify(context, title: 'Booked', subtitle: place.title, body: result, glyph: AppIcons.bed);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: NativeNavigationBar(
        leading: NativeBarButton(
          icon: const NativeIcon.icon(AppIcons.caretLeft),
          title: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        trailing: [
          NativeBarButton(
            icon: NativeIcon.icon(savedPlaces.value.contains(place.id) ? AppIcons.heartFill : AppIcons.heart),
            title: 'Save',
            tint: savedPlaces.value.contains(place.id) ? accent : null,
            onPressed: () => setState(() => toggleSaved(place.id)),
          ),
          NativeBarButton(
            icon: const NativeIcon.icon(AppIcons.share),
            title: 'Share',
            onPressed: () => notify(
              context,
              title: 'Link copied',
              subtitle: place.title,
              body: 'Paste it anywhere to share ${place.name}.',
              glyph: AppIcons.share,
            ),
          ),
        ],
        child: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            final wide = size.width > 700;
            return Stack(
              children: [
                ListView(
                  padding: EdgeInsets.only(bottom: padding.bottom + 96),
                  children: [
                    SizedBox(
                      height: wide ? size.height * 0.62 : size.height * 0.5,
                      child: Image.asset(place.image, fit: BoxFit.cover),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(20 + padding.left, 20, 20 + padding.right, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(place.name, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          _Meta(place: place),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: NativeSegmentedControl(
                              labels: const ['Overview', 'Tips', 'Photos'],
                              selectedIndex: _section,
                              onValueChanged: (i) => setState(() => _section = i),
                            ),
                          ),
                          const SizedBox(height: 20),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: switch (_section) {
                              0 => _Overview(key: const ValueKey(0), place: place),
                              1 => _Tips(key: const ValueKey(1), place: place),
                              _ => _Photos(key: const ValueKey(2), place: place),
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 16 + padding.left,
                  right: 16 + padding.right,
                  bottom: padding.bottom + 12,
                  child: GlassGroup(
                    zIndex: 1,
                    child: Row(
                      children: [
                        Expanded(
                          child: GlassShape(
                            height: 56,
                            icon: const NativeIcon.icon(AppIcons.suitcaseRolling),
                            label: 'Add to trip',
                            menuTitle: 'Add ${place.name} to',
                            menu: [
                              for (final trip in trips.where((t) => !t.past))
                                NativeMenuItem(
                                  title: trip.name,
                                  subtitle: trip.dates,
                                  icon: NativeIcon.image(trip.cover),
                                  iconSize: 32,
                                  onSelected: () => _addToTrip(trip),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GlassShape(
                            height: 56,
                            icon: const NativeIcon.icon(AppIcons.bed),
                            label: 'Book a stay',
                            tint: accent,
                            foreground: Colors.white,
                            onTap: _bookStay,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(AppIcons.mapPinFill, size: 16, color: accent),
        const SizedBox(width: 4),
        Text(place.country, style: TextStyle(fontSize: 16, color: secondary)),
        const SizedBox(width: 14),
        const Icon(AppIcons.starFill, size: 16, color: Color(0xFFFFB800)),
        const SizedBox(width: 4),
        Text('${place.rating}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        Text(' · ${place.reviews} reviews', style: TextStyle(fontSize: 16, color: secondary)),
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({super.key, required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(place.blurb, style: const TextStyle(fontSize: 17, height: 1.45)),
        const SizedBox(height: 20),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: [
            _Fact(icon: AppIcons.calendarBlank, label: 'Best time', value: place.bestTime),
            _Fact(icon: AppIcons.airplaneTilt, label: 'From London', value: place.flight),
            _Fact(icon: AppIcons.wallet, label: 'Daily budget', value: '\$${place.budget}'),
            _Fact(icon: AppIcons.cloudSun, label: 'In season', value: '24°'),
          ],
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Icon(icon, size: 24, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips({super.key, required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (i, tip) in place.tips.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: accent,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(tip, style: const TextStyle(fontSize: 17, height: 1.4))),
              ],
            ),
          ),
      ],
    );
  }
}

class _Photos extends StatelessWidget {
  const _Photos({super.key, required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final related = [
      for (final p in places)
        if (p.mood == place.mood && p.id != place.id) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            for (final image in [place.image, ...place.gallery])
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(image, fit: BoxFit.cover, cacheWidth: 600),
              ),
          ],
        ),
        if (related.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'More ${place.mood.label.toLowerCase()}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: related.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => SizedBox(width: 160, child: PlaceTile(place: related[i])),
            ),
          ),
        ],
      ],
    );
  }
}
