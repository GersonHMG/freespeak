// What the phrase should sound like, against what the learner actually said,
// in IPA.
//
// Before an attempt the screen shows the reference phonemes on their own;
// this is what takes that slot once there is something to compare them to.
// The two rows carry one column per word, in the same order, so a wrong sound
// is found by reading straight down rather than by hunting through a single
// run-on string.
//
// Colouring matches the phrase above it (see [SpokenText]) — same bands, same
// palette — so a red cluster of symbols here and a red word up there are
// visibly one fact stated twice, once in spelling and once in sound. That is
// the whole point of showing this: "fox" being wrong says nothing a learner
// can act on, and /fɑks/ where /fɒks/ was wanted says exactly what to change.

import 'package:flutter/material.dart';

import '../pronunciation/category.dart';
import '../pronunciation/pronunciation_result.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';

/// Stands in for a word that drew no sounds at all, so the rows still read
/// word for word instead of the spoken side quietly closing the gap.
const String _silence = '·';

/// The reference and spoken phonemes of a scored attempt, word by word.
class PhonemeComparison extends StatelessWidget {
  const PhonemeComparison({required this.result, super.key});

  final PronunciationResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // A word the phonemizer had no entry for has no sounds on either side, and
    // would show as a blank column in both rows rather than as anything the
    // learner could read.
    final scored = [
      for (final word in result.words)
        if (word.referencePhonemes.isNotEmpty) word,
    ];
    if (scored.isEmpty) return const SizedBox.shrink();

    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(
            theme: theme,
            label: 'TARGET',
            style: mono?.copyWith(color: colorScheme.onSurfaceVariant),
            spans: [
              for (var i = 0; i < scored.length; i++)
                TextSpan(text: _spaced(i, scored[i].referencePhonemes)),
            ],
          ),
          const SizedBox(height: 6),
          _row(
            theme: theme,
            label: 'YOU SAID',
            style: mono,
            spans: [
              for (var i = 0; i < scored.length; i++)
                TextSpan(
                  text: _spaced(
                    i,
                    scored[i].spokenPhonemes.isEmpty
                        ? _silence
                        : scored[i].spokenPhonemes,
                  ),
                  style: TextStyle(color: _colorFor(theme, scored[i])),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _spaced(int index, String phonemes) =>
      index == 0 ? phonemes : ' $phonemes';

  Widget _row({
    required ThemeData theme,
    required String label,
    required TextStyle? style,
    required List<InlineSpan> spans,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(style: style, children: spans),
          ),
        ),
      ],
    );
  }

  Color _colorFor(ThemeData theme, ScoredWord score) {
    if (score.wasSkipped) return theme.colorScheme.error;
    return colorForBand(theme, _bandFor(score.category));
  }

  ScoreBand _bandFor(PronunciationCategory category) => switch (category) {
    PronunciationCategory.good => ScoreBand.green,
    PronunciationCategory.mediocre => ScoreBand.orange,
    PronunciationCategory.bad => ScoreBand.red,
  };
}
