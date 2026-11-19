import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../app_icons.dart';
import '../app_state.dart';
import '../data/travel.dart';
import 'place_page.dart';
import 'search_page.dart';

/// The home tab: featured places in a carousel with glass cards over the
/// photos, a glass category bar that stays pinned while the grid scrolls
/// under it, and a grid of places with glass labels and native context menus.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  Mood _mood = Mood.all;
  final ScrollController _scroll = ScrollController();

  /// The carousel's height: shorter on a short screen (the open iPhone Duo).
  static double featuredHeight(BuildContext context) => math.min(440, MediaQuery.sizeOf(context).height * 0.55);
  static const _barHeight = 68.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static const _featured = ['kyoto', 'santorini', 'patagonia', 'maldives'];

  /// The featured places come last, so the grid doesn't open with the
  /// carousel's first card.
  List<Place> get _filtered => [
    for (final featured in [false, true])
      for (final p in places)
        if ((_mood == Mood.all || p.mood == _mood) && _featured.contains(p.id) == featured) p,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NativeNavigationBar(
        title: const NativeBarTitle(
          title: 'Explore',
          subtitle: '12 places · 3 trips planned',
          alignment: NativeBarTitleAlignment.leading,
        ),
        trailing: [
          NativeBarButton(
            icon: const NativeIcon.icon(AppIcons.magnifyingGlass),
            title: 'Search',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage())),
          ),
          NativeBarButton(
            icon: const NativeIcon.icon(AppIcons.userCircle),
            title: 'Profile',
            menu: [
              NativeMenuItem(
                title: 'Flutter replicas',
                subtitle: 'What Android and iOS 15–25 show',
                icon: const NativeIcon.icon(AppIcons.androidLogo),
                checked: flutterReplicas.value,
                onSelected: () => flutterReplicas.value = !flutterReplicas.value,
              ),
              NativeMenuItem(
                title: 'Saved places',
                subtitle: '${savedPlaces.value.length} saved',
                icon: const NativeIcon.icon(AppIcons.heart),
                onSelected: () => setState(() => _mood = Mood.all),
              ),
            ],
          ),
        ],
        child: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            final places = _filtered;
            final scrollView = CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(top: padding.top + 8),
                  sliver: SliverToBoxAdapter(child: _Featured(ids: _featured)),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: _barHeight)),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16 + padding.left, 4, 16 + padding.right, 12),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      _mood == Mood.all ? 'Everywhere' : _mood.label,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16 + padding.left, 0, 16 + padding.right, padding.bottom + 24),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.74,
                    ),
                    itemCount: places.length,
                    itemBuilder: (context, i) => PlaceTile(place: places[i]),
                  ),
                ),
              ],
            );
            // The category bar rides under the carousel, then stays pinned
            // below the navigation bar while the grid scrolls under its glass.
            return Stack(
              children: [
                scrollView,
                AnimatedBuilder(
                  animation: _scroll,
                  builder: (context, _) {
                    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                    return Positioned(
                      top: math.max(padding.top, padding.top + 8 + featuredHeight(context) - offset),
                      left: 0,
                      right: 0,
                      height: _barHeight,
                      child: Center(
                        // Above the grid's glass labels scrolling under it.
                        child: GlassGroup(
                          zIndex: 2,
                          child: GlassSegmentBar(
                            segments: [for (final mood in Mood.values) GlassSegment(icon: NativeIcon.icon(mood.icon))],
                            selectedIndex: _mood.index,
                            onSelected: (i) => setState(() => _mood = Mood.values[i]),
                            segmentWidth: 48,
                            selectedForeground: accent,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

void openPlace(BuildContext context, Place place) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlacePage(place: place)));

// MARK: - Featured carousel

class _Featured extends StatelessWidget {
  const _Featured({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final padding = MediaQuery.paddingOf(context);
    final available = width - padding.left - padding.right;
    final cardWidth = available > 700 ? 420.0 : available - 40;
    return SizedBox(
      height: _ExplorePageState.featuredHeight(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(16 + padding.left, 0, 16 + padding.right, 0),
        itemCount: ids.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: cardWidth,
          child: _FeaturedCard(place: placeById(ids[i])),
        ),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openPlace(context, place),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(place.image, fit: BoxFit.cover),
            Positioned(top: 14, right: 14, child: SaveButton(place: place)),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: GlassBackground(
                cornerRadius: 22,
                tint: photoGlassTint(context),
                onTap: () => openPlace(context, place),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FEATURED · ${place.mood.label.toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        place.name,
                        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(place.country, style: const TextStyle(color: Colors.white, fontSize: 15)),
                          const Spacer(),
                          const Icon(AppIcons.starFill, size: 15, color: Color(0xFFFFD60A)),
                          const SizedBox(width: 4),
                          Text(
                            '${place.rating}',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          Text(' (${place.reviews})', style: const TextStyle(color: Colors.white70, fontSize: 15)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round glass heart that saves the place.
class SaveButton extends StatelessWidget {
  const SaveButton({super.key, required this.place, this.size = 44});

  final Place place;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: savedPlaces,
      builder: (context, saved, _) {
        final on = saved.contains(place.id);
        return GlassShape(
          width: size,
          height: size,
          icon: NativeIcon.icon(on ? AppIcons.heartFill : AppIcons.heart),
          foreground: on ? accent : Colors.white,
          tint: photoGlassTint(context),
          onTap: () => toggleSaved(place.id),
        );
      },
    );
  }
}

// MARK: - Grid

/// A place's photo with its name on glass; long-press for a native context
/// menu.
class PlaceTile extends StatelessWidget {
  const PlaceTile({super.key, required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return NativeContextMenu(
      borderRadius: BorderRadius.circular(24),
      items: [
        NativeMenuItem(
          title: savedPlaces.value.contains(place.id) ? 'Remove from saved' : 'Save',
          icon: const NativeIcon.icon(AppIcons.heart),
          onSelected: () => toggleSaved(place.id),
        ),
        NativeMenuItem(
          title: 'Add to Japan in spring',
          icon: const NativeIcon.icon(AppIcons.suitcaseRolling),
          onSelected: () => notify(
            context,
            title: 'Japan in spring',
            subtitle: 'Trip updated',
            body: '${place.name} was added to your trip.',
            glyph: AppIcons.suitcaseRollingFill,
          ),
        ),
        NativeMenuItem(title: 'Share', icon: const NativeIcon.icon(AppIcons.share), onSelected: () {}),
        NativeMenuItem(
          title: 'Not interested',
          icon: const NativeIcon.icon(AppIcons.eyeSlash),
          destructive: true,
          onSelected: () {},
        ),
      ],
      child: GestureDetector(
        onTap: () => openPlace(context, place),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(place.image, fit: BoxFit.cover, cacheWidth: 600),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: GlassShape(
                  height: 40,
                  icon: const NativeIcon.icon(AppIcons.mapPinFill),
                  iconSize: 16,
                  label: place.name,
                  foreground: Colors.white,
                  tint: photoGlassTint(context),
                  onTap: () => openPlace(context, place),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
