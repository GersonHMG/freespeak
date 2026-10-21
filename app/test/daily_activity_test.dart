// computeDailyActivity is pure Dart (no database), so it's tested directly
// against synthetic (card, timestamp) reads rather than through
// PracticeHistoryStore -- see test/practice_history_store_test.dart for the
// sqflite-ffi-backed coverage of the store itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/data/daily_activity.dart';

void main() {
  // A Wednesday, so there are both earlier (Mon, Tue) and later (Thu..Sun)
  // days in the same week to check are handled correctly.
  final wednesday = DateTime(2024, 1, 10, 15, 30);
  final tuesday = DateTime(2024, 1, 9);
  final monday = DateTime(2024, 1, 8);
  final lastSunday = DateTime(2024, 1, 7); // the week before

  test('the goal is 15 cards: one pronunciation session and 10 Recall', () {
    expect(kDefaultDailyGoalTarget, 15);
  });

  test('counts only today\'s cards for cardsToday', () {
    final result = computeDailyActivity([
      ('a', wednesday),
      ('b', wednesday.add(const Duration(hours: 1))),
      ('c', tuesday),
    ], now: wednesday);

    expect(result.cardsToday, 2);
  });

  test('a card read twice in a day counts once', () {
    final result = computeDailyActivity([
      ('card:1', wednesday),
      ('card:1', wednesday.add(const Duration(minutes: 5))),
      ('sentence:Hello there.', wednesday),
      ('sentence:Hello there.', wednesday.add(const Duration(minutes: 1))),
    ], now: wednesday);

    expect(result.cardsToday, 2);
  });

  test('the same card on two days counts on each', () {
    final result = computeDailyActivity([
      ('card:1', tuesday),
      ('card:1', wednesday),
    ], now: wednesday);

    expect(result.cardsPerDay, [0, 1, 1, 0, 0, 0, 0]);
  });

  test('marks each day of the week practiced or not, Monday-first', () {
    final result = computeDailyActivity([
      ('a', monday),
      ('b', wednesday),
    ], now: wednesday);

    expect(result.practicedDays, [
      true,
      false,
      true,
      false,
      false,
      false,
      false,
    ]);
  });

  test('excludes reads from a previous week from practicedDays', () {
    final result = computeDailyActivity([('a', lastSunday)], now: wednesday);

    expect(result.cardsToday, 0);
    expect(result.practicedDays, everyElement(false));
  });

  group('currentStreak', () {
    test('counts consecutive practiced days ending today', () {
      final result = computeDailyActivity([
        ('a', monday),
        ('a', tuesday),
        ('a', wednesday),
      ], now: wednesday);

      expect(result.currentStreak, 3);
    });

    test('stays alive on a day with nothing yet, counting from yesterday', () {
      final result = computeDailyActivity([
        ('a', monday),
        ('a', tuesday),
      ], now: wednesday);

      expect(result.currentStreak, 2);
    });

    test('breaks on a gap before today', () {
      final result = computeDailyActivity([
        ('a', monday),
        // Tuesday skipped.
        ('a', wednesday),
      ], now: wednesday);

      expect(result.currentStreak, 1);
    });

    test('is zero with no practice at all', () {
      final result = computeDailyActivity(const [], now: wednesday);

      expect(result.currentStreak, 0);
    });
  });

  group('bestStreak', () {
    test('finds a longer run earlier in the window than the current one', () {
      final result = computeDailyActivity([
        // A four-day run the week before, then a gap, then today alone.
        ('a', lastSunday.subtract(const Duration(days: 3))),
        ('a', lastSunday.subtract(const Duration(days: 2))),
        ('a', lastSunday.subtract(const Duration(days: 1))),
        ('a', lastSunday),
        ('a', wednesday),
      ], now: wednesday);

      expect(result.currentStreak, 1);
      expect(result.bestStreak, 4);
    });

    test('is never below currentStreak', () {
      final result = computeDailyActivity([
        ('a', monday),
        ('a', tuesday),
        ('a', wednesday),
      ], now: wednesday);

      expect(result.bestStreak, result.currentStreak);
    });

    test('is zero with no practice at all', () {
      expect(computeDailyActivity(const [], now: wednesday).bestStreak, 0);
    });
  });

  test('cardsPerDay counts each weekday, Monday first, ahead days zero', () {
    final result = computeDailyActivity([
      ('a', monday),
      ('b', monday.add(const Duration(hours: 5))),
      ('c', wednesday),
      ('d', lastSunday), // previous week: excluded
    ], now: wednesday);

    expect(result.cardsPerDay, [2, 0, 1, 0, 0, 0, 0]);
  });

  group('computeYearActivity', () {
    final now = DateTime(2024, 3, 10, 12); // the 70th day of a leap year

    test('buckets the year by day, a card once a day', () {
      final year = computeYearActivity([
        ('a', DateTime(2024, 3, 9, 9)),
        ('a', DateTime(2024, 3, 9, 18)),
        ('b', DateTime(2024, 3, 9, 20)),
        ('a', DateTime(2024, 3, 10, 8)),
        ('z', DateTime(2023, 12, 31, 23)), // last year: left out
      ], 2024, now: now);

      expect(year.cardsOn(DateTime(2024, 3, 9)), 2);
      expect(year.cardsOn(DateTime(2024, 3, 10, 22)), 1);
      expect(year.cardsOn(DateTime(2023, 12, 31)), 0);
      expect(year.totalCards, 3);
      expect(year.daysPracticed, 2);
      expect(year.dailyAverage, 2); // 3 cards over 2 days, rounded
    });

    test('days learned counts the days so far, all of a past year', () {
      final reads = [
        for (var d = 1; d <= 7; d++) ('a', DateTime(2024, 1, d)),
      ];
      expect(computeYearActivity(reads, 2024, now: now).daysElapsed, 70);
      expect(computeYearActivity(reads, 2024, now: now).daysLearnedPercent, 10);
      expect(
        computeYearActivity(reads, 2024, now: DateTime(2025, 6)).daysElapsed,
        366,
      );
      expect(computeYearActivity([], 2025, now: now).daysElapsed, 0);
      expect(computeYearActivity([], 2025, now: now).daysLearnedPercent, 0);
    });

    test('the longest streak is the longest run within the year', () {
      final year = computeYearActivity([
        for (var d = 1; d <= 3; d++) ('a', DateTime(2024, 1, d)),
        for (var d = 20; d <= 24; d++) ('a', DateTime(2024, 2, d)),
        ('a', DateTime(2024, 3, 1)),
      ], 2024, now: now);
      expect(year.longestStreak, 5);
    });

    test('the best day and the months', () {
      final year = computeYearActivity([
        ('a', DateTime(2024, 1, 5)),
        ('a', DateTime(2024, 2, 1)),
        ('b', DateTime(2024, 2, 1)),
        ('a', DateTime(2024, 2, 9)),
        ('b', DateTime(2024, 2, 9)), // ties 1 Feb: the earlier one wins
      ], 2024, now: now);

      expect(year.bestDay?.key, DateTime(2024, 2, 1));
      expect(year.bestDay?.value, 2);
      expect(year.months[0], (cards: 1, days: 1));
      expect(year.months[1], (cards: 4, days: 2));
      expect(year.months[2], (cards: 0, days: 0));
      expect(computeYearActivity([], 2024, now: now).bestDay, isNull);
    });

    test('a streak runs on across a daylight-saving change', () {
      // Spring forward in Europe (31 March) and the US (10 March), so
      // whichever zone the test runs in, one of the gaps is 23 hours.
      final reads = [
        for (var d = 8; d <= 12; d++) ('a', DateTime(2024, 3, d)),
        for (var d = 29; d <= 31; d++) ('a', DateTime(2024, 3, d)),
        ('a', DateTime(2024, 4, 1)),
      ];
      expect(
        computeYearActivity(reads, 2024, now: DateTime(2024, 5)).longestStreak,
        5,
      );
      expect(
        computeDailyActivity(reads, now: DateTime(2024, 4, 1, 12))
            .currentStreak,
        4,
      );
    });
  });
}
