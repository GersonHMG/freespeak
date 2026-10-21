import 'package:flutter_test/flutter_test.dart';
import 'package:lingo_node/decks/deck_models.dart';
import 'package:lingo_node/decks/scheduler.dart';

CardSchedule _review({required double interval, double ease = 2.5}) =>
    CardSchedule(
      state: CardState.review,
      dueAt: DateTime(2026, 10, 18),
      intervalDays: interval,
      ease: ease,
      reps: 3,
      lapses: 0,
    );

void main() {
  // Evening, so "start of the due day" is visibly not now + N * 24 h.
  final now = DateTime(2026, 10, 18, 21, 30);

  group('first look', () {
    test('Difficult keeps a new card in the session', () {
      final next = scheduleReview(CardSchedule.fresh, Grade.difficult, now);
      expect(next.state, CardState.learning);
      expect(next.intervalDays, 0);
      expect(next.dueAt, now);
      expect(next.reps, 1);
      expect(next.lapses, 0);
      expect(next.ease, kStartEase);
    });

    test('Medium is due tomorrow at midnight', () {
      final next = scheduleReview(CardSchedule.fresh, Grade.medium, now);
      expect(next.state, CardState.review);
      expect(next.intervalDays, 1);
      expect(next.dueAt, DateTime(2026, 10, 19));
    });

    test('Easy is due in three days', () {
      final next = scheduleReview(CardSchedule.fresh, Grade.easy, now);
      expect(next.intervalDays, 3);
      expect(next.dueAt, DateTime(2026, 10, 21));
    });

    test('a learning card graduates on Medium', () {
      final learning = scheduleReview(CardSchedule.fresh, Grade.difficult, now);
      final next = scheduleReview(learning, Grade.medium, now);
      expect(next.state, CardState.review);
      expect(next.intervalDays, 1);
      expect(next.reps, 2);
    });
  });

  group('later reviews', () {
    test('Medium multiplies the interval by the ease', () {
      final next = scheduleReview(_review(interval: 4), Grade.medium, now);
      expect(next.intervalDays, 10); // round(4 * 2.5)
      expect(next.ease, 2.5);
      expect(next.dueAt, DateTime(2026, 10, 28));
    });

    test('Medium always grows the interval by at least a day', () {
      final next = scheduleReview(
        _review(interval: 1, ease: 1.3),
        Grade.medium,
        now,
      );
      expect(next.intervalDays, 2); // round(1.3) = 1, raised to I + 1
    });

    test('Easy multiplies further and raises the ease', () {
      final next = scheduleReview(_review(interval: 4), Grade.easy, now);
      expect(next.intervalDays, 13); // round(4 * 2.5 * 1.3)
      expect(next.ease, closeTo(2.65, 1e-9));
    });

    test('Easy is always ahead of Medium', () {
      final card = _review(interval: 1, ease: 1.3);
      final medium = scheduleReview(card, Grade.medium, now);
      final easy = scheduleReview(card, Grade.easy, now);
      expect(easy.intervalDays, greaterThan(medium.intervalDays));
    });

    test('Difficult resets to one day, lowers the ease and counts a lapse', () {
      final next = scheduleReview(_review(interval: 30), Grade.difficult, now);
      expect(next.state, CardState.review);
      expect(next.intervalDays, 1);
      expect(next.ease, closeTo(2.3, 1e-9));
      expect(next.lapses, 1);
      expect(next.dueAt, DateTime(2026, 10, 19));
    });

    test('the ease never drops below its floor', () {
      final next = scheduleReview(
        _review(interval: 5, ease: 1.4),
        Grade.difficult,
        now,
      );
      expect(next.ease, kMinEase);
    });
  });

  test('startOfDay crosses month ends by calendar, not by 24 h steps', () {
    expect(
      startOfDay(DateTime(2026, 10, 30, 23), plusDays: 3),
      DateTime(2026, 11, 2),
    );
  });
}
