// The verdict on one attempt: a headline score, and the words to work on.
//
// Deliberately short. The per-word colouring in [SpokenText] is the real
// feedback — it sits on the words themselves, where the learner is already
// looking. This exists to say what was heard, which is the one thing the
// colouring cannot: half of a bad score is the recognizer mishearing a word,
// and being able to see that is what stops the app feeling arbitrary.

import 'package:flutter/material.dart';

import '../pronunciation/category.dart';
import '../pronunciation/pronunciation_result.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import '../scoring/session_score.dart';

class ScoreSummary extends StatelessWidget {
  const ScoreSummary({
    super.key,
    required this.result,
    this.onListenToAttempt,
    this.outcome,
  });

  final PronunciationResult result;

  /// Plays the whole recording back, unedited. Null (or the button is simply
  /// omitted) when there is nothing to play — a test result built without a
  /// [PronunciationResult.recordingPath], most often.
  final VoidCallback? onListenToAttempt;

  /// This attempt's points, difficulty, and (past the first try) its decay --
  /// what [SessionScore.record] returned for it. Null skips the points line
  /// entirely, which is what a result built without going through the
  /// session scorer (a test, or nothing was heard) should pass.
  final AttemptOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needWork = result.mispronounced;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${result.overall}%',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: _scoreColor(theme, result.overall),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _verdict(result.overall, needWork.length),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (outcome != null) ...[
          const SizedBox(height: 4),
          Text(
            _pointsLine(outcome!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (result.spokenText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Heard: "${result.spokenText}"',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              // Only when there is a recording to play — a result scored
              // straight from a transcript (a test, mainly) has none.
              if (result.recordingPath != null && onListenToAttempt != null)
                IconButton(
                  onPressed: onListenToAttempt,
                  icon: const Icon(Icons.play_circle_outline),
                  iconSize: 20,
                  tooltip: 'Hear your whole attempt',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ],
        if (needWork.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in needWork)
                Chip(
                  label: Text(word.word),
                  labelStyle: theme.textTheme.bodySmall,
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(
                    color: word.wasSkipped
                        ? theme.colorScheme.error
                        : theme.colorScheme.outlineVariant,
                  ),
                  avatar: Text(
                    word.wasSkipped ? '—' : '${word.accuracy.round()}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _verdict(int overall, int needWork) {
    // Nothing recognized at all is a different message from a bad attempt:
    // the first is usually a microphone or a room, not a pronunciation.
    if (result.spokenText.isEmpty) return 'Nothing was heard — try again.';
    if (needWork == 0) return 'Clean read.';
    return needWork == 1
        ? 'One word to work on. Tap it to hear it.'
        : '$needWork words to work on. Tap one to hear it.';
  }

  Color _scoreColor(ThemeData theme, int overall) =>
      colorForBand(theme, _bandFor(categoryForAccuracy(overall.toDouble())));

  ScoreBand _bandFor(PronunciationCategory category) => switch (category) {
    PronunciationCategory.good => ScoreBand.green,
    PronunciationCategory.mediocre => ScoreBand.orange,
    PronunciationCategory.bad => ScoreBand.red,
  };

  /// e.g. "+130 pts · Medium ×1.3" on a first attempt, with "· attempt 2
  /// ×0.8" appended once decay applies.
  String _pointsLine(AttemptOutcome outcome) {
    final difficulty = outcome.score.difficulty;
    final label =
        difficulty.name[0].toUpperCase() + difficulty.name.substring(1);
    final multiplier = difficulty.multiplier.toStringAsFixed(1);
    final buffer = StringBuffer('+${outcome.award} pts · $label ×$multiplier');
    if (outcome.attemptNumber > 1) {
      buffer.write(
        ' · attempt ${outcome.attemptNumber} ×${outcome.decay.toStringAsFixed(1)}',
      );
    }
    return buffer.toString();
  }
}
