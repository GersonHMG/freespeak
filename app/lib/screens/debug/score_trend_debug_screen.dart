// The Progress tab's Score card and its details page fed made-up grades, to
// see how the trend draws with more (or odder) history than the device has.
// Nothing is written to the database: the sample grades go straight into
// computeGradeTrend.

import 'package:flutter/material.dart';

import '../../data/grade_trend.dart';
import '../../decks/deck_models.dart';
import '../../theme/lingo_theme.dart';
import '../score_trend_screen.dart';

/// [perfect, partial, wrong] per day, oldest first, ending today; null is a
/// day with no practice.
// dart format off
const Map<String, List<List<int>?>> _samples = {
  'Busy and light days': [
    [0, 0, 5], [0, 2, 3], [1, 4, 0], [2, 10, 18], [1, 1, 0], null, [12, 20, 8],
    [3, 1, 0], [15, 22, 13], [20, 15, 5], [2, 0, 0], [18, 10, 4], [1, 2, 3],
    [30, 12, 4],
  ],
  'Steady climb': [
    [0, 0, 5], [0, 2, 3], [1, 4, 0], [1, 3, 2], [2, 3, 1], null, [3, 2, 1],
    [3, 3, 0], [4, 2, 1], [4, 3, 0], null, [5, 2, 0], [6, 1, 1], [7, 1, 0],
  ],
  'With a slump': [
    [0, 0, 5], [0, 2, 3], [1, 4, 0], [2, 3, 1], [1, 2, 4], null, null,
    [1, 3, 2], [3, 3, 1], [4, 2, 1], [3, 4, 0], [5, 2, 1], [5, 3, 0],
    [6, 2, 0],
  ],
  'Heavy use': [
    [10, 30, 60], [14, 36, 50], [20, 40, 45], [25, 45, 40], [30, 50, 35],
    [38, 50, 30], [45, 50, 25], [50, 48, 20], [60, 45, 18], [70, 40, 15],
    [80, 35, 12], [90, 30, 10], [100, 25, 8], [120, 20, 5],
  ],
  'Getting worse': [
    [6, 2, 0], [5, 3, 0], [5, 2, 1], [4, 3, 1], [4, 2, 2], [3, 3, 2],
    [3, 2, 3], [2, 3, 3], [2, 2, 4], [1, 3, 4], [1, 2, 5], [0, 3, 5],
    [0, 2, 6], [0, 1, 7],
  ],
  'First 3 days': [
    [0, 0, 5], [0, 2, 3], [1, 4, 0],
  ],
  'Today only': [
    [1, 4, 0],
  ],
};
// dart format on

class ScoreTrendDebugScreen extends StatefulWidget {
  const ScoreTrendDebugScreen({super.key});

  @override
  State<ScoreTrendDebugScreen> createState() => _ScoreTrendDebugScreenState();
}

class _ScoreTrendDebugScreenState extends State<ScoreTrendDebugScreen> {
  String _sample = _samples.keys.first;

  GradeTrend _trend() {
    final now = DateTime.now();
    final days = _samples[_sample]!;
    final grades = <(Grade, DateTime)>[];
    for (final (i, day) in days.indexed) {
      if (day == null) continue;
      final at = DateTime(
        now.year,
        now.month,
        now.day - (days.length - 1 - i),
        12,
      );
      for (final (grade, count) in [
        (Grade.easy, day[0]),
        (Grade.medium, day[1]),
        (Grade.difficult, day[2]),
      ]) {
        grades.addAll(List.filled(count, (grade, at)));
      }
    }
    return computeGradeTrend(grades, now: now);
  }

  @override
  Widget build(BuildContext context) {
    final trend = _trend();
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        title: const Text('Score trend (sample data)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in _samples.keys)
                ChoiceChip(
                  label: Text(name),
                  selected: name == _sample,
                  onSelected: (_) => setState(() => _sample = name),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // Tapping the card opens the details page with the same sample.
          ScoreTrendCard(trend: trend),
        ],
      ),
    );
  }
}
