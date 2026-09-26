import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:veneer/veneer.dart';

import '../app_icons.dart';

/// Opens the assistant from the tab bar's AI button in a sheet: on iOS 26 a
/// real UIKit sheet running the `assistantSheet` entrypoint (see main.dart),
/// elsewhere the same page in the Flutter sheet. It rests at medium or large
/// and drags down to close.
void openAssistant(BuildContext context) {
  showNativeSheet<void>(
    context: context,
    entrypoint: 'assistantSheet',
    detents: const [NativeSheetDetent.medium, NativeSheetDetent.large],
    initialDetent: NativeSheetDetent.large,
    builder: (context) => const AssistantPage(),
  );
}

/// An assistant chat in a sheet: a native navigation bar and prompt composer
/// over a Flutter conversation — "+" menu for attachments, dictation, and a
/// voice button that becomes send as you type. Voice mode splits mute and
/// end buttons off the composer's glass and shows a live orb.
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

enum _Role { user, assistant }

class _Turn {
  _Turn(this.role, this.text, {this.attachments = const []});

  final _Role role;
  String text;
  final List<NativeComposerAttachment> attachments;
}

class _AssistantPageState extends State<AssistantPage> {
  final NativeComposerController _composer = NativeComposerController();
  final List<_Turn> _turns = [];
  final List<NativeComposerAttachment> _attachments = [];
  bool _voice = false;
  bool _muted = false;
  String _voiceName = 'Harbor';
  Timer? _stream;
  int _replyIndex = 0;
  int _attachmentSerial = 0;

  static const _voices = ['Harbor', 'Aurora', 'Sage'];

  static const _replies = [
    'Here’s a simple plan: cache the map tiles for saved routes first, then queue edits made offline and sync '
        'them when the connection returns. Want me to split that into tasks?',
    'Good question. The short version: keep the state in one place, pass it down, and let widgets rebuild '
        'from it. I can sketch the structure if that helps.',
    'That photo has lovely evening light. For a caption, something like “Last light over the ridge” would '
        'fit — or I can suggest a few more.',
    'Sure — three ideas for the weekend: a sunrise hike to the lookout, a picnic by the lake, or a slow '
        'morning at the farmers market followed by a bike ride along the coast.',
  ];

  @override
  void dispose() {
    _stream?.cancel();
    _composer.dispose();
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 1)));

  void _attach({required String title, String? subtitle, required NativeIcon thumbnail, bool photo = false}) {
    final id = 'a${_attachmentSerial++}';
    setState(
      () => _attachments.add(
        NativeComposerAttachment(
          id: id,
          title: photo ? null : title,
          subtitle: subtitle,
          thumbnail: thumbnail,
          onRemove: () => setState(() => _attachments.removeWhere((a) => a.id == id)),
        ),
      ),
    );
  }

  void _send(String text) {
    final prompt = text.trim();
    if (prompt.isEmpty && _attachments.isEmpty) return;
    final hasPhoto = _attachments.any((a) => a.title == null);
    setState(() {
      _turns.add(_Turn(_Role.user, prompt, attachments: List.of(_attachments)));
      _attachments.clear();
    });
    _reply(_replyFor(prompt.toLowerCase(), hasPhoto: hasPhoto));
  }

  /// A canned reply on the prompt's topic, or the next one in turn.
  String _replyFor(String prompt, {required bool hasPhoto}) {
    if (hasPhoto || prompt.contains('photo') || prompt.contains('caption')) return _replies[2];
    if (prompt.contains('weekend') || prompt.contains('trip')) return _replies[3];
    if (prompt.contains('offline') || prompt.contains('sync') || prompt.contains('plan')) return _replies[0];
    return _replies[_replyIndex++ % _replies.length];
  }

  /// Streams a canned reply word by word, like a model would.
  void _reply(String reply) {
    _stream?.cancel();
    final words = reply.split(' ');
    final turn = _Turn(_Role.assistant, '');
    var i = 0;
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _turns.add(turn));
      _stream = Timer.periodic(const Duration(milliseconds: 45), (timer) {
        if (!mounted || i >= words.length) return timer.cancel();
        setState(() => turn.text = i == 0 ? words[i++] : '${turn.text} ${words[i++]}');
      });
    });
  }

  void _newChat() {
    _stream?.cancel();
    setState(() {
      _turns.clear();
      _attachments.clear();
    });
    _composer.clear();
  }

  List<NativeMenuItem> get _moreMenu => [
    NativeMenuItem(title: 'Share', icon: const NativeIcon.icon(AppIcons.share), onSelected: () => _toast('Share')),
    NativeMenuItem(
      title: 'Rename',
      icon: const NativeIcon.icon(AppIcons.pencilSimple),
      onSelected: () => _toast('Rename'),
    ),
    NativeMenuItem(
      title: 'Delete',
      icon: const NativeIcon.icon(AppIcons.trash),
      destructive: true,
      onSelected: _newChat,
    ),
  ];

  List<NativeMenuItem> get _voiceMenu => [
    for (final name in _voices)
      NativeMenuItem(
        title: name,
        icon: name == _voiceName ? const NativeIcon.icon(AppIcons.check) : null,
        onSelected: () => setState(() => _voiceName = name),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The sheet's own material shows through.
      backgroundColor: Colors.transparent,
      // NativePromptComposer handles the keyboard itself.
      resizeToAvoidBottomInset: false,
      body: NativeNavigationBar(
        leading: NativeBarButton(
          icon: const NativeIcon.icon(AppIcons.close),
          title: 'Close',
          onPressed: () => NativeSheet.close(context),
        ),
        // Two buttons share one glass group; voice mode swaps them for one.
        trailing: _voice
            ? [
                NativeBarButton(
                  icon: const NativeIcon.icon(AppIcons.slidersHorizontal),
                  title: 'Voice',
                  menu: _voiceMenu,
                ),
              ]
            : [
                NativeBarButton(
                  icon: const NativeIcon.icon(AppIcons.notePencil),
                  title: 'New chat',
                  onPressed: _newChat,
                ),
                NativeBarButton(icon: const NativeIcon.icon(AppIcons.dotsThree), title: 'More', menu: _moreMenu),
              ],
        child: NativePromptComposer(
          controller: _composer,
          placeholder: 'Ask anything',
          leading: NativeComposerButton(
            icon: const NativeIcon.icon(AppIcons.plus),
            title: 'Add',
            menu: [
              NativeMenuItem(
                title: 'Photos',
                icon: const NativeIcon.icon(AppIcons.images),
                onSelected: () => _attach(
                  title: 'lake.jpg',
                  thumbnail: const NativeIcon.image('assets/images/lake.jpg'),
                  photo: true,
                ),
              ),
              NativeMenuItem(
                title: 'Camera',
                icon: const NativeIcon.icon(AppIcons.camera),
                onSelected: () => _attach(
                  title: 'coast.jpg',
                  thumbnail: const NativeIcon.image('assets/images/coast.jpg'),
                  photo: true,
                ),
              ),
              NativeMenuItem(
                title: 'Files',
                icon: const NativeIcon.icon(AppIcons.fileText),
                onSelected: () => _attach(
                  title: 'trip-plan.pdf',
                  subtitle: 'PDF · 2 pages',
                  thumbnail: const NativeIcon.icon(AppIcons.fileTextFill),
                ),
              ),
            ],
          ),
          actions: [
            NativeComposerButton(
              icon: const NativeIcon.icon(AppIcons.microphone),
              title: 'Dictate',
              onPressed: () => _toast('Dictation'),
            ),
          ],
          primaryAction: NativeComposerButton(
            icon: const NativeIcon.icon(AppIcons.waveform),
            title: 'Voice mode',
            onPressed: () => setState(() {
              _voice = true;
              _muted = false;
            }),
          ),
          sideActions: [
            NativeComposerButton(
              icon: NativeIcon.icon(_muted ? AppIcons.microphone : AppIcons.microphoneSlash),
              title: _muted ? 'Unmute' : 'Mute',
              onPressed: () => setState(() => _muted = !_muted),
            ),
            NativeComposerButton(
              icon: const NativeIcon.icon(AppIcons.close),
              title: 'End voice mode',
              prominent: true,
              onPressed: () => setState(() => _voice = false),
            ),
          ],
          showSideActions: _voice,
          attachments: List.of(_attachments),
          tintColor: const Color(0xFF0A84FF),
          onSend: _send,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _composer.unfocus,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(animation), child: child),
              ),
              child: _voice
                  ? _VoiceView(key: const ValueKey('voice'), muted: _muted)
                  : _turns.isEmpty
                  ? const _Greeting(key: ValueKey('empty'))
                  : _Conversation(key: const ValueKey('chat'), turns: _turns),
            ),
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: Center(
        child: Text(
          'What can I help with?',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}

// MARK: - Conversation

class _Conversation extends StatelessWidget {
  const _Conversation({super.key, required this.turns});

  final List<_Turn> turns;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return ListView.builder(
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(top: padding.top + 12, bottom: padding.bottom + 12),
      itemCount: turns.length,
      itemBuilder: (context, i) {
        final index = turns.length - 1 - i;
        final turn = turns[index];
        return turn.role == _Role.user
            ? _UserBubble(turn)
            : _AssistantText(turn, showActions: index == turns.length - 1);
      },
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.turn);

  final _Turn turn;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (turn.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [for (final a in turn.attachments) _SentAttachment(a)],
              ),
            ),
          if (turn.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF0A3D70) : const Color(0xFFDCEBFF),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                turn.text,
                style: TextStyle(fontSize: 17, height: 1.3, color: dark ? Colors.white : Colors.black),
              ),
            ),
        ],
      ),
    );
  }
}

class _SentAttachment extends StatelessWidget {
  const _SentAttachment(this.a);

  final NativeComposerAttachment a;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (a.title == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: NativeIconView(a.thumbnail!, size: 120, fit: BoxFit.cover),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NativeIconView(a.thumbnail!, size: 26, color: const Color(0xFFFF5B5B)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.title!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              if (a.subtitle != null)
                Text(a.subtitle!, style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.55))),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssistantText extends StatelessWidget {
  const _AssistantText(this.turn, {required this.showActions});

  final _Turn turn;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(turn.text, style: const TextStyle(fontSize: 17, height: 1.4)),
          if (showActions && turn.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final icon in const [AppIcons.copy, AppIcons.thumbsUp, AppIcons.thumbsDown, AppIcons.speakerHigh])
                  Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Icon(icon, size: 18, color: secondary),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// MARK: - Voice

/// The voice session: an orb, centred in the space the bars and composer
/// leave, so it glides up with the keyboard.
class _VoiceView extends StatelessWidget {
  const _VoiceView({super.key, required this.muted});

  final bool muted;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: Center(child: _Orb(muted: muted)),
    );
  }
}

class _Orb extends StatefulWidget {
  const _Orb({required this.muted});

  final bool muted;

  @override
  State<_Orb> createState() => _OrbState();
}

class _OrbState extends State<_Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 12))
    ..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: widget.muted ? 0.55 : 1,
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final t = _clock.value * 2 * math.pi;
          // Breathes while listening; still when muted.
          final scale = widget.muted ? 0.94 : 1 + 0.035 * math.sin(t * 6);
          return Transform.scale(
            scale: scale,
            child: CustomPaint(size: const Size.square(210), painter: _OrbPainter(t)),
          );
        },
      ),
    );
  }
}

/// A sky-blue sphere with drifting clouds.
class _OrbPainter extends CustomPainter {
  _OrbPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = size.center(Offset.zero);
    final circle = Rect.fromCircle(center: center, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    canvas.drawRect(
      circle,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5A63FF), Color(0xFF8A95FF), Color(0xFFEFF1FF), Color(0xFFC3CBFF)],
          stops: [0, 0.38, 0.62, 1],
        ).createShader(circle),
    );
    final cloud = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    for (var i = 0; i < 6; i++) {
      final phase = t + i * 1.7;
      final dx = math.sin(phase) * r * 0.45;
      final dy = r * (0.05 + 0.12 * math.cos(phase * 0.7 + i));
      final w = r * (0.9 + 0.25 * math.sin(phase * 1.3));
      canvas.drawOval(
        Rect.fromCenter(center: center + Offset(dx, dy), width: w, height: w * 0.42),
        cloud..color = Colors.white.withValues(alpha: 0.55 + 0.3 * math.sin(phase * 0.5).abs()),
      );
    }
    canvas.drawCircle(
      center - Offset(0, r * 0.55),
      r * 0.6,
      Paint()
        ..color = const Color(0xFF4F57FF).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}
