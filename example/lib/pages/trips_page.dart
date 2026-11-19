import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../app_icons.dart';
import '../app_state.dart';
import '../data/travel.dart';

/// Trips. On a phone, a list that pushes each trip; on a wide screen (the
/// unfolded iPhone Duo, iPhone landscape) a split layout: two
/// [NativeChromePane]s, each with its own native navigation bar.
class TripsPage extends StatefulWidget {
  const TripsPage({super.key});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  String _selected = trips.first.id;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < 700) {
      return _TripList(
        onOpen: (trip) =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => TripDetail(trip: trips.firstWhere((t) => t.id == trip)))),
      );
    }
    // The tab bar is a side column here: leave its inset out of the panes.
    final right = MediaQuery.paddingOf(context).right;
    final listWidth = math.min(340.0, (size.width * 0.38).roundToDouble());
    const divider = 1.0;
    final detailWidth = size.width - right - listWidth - divider;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: listWidth,
            child: NativeChromePane(
              id: 'trips',
              left: 0,
              width: listWidth,
              child: MediaQuery.removePadding(
                context: context,
                removeRight: true,
                child: _TripList(selected: _selected, onOpen: (id) => setState(() => _selected = id)),
              ),
            ),
          ),
          const VerticalDivider(width: divider, thickness: divider),
          SizedBox(
            width: detailWidth,
            child: NativeChromePane(
              id: 'trip',
              left: listWidth + divider,
              width: detailWidth,
              child: MediaQuery.removePadding(
                context: context,
                removeLeft: true,
                removeRight: true,
                child: TripDetail(
                  key: ValueKey(_selected),
                  trip: trips.firstWhere((t) => t.id == _selected),
                  embedded: true,
                ),
              ),
            ),
          ),
          SizedBox(width: right),
        ],
      ),
    );
  }
}

class _TripList extends StatelessWidget {
  const _TripList({this.selected, required this.onOpen});

  final String? selected;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final upcoming = trips.where((t) => !t.past).toList();
    final past = trips.where((t) => t.past).toList();
    return Scaffold(
      body: NativeNavigationBar(
        title: NativeBarTitle(
          title: 'Trips',
          subtitle: '${upcoming.length} upcoming',
          alignment: NativeBarTitleAlignment.leading,
        ),
        trailing: [
          NativeBarButton(
            icon: const NativeIcon.icon(AppIcons.plus),
            title: 'New trip',
            menu: [
              NativeMenuItem(
                title: 'New trip',
                icon: const NativeIcon.icon(AppIcons.suitcaseRolling),
                onSelected: () {},
              ),
              NativeMenuItem(
                title: 'Import a booking',
                subtitle: 'From a confirmation email',
                icon: const NativeIcon.icon(AppIcons.ticket),
                onSelected: () {},
              ),
            ],
          ),
        ],
        child: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            return ListView(
              padding: EdgeInsets.fromLTRB(16 + padding.left, padding.top + 8, 16 + padding.right, padding.bottom + 24),
              children: [
                for (final trip in upcoming)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _TripCard(trip: trip, selected: trip.id == selected, onTap: () => onOpen(trip.id)),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Past trips',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final trip in past)
                  _PastTrip(trip: trip, selected: trip.id == selected, onTap: () => onOpen(trip.id)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.selected, required this.onTap});

  final Trip trip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 200,
        padding: EdgeInsets.all(selected ? 3 : 0),
        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(28)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(selected ? 25 : 28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(trip.cover, fit: BoxFit.cover, cacheWidth: 900),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: GlassBackground(
                  cornerRadius: 20,
                  tint: photoGlassTint(context),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                '${trip.dates} · ${trip.stops.join(' → ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        Travelers(names: trip.travelers),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PastTrip extends StatelessWidget {
  const _PastTrip({required this.trip, required this.selected, required this.onTap});

  final Trip trip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(trip.cover, width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 192),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    Text(trip.dates, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlapping initials of the people on a trip.
class Travelers extends StatelessWidget {
  const Travelers({super.key, required this.names, this.size = 30});

  final List<String> names;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + (names.length - 1) * size * 0.62,
      height: size,
      child: Stack(
        children: [
          for (final (i, name) in names.indexed)
            Positioned(
              left: i * size * 0.62,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: travelerColors[name[0]] ?? accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  name[0],
                  style: TextStyle(color: Colors.white, fontSize: size * 0.45, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A trip's plan, day by day.
class TripDetail extends StatelessWidget {
  const TripDetail({super.key, required this.trip, this.embedded = false});

  final Trip trip;

  /// In the split layout's detail pane: no back button.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NativeNavigationBar(
        leading: embedded
            ? null
            : NativeBarButton(
                icon: const NativeIcon.icon(AppIcons.caretLeft),
                title: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: NativeBarTitle(title: trip.name, subtitle: trip.dates),
        trailing: [
          NativeBarButton(
            icon: const NativeIcon.icon(AppIcons.users),
            title: 'Invite',
            onPressed: () => notify(
              context,
              title: trip.name,
              subtitle: 'Invite link copied',
              body: 'Anyone with the link can see the plan and add ideas.',
              glyph: AppIcons.users,
            ),
          ),
          NativeBarButton(
            icon: const NativeIcon.icon(AppIcons.dotsThree),
            title: 'More',
            menu: [
              NativeMenuItem(
                title: 'Edit dates',
                icon: const NativeIcon.icon(AppIcons.calendarBlank),
                onSelected: () {},
              ),
              NativeMenuItem(title: 'Show map', icon: const NativeIcon.icon(AppIcons.mapTrifold), onSelected: () {}),
              NativeMenuItem(
                title: 'Delete trip',
                icon: const NativeIcon.icon(AppIcons.trash),
                destructive: true,
                onSelected: () {},
              ),
            ],
          ),
        ],
        child: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            final width = MediaQuery.sizeOf(context).width;
            final scheme = Theme.of(context).colorScheme;
            return ListView(
              padding: EdgeInsets.fromLTRB(16 + padding.left, padding.top + 8, 16 + padding.right, padding.bottom + 24),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: AspectRatio(
                    aspectRatio: embedded || width > 700 ? 16 / 9 : 4 / 3,
                    child: Image.asset(trip.cover, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(AppIcons.mapPinFill, size: 18, color: accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        trip.stops.join(' → '),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Travelers(names: trip.travelers),
                  ],
                ),
                const SizedBox(height: 8),
                for (final day in trip.days) ...[
                  const SizedBox(height: 18),
                  Text(
                    '${day.title} · ${day.place}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  for (final (i, (time, what)) in day.items.indexed)
                    _Stop(time: time, what: what, last: i == day.items.length - 1),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.time, required this.what, required this.last});

  final String time;
  final String what;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(time, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
            ),
          ),
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                if (!last) Expanded(child: Container(width: 2, color: accent.withValues(alpha: 0.3))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(what, style: const TextStyle(fontSize: 17)),
            ),
          ),
        ],
      ),
    );
  }
}
