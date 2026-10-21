import 'package:flutter/material.dart';

import '../data/practice_history_store.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import 'tap_sound.dart';

/// One row of a mispronounced-sentences list: the sentence, how often it was
/// missed, and its average score in the band's colour. The sentence-level
/// sibling of [MispronouncedWordTile].
class MispronouncedSentenceTile extends StatelessWidget {
  const MispronouncedSentenceTile({
    super.key,
    required this.sentence,
    required this.onTap,
  });

  final MispronouncedSentence sentence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final band = ScoreThresholds.standard.bandFor(sentence.averageAccuracy);
    final bandColor = colorForBand(theme, band);

    return ListTile(
      onTap: () {
        playTapSound();
        onTap();
      },
      title: Text(
        sentence.sentence,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        'Missed ${sentence.timesMissed} '
        '${sentence.timesMissed == 1 ? 'time' : 'times'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${sentence.averageAccuracy.round()}%',
            style: theme.textTheme.titleMedium?.copyWith(
              color: bandColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
