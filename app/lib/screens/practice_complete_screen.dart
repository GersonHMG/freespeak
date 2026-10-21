// Shown when a "wrong words" drill has been through every word: how the
// pass went, and the way back home.
//
// Deliberately not [SessionCompleteScreen]: no daily-goal celebration or
// confetti here even for a scored (Word Rematch) run -- this stays a
// summary, just one that also states the points when the run earned any.

import 'package:flutter/material.dart';

import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import '../widgets/tap_sound.dart';

class PracticeCompleteScreen extends StatelessWidget {
  const PracticeCompleteScreen({
    required this.words,
    required this.bestAccuracyByWord,
    this.totalPoints,
    super.key,
  });

  /// The drill's words, in order.
  final List<String> words;

  /// Each word's best scored attempt this drill, 0-100. A word the learner
  /// skipped without recording has no entry.
  final Map<String, int> bestAccuracyByWord;

  /// Points earned this run, or null for a drill that doesn't award points
  /// (see [PracticeScreen.awardsPoints]) -- null hides the points line
  /// entirely rather than showing "0 pts" for a mode that was never scored.
  final int? totalPoints;

  int get _attempted => bestAccuracyByWord.length;

  int get _averageAccuracy => _attempted == 0
      ? 0
      : (bestAccuracyByWord.values.reduce((a, b) => a + b) / _attempted)
            .round();

  int get _soundedGood => bestAccuracyByWord.values
      .where(
        (accuracy) =>
            ScoreThresholds.standard.bandFor(accuracy.toDouble()) ==
            ScoreBand.green,
      )
      .length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final band = ScoreThresholds.standard.bandFor(_averageAccuracy.toDouble());

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Icon(
                Icons.task_alt_rounded,
                size: 72,
                color: _attempted == 0
                    ? colors.onSurfaceVariant
                    : colorForBand(theme, band),
              ),
              const SizedBox(height: 20),
              Text(
                'Practice Complete!',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (totalPoints != null) ...[
                const SizedBox(height: 12),
                Text(
                  '+$totalPoints pts',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.primary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _attempted == 0
                    ? 'No words recorded this time.'
                    : '$_soundedGood of $_attempted '
                          '${_attempted == 1 ? 'word' : 'words'} sounded good',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (_attempted > 0) ...[
                const SizedBox(height: 28),
                Text(
                  '$_averageAccuracy%',
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorForBand(theme, band),
                  ),
                ),
                Text(
                  'average accuracy',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final word in words)
                    _WordChip(word: word, accuracy: bestAccuracyByWord[word]),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  playTapSound();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({required this.word, required this.accuracy});

  final String word;
  final int? accuracy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final score = accuracy;
    final color = score == null
        ? colors.onSurfaceVariant
        : colorForBand(
            theme,
            ScoreThresholds.standard.bandFor(score.toDouble()),
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        score == null ? word : '$word  $score%',
        style: theme.textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
