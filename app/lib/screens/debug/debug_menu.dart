// The developer-only entry point into the debug screens. Dropped into a
// Scaffold's `drawer:` slot, which gets Flutter's edge-swipe-to-open gesture
// for free -- swiping right from the left edge reveals this menu, no gesture
// handling of our own needed.

import 'package:flutter/material.dart';

import '../../data/practice_history_scope.dart';
import '../../pronunciation/pronunciation_scope.dart';
import '../../tts/phonon_tts_scope.dart';
import 'pronunciation_debug_screen.dart';
import 'tts_debug_screen.dart';
import 'tts_reference_screen.dart';
import 'word_map_debug_screen.dart';

class DebugMenu extends StatelessWidget {
  const DebugMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final tts = PhononTtsScope.of(context);
    final detector = PronunciationScope.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'Debug Menu',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            _DebugMenuTile(
              icon: Icons.record_voice_over_outlined,
              title: 'TTS',
              subtitle: 'Text and phonemes to speech',
              onTap: () => _push(context, TtsDebugScreen(tts: tts)),
            ),
            _DebugMenuTile(
              icon: Icons.mic_none_outlined,
              title: 'Pronunciation',
              subtitle: 'Score a sample recording',
              onTap: () =>
                  _push(context, PronunciationDebugScreen(detector: detector)),
            ),
            _DebugMenuTile(
              icon: Icons.hearing_outlined,
              title: 'TTS Reference',
              subtitle: 'Vosk vs the TTS audio',
              onTap: () => _push(
                context,
                TtsReferenceScreen(detector: detector, tts: tts),
              ),
            ),
            _DebugMenuTile(
              icon: Icons.map_outlined,
              title: 'Word Map',
              subtitle: "Vosk's raw word timing",
              onTap: () => _push(
                context,
                WordMapDebugScreen(detector: detector, tts: tts),
              ),
            ),
            const Divider(height: 1),
            _DebugMenuTile(
              icon: Icons.delete_outline,
              title: 'Clear Data',
              subtitle: 'Delete all saved practice history',
              onTap: () => _confirmClearData(context),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _confirmClearData(BuildContext context) async {
    final history = PracticeHistoryScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all saved practice data?'),
        content: const Text(
          'Every recorded attempt, mispronounced word, and score is '
          'permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await history.clearAll();
    if (!context.mounted) return;
    Navigator.of(context).pop(); // Close the drawer.
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Practice data cleared.')));
  }
}

class _DebugMenuTile extends StatelessWidget {
  const _DebugMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
