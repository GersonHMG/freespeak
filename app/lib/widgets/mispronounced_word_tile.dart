import 'package:flutter/material.dart';

import '../data/practice_history_store.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import 'tap_sound.dart';

/// One row of a mispronounced-words list: the word, how often it was missed,
/// and its average accuracy in the band's colour.
///
/// [onTap] makes the whole row tappable (the word picker uses it to start a
/// drill); [onPractice] adds a trailing mic button instead, for a list where
/// the row itself is informational (My Progress). Either, both, or neither.
class MispronouncedWordTile extends StatelessWidget {
  const MispronouncedWordTile({
    super.key,
    required this.word,
    this.onTap,
    this.onPractice,
  });

  final MispronouncedWord word;
  final VoidCallback? onTap;
  final VoidCallback? onPractice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final band = ScoreThresholds.standard.bandFor(word.averageAccuracy);
    final bandColor = colorForBand(theme, band);

    return ListTile(
      onTap: onTap == null
          ? null
          : () {
              playTapSound();
              onTap!();
            },
      title: Text(
        word.word,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        'Missed ${word.timesMissed} '
        '${word.timesMissed == 1 ? 'time' : 'times'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${word.averageAccuracy.round()}%',
            style: theme.textTheme.titleMedium?.copyWith(
              color: bandColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (onPractice != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Practice this word',
              icon: const Icon(Icons.mic_rounded),
              color: theme.colorScheme.primary,
              onPressed: () {
                playTapSound();
                onPractice!();
              },
            ),
          ] else if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}
