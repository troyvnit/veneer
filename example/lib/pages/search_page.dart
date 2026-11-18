import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

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

  static const _channels = [
    ('launch-crew', 'Beta ships this afternoon'),
    ('design', 'New glass tokens are in Figma'),
    ('android', 'Replica sheets match the native sizes'),
    ('ios', 'Tab bar handoff fixed in 0.9.1'),
    ('random', 'Who took the last oat milk?'),
    ('support', 'Two new tickets about dictation'),
    ('releases', 'veneer published to pub.dev'),
    ('photos', 'Lakeside shoot is up'),
    ('marketing', 'Launch post goes out at 9'),
    ('qa', 'Regression run is green'),
    ('infra', 'CI moved to macOS runners'),
    ('docs', 'README screenshots refreshed'),
  ];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = [
      for (final channel in _channels)
        if (_filter.isEmpty ||
            channel.$1.contains(_filter.toLowerCase()) ||
            channel.$2.toLowerCase().contains(_filter.toLowerCase()))
          channel,
    ];
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: NativeSearchToolbar(
        placeholder: 'Search channels',
        controller: _query,
        onChanged: (q) => setState(() => _filter = q),
        onClose: () => Navigator.of(context).pop(),
        child: ListView(
          children: [
            for (final (name, preview) in results)
              CupertinoListTile(leading: const Icon(CupertinoIcons.number), title: Text(name), subtitle: Text(preview)),
          ],
        ),
      ),
    );
  }
}
