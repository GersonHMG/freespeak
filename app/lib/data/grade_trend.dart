// The Progress tab's score trend: every Recall grade of the last two weeks,
// bucketed into local days, and a rolling score over them.
//
// A grade is worth Perfect 100, Partial 50, Wrong 0. A day's score, and a
// window's, is the mean over every answer in it -- so a 50-answer day
// weighs 25 times a 2-answer day, and a light day can't swing the trend.
//
// Bucketing is plain Dart for the same reason as daily_activity.dart: the
// timestamps are epoch milliseconds, and DateTime already knows which local
// day each one falls on.

import '../decks/deck_models.dart';
import '../decks/deck_store.dart';

/// How many days back the trend reaches, today included.
const int kGradeTrendDays = 14;

/// Below this many answers a day's own score says little; the trend screen
/// draws such a day faded.
const int kFewAnswers = 5;

/// The grades given on one day, or over a run of days.
class GradeTally {
  const GradeTally({this.perfect = 0, this.partial = 0, this.wrong = 0});

  final int perfect;
  final int partial;
  final int wrong;

  int get total => perfect + partial + wrong;

  /// 0-100, or null when nothing was graded.
  int? get score =>
      total == 0 ? null : ((perfect * 100 + partial * 50) / total).round();

  int count(Grade grade) => switch (grade) {
    Grade.easy => perfect,
    Grade.medium => partial,
    Grade.difficult => wrong,
  };

  GradeTally operator +(GradeTally other) => GradeTally(
    perfect: perfect + other.perfect,
    partial: partial + other.partial,
    wrong: wrong + other.wrong,
  );

  static GradeTally sum(Iterable<GradeTally> tallies) =>
      tallies.fold(const GradeTally(), (a, b) => a + b);
}

class GradeTrend {
  GradeTrend._(this.days, this.tallies, this.window);

  /// One local day each, oldest first, ending today; consecutive, so a day
  /// with no practice is there with an empty tally. Starts at the first
  /// graded day when that is under [kGradeTrendDays] ago.
  final List<DateTime> days;
  final List<GradeTally> tallies;

  /// Days the rolling score and the comparison cover: a week once there are
  /// two weeks of history, 3 days before that.
  final int window;

  bool get isEmpty => days.isEmpty;

  /// The score over the [window] days ending at day [i] (fewer at the
  /// start), or null when none of them had any grades.
  int? rollingScore(int i) =>
      GradeTally.sum(tallies.sublist((i - window + 1).clamp(0, i), i + 1))
          .score;

  /// The last [window] days together.
  GradeTally get latest => GradeTally.sum(
    tallies.sublist((tallies.length - window).clamp(0, tallies.length)),
  );

  /// The first [window] days together -- what [latest] is compared against.
  GradeTally get earliest =>
      GradeTally.sum(tallies.take(window.clamp(0, tallies.length)));

  /// [latest]'s score minus [earliest]'s, or null while the two windows
  /// would overlap (too little history to compare) or either is empty.
  int? get change {
    if (days.length < 2 * window) return null;
    final now = latest.score, then = earliest.score;
    return now == null || then == null ? null : now - then;
  }
}

/// Pure bucketing of [grades] (what, when) into a [GradeTrend] ending on
/// [now]'s day. Grades older than [kGradeTrendDays] are ignored.
GradeTrend computeGradeTrend(
  List<(Grade grade, DateTime at)> grades, {
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  final from = DateTime(
    today.year,
    today.month,
    today.day - (kGradeTrendDays - 1),
  );
  final byDay = <DateTime, GradeTally>{};
  for (final (grade, at) in grades) {
    final day = _dateOnly(at);
    if (day.isBefore(from) || day.isAfter(today)) continue;
    byDay[day] =
        (byDay[day] ?? const GradeTally()) +
        switch (grade) {
          Grade.easy => const GradeTally(perfect: 1),
          Grade.medium => const GradeTally(partial: 1),
          Grade.difficult => const GradeTally(wrong: 1),
        };
  }
  if (byDay.isEmpty) return GradeTrend._(const [], const [], 3);

  final first = byDay.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  final days = [
    for (
      var d = first;
      !d.isAfter(today);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      d,
  ];
  final tallies = [for (final day in days) byDay[day] ?? const GradeTally()];
  return GradeTrend._(days, tallies, days.length >= kGradeTrendDays ? 7 : 3);
}

Future<GradeTrend> loadGradeTrend(DeckStore decks, {DateTime? now}) async {
  final today = _dateOnly(now ?? DateTime.now());
  final since = DateTime(
    today.year,
    today.month,
    today.day - (kGradeTrendDays - 1),
  );
  return computeGradeTrend(await decks.gradesSince(since), now: now);
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
