import 'package:flutter/material.dart';

import '../tts/phrase_player.dart';

/// Plays [text] slowed down, pitch unchanged, through the screen's
/// [PhrasePlayer] -- the whole phrase, or with [bySyllable] one syllable at a
/// time with a pause between each (Word Rematch). The same circular shape as
/// [HearButton], which it sits beside.
class SlowHearButton extends StatelessWidget {
  const SlowHearButton({
    super.key,
    required this.text,
    required this.player,
    this.bySyllable = false,
  });

  final String text;
  final PhrasePlayer player;
  final bool bySyllable;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final preparing = bySyllable
            ? player.isPreparingSyllables
            : player.isPreparingSlow;
        final playing = bySyllable
            ? player.isPlayingSyllables
            : player.isPlayingSlow;

        final Widget child;
        if (preparing) {
          child = const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        } else {
          child = Icon(playing ? Icons.stop : Icons.slow_motion_video);
        }

        return SizedBox(
          width: _size,
          height: _size,
          child: Tooltip(
            message: bySyllable
                ? 'Hear it slowly, syllable by syllable'
                : 'Hear it slowly',
            child: OutlinedButton(
              onPressed: () => bySyllable
                  ? player.toggleSyllables(text)
                  : player.toggleSlow(text),
              style: OutlinedButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                side: BorderSide(
                  color: playing
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                ),
                foregroundColor: playing
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
