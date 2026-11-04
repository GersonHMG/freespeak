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

  test('a streak runs on across a daylight-saving change', () {
    // Spring forward in Europe (31 March) and the US (10 March), so
    // whichever zone the test runs in, one of the gaps is 23 hours.
    final reads = [
      for (var d = 8; d <= 12; d++) ('a', DateTime(2024, 3, d)),
      for (var d = 29; d <= 31; d++) ('a', DateTime(2024, 3, d)),
      ('a', DateTime(2024, 4, 1)),
    ];
    final result = computeDailyActivity(reads, now: DateTime(2024, 4, 1, 12));
    expect(result.bestStreak, 5);
    expect(result.currentStreak, 4);
  });
}
