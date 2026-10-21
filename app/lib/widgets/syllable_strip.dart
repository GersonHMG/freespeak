// Word Rematch's syllable view: the word printed a syllable at a time
// ("how · ev · er"), each piece lighting up as it is spoken and playable on
// its own. [SlowHearButton] with `bySyllable` plays them all, slowed.
//
// Both read the screen's [PhrasePlayer] rather than owning audio, for the
// same reason [HearButton] does: the word, its syllables and the highlight
// all have to agree about what is playing.

import 'package:flutter/material.dart';

import '../tts/phrase_player.dart';
import '../tts/syllabifier.dart';

/// The current word's syllables as tappable chips. Empty until the player has
/// built them, and for a one-syllable word, where there is nothing to split.
class SyllableStrip extends StatelessWidget {
  const SyllableStrip({super.key, required this.player});

  final PhrasePlayer player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final audio = player.syllables;
        if (audio == null || audio.labels.length < 2) {
          return const SizedBox.shrink();
        }

        final children = <Widget>[];
        for (var i = 0; i < audio.labels.length; i++) {
          if (i > 0) {
            children.add(
              Text(
                '·',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            );
          }
          final spoken = player.spokenSyllable == i;
          final stressed = audio.syllables[i].stress == SyllableStress.primary;
          children.add(
            Material(
              color: spoken
                  ? colors.primary.withValues(alpha: 0.16)
                  : Colors.transparent,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => player.playSyllable(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    audio.labels[i],
                    style: theme.textTheme.titleMedium?.copyWith(
                      // The stressed syllable is the one to lean on.
                      fontWeight: stressed ? FontWeight.w800 : FontWeight.w500,
                      fontFamily: audio.spelled ? null : 'monospace',
                      color: spoken ? colors.primary : colors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          children: children,
        );
      },
    );
  }
}
