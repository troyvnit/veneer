import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

/// A Slack-style channel: a native navigation bar (back button, channel
/// capsule, grouped trailing buttons) over Flutter-drawn messages that fade
/// into iOS 26's scroll edge effect, and a native composer above the tab bar.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<_Message> _messages = List.of(_seed);
  final NativeComposerController _composer = NativeComposerController();

  void _send(String text) {
    final now = TimeOfDay.now();
    setState(
      () => _messages.add(
        _Message(author: 'Troy', color: const Color(0xFFE8912D), time: now.format(context), body: text.trim()),
      ),
    );
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 1)));

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NativeComposer(
        controller: _composer,
        placeholder: 'Message launch-crew',
        leading: NativeComposerButton(
          icon: const NativeIcon.symbol('plus'),
          title: 'Attach',
          onPressed: () => _toast('Attach'),
        ),
        idleAction: NativeComposerButton(
          icon: const NativeIcon.symbol('mic'),
          title: 'Record voice clip',
          onPressed: () => _toast('Voice clip'),
        ),
        toolbar: [
          NativeComposerButton(
            icon: const NativeIcon.symbol('textformat'),
            title: 'Formatting',
            onPressed: () => _toast('Formatting'),
          ),
          NativeComposerButton(
            icon: const NativeIcon.symbol('face.smiling'),
            title: 'Emoji',
            onPressed: () => _toast('Emoji'),
          ),
          NativeComposerButton(
            icon: const NativeIcon.symbol('at'),
            title: 'Mention',
            onPressed: () => _toast('Mention'),
          ),
          NativeComposerButton(
            icon: const NativeIcon.svgAsset('assets/icons/slash_command.svg'),
            title: 'Shortcuts',
            onPressed: () => _toast('Shortcuts'),
          ),
        ],
        sendIcon: const NativeIcon.symbol('paperplane.fill'),
        tintColor: const Color(0xFF2BAC76),
        onSend: _send,
        child: Builder(
          builder: (context) {
            // Padding already includes the nav bar (top) and composer + keyboard/tab bar (bottom).
            final padding = MediaQuery.paddingOf(context);
            return Stack(
              children: [
                NotificationListener<ScrollStartNotification>(
                  // Like Slack: dragging the conversation puts the keyboard away.
                  onNotification: (n) {
                    if (n.dragDetails != null) _composer.unfocus();
                    return false;
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _composer.unfocus,
                    child: ListView.builder(
                      reverse: true,
                      padding: EdgeInsets.only(top: padding.top + 8, bottom: padding.bottom + 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) => _MessageTile(_messages[_messages.length - 1 - i]),
                    ),
                  ),
                ),
                NativeNavigationBar(
                  leading: NativeBarButton(
                    icon: const NativeIcon.symbol('chevron.left'),
                    title: 'Back',
                    onPressed: () => _toast('Back'),
                  ),
                  title: NativeBarTitle(
                    title: 'launch-crew',
                    subtitle: '6 members • 3 tabs',
                    icon: const NativeIcon.symbol('lock.fill'),
                    capsule: true,
                    onPressed: () => _toast('Channel details'),
                  ),
                  trailing: [
                    NativeBarButton(
                      icon: const NativeIcon.svgAsset('assets/icons/app_mark.svg', tinted: false),
                      title: 'Apps',
                      onPressed: () => _toast('Apps'),
                    ),
                    NativeBarButton(
                      icon: const NativeIcon.symbol('headphones'),
                      title: 'Huddle',
                      onPressed: () => _toast('Huddle'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// MARK: - Messages

class _Message {
  const _Message({
    required this.author,
    required this.color,
    required this.time,
    required this.body,
    this.reactions = const {},
    this.replies = 0,
    this.card = false,
  });

  final String author;
  final Color color;
  final String time;
  final String body;
  final Map<String, int> reactions;
  final int replies;
  final bool card;
}

const _seed = [
  _Message(
    author: 'Tasks',
    color: Color(0xFF6E56CF),
    time: '9:05 AM',
    body: 'Add offline mode to the trail map',
    card: true,
    reactions: {'👀': 2},
  ),
  _Message(
    author: 'Troy',
    color: Color(0xFFE8912D),
    time: '10:12 AM',
    body: 'Beta build 42 is on TestFlight @Mia @Alex',
    reactions: {'🎉': 3},
    replies: 12,
  ),
  _Message(
    author: 'Mia',
    color: Color(0xFF2EB67D),
    time: '10:20 AM',
    body: 'Downloading now — running through onboarding first.',
  ),
  _Message(
    author: 'Alex',
    color: Color(0xFF36C5F0),
    time: '10:34 AM',
    body: 'Found a typo on the paywall screen @Mia @Troy',
    reactions: {'🙏': 2, '🚀': 1},
    replies: 3,
  ),
  _Message(
    author: 'Troy',
    color: Color(0xFFE8912D),
    time: '10:41 AM',
    body: 'Nice catch, fixing it in the next build.',
  ),
];

class _MessageTile extends StatelessWidget {
  const _MessageTile(this.m);

  final _Message m;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(m.author, m.color, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(m.author, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text(m.time, style: TextStyle(fontSize: 13, color: secondary)),
                  ],
                ),
                const SizedBox(height: 2),
                if (m.card) _IssueCard(title: m.body) else _Body(m.body),
                if (m.reactions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in m.reactions.entries) _ReactionPill(emoji: e.key, count: e.value),
                      _AddReaction(color: secondary),
                    ],
                  ),
                ],
                if (m.replies > 0) ...[const SizedBox(height: 8), _ThreadRow(m.replies)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Body text with Slack-style mention chips.
class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    const mention = Color(0xFF1D9BD1);
    final spans = <InlineSpan>[];
    for (final word in text.split(' ')) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' '));
      spans.add(
        word.startsWith('@')
            ? TextSpan(
                text: word,
                style: TextStyle(color: mention, backgroundColor: mention.withValues(alpha: 0.16)),
              )
            : TextSpan(text: word),
      );
    }
    return Text.rich(TextSpan(children: spans), style: const TextStyle(fontSize: 17, height: 1.3));
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.name, this.color, {required this.size});

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.22)),
    child: Text(
      name[0],
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.45),
    ),
  );
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({required this.emoji, required this.count});

  final String emoji;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text('$count', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AddReaction extends StatelessWidget {
  const _AddReaction({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 30,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Icon(Icons.add_reaction_outlined, size: 18, color: color),
  );
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow(this.replies);

  final int replies;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Row(
      children: [
        for (final (name, color) in const [
          ('T', Color(0xFFE8912D)),
          ('M', Color(0xFF2EB67D)),
          ('A', Color(0xFF36C5F0)),
        ]) ...[_Avatar(name, color, size: 24), const SizedBox(width: 4)],
        const SizedBox(width: 4),
        Text(
          '$replies replies',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1D9BD1)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Yesterday at 6:10 PM',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: secondary),
          ),
        ),
      ],
    );
  }
}

/// An app-message block, like an issue tracker notification.
class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.onSurface.withValues(alpha: 0.2), width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            '1. Cache map tiles for every saved route.\n'
            '2. Show a banner while the app is offline.\n'
            '3. Queue edits made offline and sync them when the connection returns.\n'
            '4. Keep GPS tracking working without a network.',
            style: TextStyle(fontSize: 16, height: 1.35),
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'State  ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: 'In Progress     ',
                  style: TextStyle(color: secondary),
                ),
                const TextSpan(
                  text: 'Assignee  ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: 'Mia Chen',
                  style: TextStyle(color: secondary),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 10),
          for (final label in const ['Subscribe', 'In Progress', 'More Options'])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.25)),
                    foregroundColor: scheme.onSurface,
                  ),
                  onPressed: () {},
                  child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
