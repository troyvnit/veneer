import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../app_icons.dart';
import '../data/travel.dart';
import 'trips_page.dart';

/// The trip journal: a native navigation bar with a capsule title, and a
/// native composer above the tab bar that grows a toolbar while you type,
/// rides the keyboard and records voice notes. The entries are Flutter.
class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _Entry {
  const _Entry({
    required this.author,
    required this.time,
    required this.place,
    this.text = '',
    this.photos = const [],
    this.likes = const [],
    this.voice,
  });

  final String author;
  final String time;
  final String place;
  final String text;
  final List<String> photos;
  final List<String> likes;
  final Duration? voice;
}

class _JournalPageState extends State<JournalPage> {
  final NativeComposerController _composer = NativeComposerController();
  final List<_Entry> _entries = List.of(_seed);

  static const _seed = [
    _Entry(
      author: 'Maya',
      time: '06:40',
      place: 'Kinkaku-ji',
      text: 'First in line at the Golden Pavilion. Not a ripple on the pond.',
      photos: ['assets/images/kyoto_2.jpg'],
      likes: ['Leo', 'Sam'],
    ),
    _Entry(
      author: 'Leo',
      time: '12:15',
      place: 'Nishiki Market',
      text: 'Tamagoyaki on a stick, grilled eel, and a matcha soft serve for dessert. Lunch sorted.',
      likes: ['Maya'],
    ),
    _Entry(
      author: 'Sam',
      time: '17:50',
      place: 'Kiyomizu-dera',
      text: 'Golden hour from the terrace. The blossoms are at their peak this week.',
      photos: ['assets/images/kyoto.jpg'],
      likes: ['Maya', 'Leo'],
    ),
  ];

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  String get _now => TimeOfDay.now().format(context);

  void _add(_Entry entry) => setState(() => _entries.add(entry));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: NativeNavigationBar(
        title: const NativeBarTitle(
          title: 'Japan in spring',
          subtitle: 'Day 6 · Kyoto',
          icon: NativeIcon.image('assets/images/kyoto.jpg'),
          capsule: true,
        ),
        trailing: [
          NativeBarButton(icon: const NativeIcon.icon(AppIcons.mapTrifold), title: 'Map', onPressed: () {}),
          NativeBarButton(icon: const NativeIcon.icon(AppIcons.users), title: 'Travelers', onPressed: () {}),
        ],
        child: NativeComposer(
          controller: _composer,
          placeholder: 'Write about today…',
          leading: NativeComposerButton(
            icon: const NativeIcon.icon(AppIcons.plus),
            title: 'Add',
            menu: [
              NativeMenuItem(
                title: 'Photo',
                icon: const NativeIcon.icon(AppIcons.imagesSquare),
                onSelected: () =>
                    _add(_Entry(author: 'You', time: _now, place: 'Gion', photos: const ['assets/images/kyoto.jpg'])),
              ),
              NativeMenuItem(
                title: 'Check in',
                subtitle: 'Gion, Kyoto',
                icon: const NativeIcon.icon(AppIcons.mapPin),
                onSelected: () => _add(_Entry(author: 'You', time: _now, place: 'Gion', text: 'Checked in.')),
              ),
            ],
          ),
          idleAction: NativeComposerButton(
            icon: const NativeIcon.icon(AppIcons.microphone),
            title: 'Voice note',
            onPressed: () => _composer.startVoiceRecording(maxDuration: const Duration(minutes: 1)),
          ),
          onVoiceRecorded: (recording) =>
              _add(_Entry(author: 'You', time: _now, place: 'Gion', voice: recording.duration)),
          toolbar: const [
            NativeComposerButton(icon: NativeIcon.icon(AppIcons.textAa), title: 'Format'),
            NativeComposerButton(icon: NativeIcon.icon(AppIcons.smiley), title: 'Emoji'),
            NativeComposerButton(icon: NativeIcon.icon(AppIcons.mapPin), title: 'Place'),
            NativeComposerButton(icon: NativeIcon.icon(AppIcons.at), title: 'Mention'),
          ],
          highlights: const ['@Maya', '@Leo', '@Sam'],
          sendIcon: const NativeIcon.icon(AppIcons.paperPlaneTiltFill),
          tintColor: accent,
          onSend: (text) => _add(_Entry(author: 'You', time: _now, place: 'Gion', text: text.trim())),
          child: Builder(
            builder: (context) {
              final padding = MediaQuery.paddingOf(context);
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _composer.unfocus,
                child: ListView.builder(
                  reverse: true,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    16 + padding.left,
                    padding.top + 8,
                    16 + padding.right,
                    padding.bottom + 8,
                  ),
                  itemCount: _entries.length,
                  itemBuilder: (context, i) => _EntryCard(_entries[_entries.length - 1 - i]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard(this.entry);

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = TextStyle(fontSize: 14, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Travelers(names: [entry.author], size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(entry.author, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Icon(AppIcons.mapPinFill, size: 13, color: accent),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(entry.place, overflow: TextOverflow.ellipsis, style: secondary),
                    ),
                    const Spacer(),
                    Text(entry.time, style: secondary),
                  ],
                ),
                if (entry.text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(entry.text, style: const TextStyle(fontSize: 17, height: 1.35)),
                ],
                if (entry.voice case final voice?) ...[const SizedBox(height: 8), _VoiceNote(duration: voice)],
                if (entry.photos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: entry.photos.length == 1 ? 230 : 170,
                    child: Row(
                      children: [
                        for (final (i, photo) in entry.photos.indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.asset(photo, fit: BoxFit.cover, height: double.infinity, cacheWidth: 700),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (entry.likes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(AppIcons.heartFill, size: 15, color: accent),
                      const SizedBox(width: 4),
                      Text(entry.likes.join(', '), style: secondary),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceNote extends StatelessWidget {
  const _VoiceNote({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final seconds = duration.inSeconds;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.playFill, size: 18, color: accent),
          const SizedBox(width: 8),
          for (var i = 0; i < 18; i++)
            Container(
              width: 3,
              height: 6.0 + (i * 7 % 13),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
            ),
          const SizedBox(width: 8),
          Text('0:${seconds.toString().padLeft(2, '0')}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
