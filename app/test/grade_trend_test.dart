// computeGradeTrend is pure Dart (no database), so it's tested directly
// against synthetic (grade, timestamp) records; the DeckStore query feeding
// it is covered through the Progress tab's widget test.

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/grade_trend.dart';
import 'package:lingo_node/decks/deck_models.dart';

void main() {
  final today = DateTime(2026, 11, 4, 18);
  DateTime daysAgo(int n) => DateTime(2026, 11, 4 - n, 10);

  List<(Grade, DateTime)> day(
    int ago, {
    int perfect = 0,
    int partial = 0,
    int wrong = 0,
  }) => [
    for (var i = 0; i < perfect; i++) (Grade.easy, daysAgo(ago)),
    for (var i = 0; i < partial; i++) (Grade.medium, daysAgo(ago)),
    for (var i = 0; i < wrong; i++) (Grade.difficult, daysAgo(ago)),
  ];

  test('nothing graded is an empty trend', () {
    expect(computeGradeTrend([], now: today).isEmpty, isTrue);
  });

  test('a day scores Perfect 100, Partial 50, Wrong 0, averaged', () {
    // The example the panel was designed around: 5 wrong, then 2 partial
    // and 3 wrong, then 1 perfect and 4 partial.
    final trend = computeGradeTrend([
      ...day(2, wrong: 5),
      ...day(1, partial: 2, wrong: 3),
      ...day(0, perfect: 1, partial: 4),
    ], now: today);

    expect(trend.days, hasLength(3));
    expect([for (final t in trend.tallies) t.score], [0, 20, 60]);
    expect(trend.tallies.last.perfect, 1);
    expect(trend.tallies.last.partial, 4);
  });

  test('starts at the first graded day and fills days off as empty', () {
    final trend = computeGradeTrend([
      ...day(3, perfect: 1),
      ...day(0, perfect: 1),
    ], now: today);

    expect(trend.days.first, DateTime(2026, 11, 1));
    expect(trend.days.last, DateTime(2026, 11, 4));
    expect([for (final t in trend.tallies) t.total], [1, 0, 0, 1]);
    expect(trend.tallies[1].score, isNull);
  });

  test('looks back two weeks at most', () {
    final trend = computeGradeTrend([
      ...day(20, wrong: 9),
      ...day(13, perfect: 1),
    ], now: today);

    expect(trend.days, hasLength(kGradeTrendDays));
    expect(trend.window, 7);
    expect(trend.tallies.first.wrong, 0);
  });

  test('the rolling score weighs every answer once, not every day', () {
    // 2 perfect answers one day, 48 wrong the next: the busy day decides.
    final trend = computeGradeTrend([
      ...day(1, perfect: 2),
      ...day(0, wrong: 48),
    ], now: today);

    expect(trend.window, 3);
    expect(trend.rollingScore(1), 4); // 200 points over 50 answers
  });

  test(
    'compares the last window with the first only once they do not overlap',
    () {
      final short = computeGradeTrend([
        ...day(4, wrong: 5),
        ...day(0, perfect: 5),
      ], now: today);
      expect(short.change, isNull); // 5 days, two 3-day windows overlap

      final long = computeGradeTrend([
        ...day(13, wrong: 5),
        ...day(12, partial: 2, wrong: 3),
        ...day(11, perfect: 1, partial: 4),
        ...day(1, perfect: 6, partial: 1, wrong: 1),
        ...day(0, perfect: 7, partial: 1),
      ], now: today);
      expect(long.earliest.score, 27); // 400 points over 15 answers
      expect(long.latest.score, 88); // 1400 points over 16 answers
      expect(long.change, 61);
    },
  );
}
