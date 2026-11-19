import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../app_icons.dart';
import '../data/travel.dart';
import 'explore_page.dart';

/// [NativeSearchToolbar]: the system search bar at the bottom of the screen,
/// riding the keyboard, over Flutter results.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _query = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _filter.trim().toLowerCase();
    final results = [
      for (final p in places)
        if (q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            p.country.toLowerCase().contains(q) ||
            p.mood.label.toLowerCase().contains(q))
          p,
    ];
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: NativeSearchToolbar(
        placeholder: 'Places, countries, beaches…',
        controller: _query,
        onChanged: (q) => setState(() => _filter = q),
        onClose: () => Navigator.of(context).pop(),
        child: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            return ListView(
              padding: EdgeInsets.fromLTRB(
                16 + padding.left,
                padding.top + 16,
                16 + padding.right,
                padding.bottom + 16,
              ),
              children: [
                Text(
                  q.isEmpty ? 'Popular right now' : '${results.length} results',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final place in results)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => openPlace(context, place),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.asset(place.image, width: 60, height: 60, fit: BoxFit.cover, cacheWidth: 180),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(place.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                                Text(
                                  '${place.country} · ${place.mood.label}',
                                  style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const Icon(AppIcons.starFill, size: 14, color: Color(0xFFFFB800)),
                          const SizedBox(width: 4),
                          Text('${place.rating}', style: const TextStyle(fontWeight: FontWeight.w600)),
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
