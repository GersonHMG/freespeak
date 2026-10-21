// Turns raw "card read" records into the numbers HomeScreen's progress card
// shows: cards read today, the practice streak, and which of this week's
// days had any practice at all.
//
// A card is one sentence of the pronunciation session or one Recall card.
// The daily goal is [kDefaultDailyGoalTarget] of them -- a pronunciation
// session's 5 sentences plus 10 Recall cards, so neither mode alone is the
// whole day. A card counts once per day however many times it was
// attempted: re-recording a sentence or seeing a Wrong card again later in
// the sitting reads the same card, not a new one.
//
// Bucketing happens here, in plain Dart, rather than as a SQL date query --
// [PracticeHistoryStore] stores timestamps as UTC epoch milliseconds, and
// converting those back to "which local calendar day" is what
// [DateTime.fromMillisecondsSinceEpoch] already does correctly; redoing that
// in SQLite would mean fighting its own (UTC) idea of what a day is.

import 'practice_history_store.dart';

/// Cards per day before the daily goal counts as met: 5 pronunciation
/// sentences (one session) plus 10 Recall cards.
const int kDefaultDailyGoalTarget = 15;

/// How far back [loadDailyActivity] looks for streak purposes. A streak
/// longer than this reads as "this many days" up to the cap rather than
/// growing forever -- generous enough that no real learner is likely to
/// notice the ceiling.
const int kStreakLookbackDays = 60;

/// The derived numbers HomeScreen's progress card needs.
class DailyActivity {
  const DailyActivity({
    required this.cardsToday,
    required this.currentStreak,
    required this.bestStreak,
    required this.practicedDays,
    required this.cardsPerDay,
  });

  /// Distinct cards read today.
  final int cardsToday;

  /// Consecutive days with at least one card read, counting backward from
  /// today if today already has practice, or from yesterday otherwise -- a
  /// streak stays alive for the rest of today even before it's added to, the
  /// same way it would be broken only once a whole day passes with nothing
  /// recorded.
  final int currentStreak;

  /// The longest run of consecutive practiced days anywhere in the lookback
  /// window -- at least [currentStreak], since that run is one candidate.
  final int bestStreak;

  /// One entry per day of the current week, Monday first: whether that day
  /// had any practice at all. Days still ahead this week are `false`.
  final List<bool> practicedDays;

  /// Cards read on each day of the current week, Monday first -- what
  /// [practicedDays] is `> 0` of. Days still ahead this week are 0.
  final List<int> cardsPerDay;
}

/// Reads the last [kStreakLookbackDays] of card reads from [store] and
/// buckets them into a [DailyActivity], via [computeDailyActivity].
Future<DailyActivity> loadDailyActivity(
  PracticeHistoryStore store, {
  int goalTarget = kDefaultDailyGoalTarget,
  DateTime? now,
}) async {
  final today = now ?? DateTime.now();
  final since = _dateOnly(today)
      .subtract(const Duration(days: kStreakLookbackDays));
  final reads = await store.cardReadsSince(since);
  return computeDailyActivity(reads, now: today, goalTarget: goalTarget);
}

/// Pure bucketing: [reads] (which card, when) into today's card count, the
/// current streak, and this week's practiced days. A card read more than
/// once in a day counts once that day. Takes plain records (not a store) so
/// it's testable without a database.
DailyActivity computeDailyActivity(
  List<(String card, DateTime at)> reads, {
  DateTime? now,
  int goalTarget = kDefaultDailyGoalTarget,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  final monday = _mondayOf(today);
  final countByDay = _countByDay(reads);

  final cardsPerDay = [
    for (var i = 0; i < 7; i++)
      countByDay[DateTime(monday.year, monday.month, monday.day + i)] ?? 0,
  ];

  return DailyActivity(
    cardsToday: countByDay[today] ?? 0,
    currentStreak: _streakEndingAt(countByDay, today),
    bestStreak: _longestStreak(countByDay),
    practicedDays: [for (final cards in cardsPerDay) cards > 0],
    cardsPerDay: cardsPerDay,
  );
}

/// One calendar year of practice -- the Progress tab's heatmap and the
/// numbers under it.
class YearActivity {
  const YearActivity({
    required this.year,
    required this.cardsByDay,
    required this.daysElapsed,
  });

  final int year;

  /// Distinct cards read on each local day of [year] that had any; a day
  /// missing from the map had none.
  final Map<DateTime, int> cardsByDay;

  /// Days of [year] up to and including today -- all of them for a past
  /// year, none for one still ahead.
  final int daysElapsed;

  int cardsOn(DateTime day) => cardsByDay[_dateOnly(day)] ?? 0;

  int get totalCards => cardsByDay.values.fold(0, (a, b) => a + b);

  int get daysPracticed => cardsByDay.length;

  /// Cards per day practised, rounded; 0 before any practice.
  int get dailyAverage =>
      daysPracticed == 0 ? 0 : (totalCards / daysPracticed).round();

  /// Share of the year's days so far with any practice, as a whole
  /// percentage.
  int get daysLearnedPercent =>
      daysElapsed == 0 ? 0 : (100 * daysPracticed / daysElapsed).round();

  /// The longest run of consecutive practised days within [year].
  int get longestStreak => _longestStreak(cardsByDay);

  /// The day with the most cards, earliest on a tie; null before any
  /// practice.
  MapEntry<DateTime, int>? get bestDay {
    MapEntry<DateTime, int>? best;
    for (final entry in cardsByDay.entries) {
      if (best == null ||
          entry.value > best.value ||
          entry.value == best.value && entry.key.isBefore(best.key)) {
        best = entry;
      }
    }
    return best;
  }

  /// Cards and practised days in each month of [year], January first.
  List<({int cards, int days})> get months => [
    for (var month = 1; month <= 12; month++)
      (
        cards: cardsByDay.entries
            .where((e) => e.key.month == month)
            .fold(0, (sum, e) => sum + e.value),
        days: cardsByDay.keys.where((day) => day.month == month).length,
      ),
  ];
}

/// Reads [year]'s card reads from [store] and buckets them into a
/// [YearActivity], via [computeYearActivity].
Future<YearActivity> loadYearActivity(
  PracticeHistoryStore store,
  int year, {
  DateTime? now,
}) async {
  final reads = await store.cardReadsSince(DateTime(year));
  return computeYearActivity(reads, year, now: now);
}

/// Pure bucketing of [reads] into [year]'s days, counting a card once per
/// day as [computeDailyActivity] does; reads outside [year] are ignored.
YearActivity computeYearActivity(
  List<(String card, DateTime at)> reads,
  int year, {
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  final inYear = [
    for (final read in reads)
      if (read.$2.year == year) read,
  ];
  final first = DateTime(year);
  final last = DateTime(year, 12, 31);
  final end = today.isBefore(last) ? today : last;
  return YearActivity(
    year: year,
    cardsByDay: _countByDay(inYear),
    daysElapsed: end.isBefore(first) ? 0 : _daysBetween(first, end) + 1,
  );
}

/// Distinct cards read on each local day that had any.
Map<DateTime, int> _countByDay(List<(String card, DateTime at)> reads) {
  final cardsByDay = <DateTime, Set<String>>{};
  for (final (card, at) in reads) {
    cardsByDay.putIfAbsent(_dateOnly(at), () => {}).add(card);
  }
  return {
    for (final MapEntry(:key, :value) in cardsByDay.entries) key: value.length,
  };
}

/// Whole calendar days from [from] to [to], both local midnights. Counted
/// in UTC so a daylight-saving change in between doesn't make a 23- or
/// 25-hour "day".
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Walks backward from [today] (or from yesterday, if today has nothing yet)
/// counting consecutive days with practice, stopping at the first gap.
int _streakEndingAt(Map<DateTime, int> countByDay, DateTime today) {
  var day = (countByDay[today] ?? 0) > 0 ? today : _dayBefore(today);

  var streak = 0;
  while ((countByDay[day] ?? 0) > 0) {
    streak++;
    day = _dayBefore(day);
  }
  return streak;
}

/// The longest run of consecutive days in [countByDay] with cards read,
/// anywhere in the map. Walks each day forward from the earliest, so the
/// cost is the span of the window, not the number of reads.
int _longestStreak(Map<DateTime, int> countByDay) {
  final days =
      countByDay.entries.where((e) => e.value > 0).map((e) => e.key).toList()
        ..sort();
  var best = 0;
  var run = 0;
  DateTime? previous;
  for (final day in days) {
    run = previous != null && _daysBetween(previous, day) == 1 ? run + 1 : 1;
    if (run > best) best = run;
    previous = day;
  }
  return best;
}

/// Midnight of [date]'s own local day -- strips the time so day-difference
/// arithmetic above counts calendar days, not 24-hour windows.
DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// Midnight of the local day before [day] -- by calendar, not by 24 hours,
/// which across a daylight-saving change would land on 23:00 or 01:00.
DateTime _dayBefore(DateTime day) => DateTime(day.year, day.month, day.day - 1);

/// Midnight of the Monday on or before [date]. [DateTime.weekday] is 1
/// (Monday) through 7 (Sunday), matching [DailyActivity.practicedDays]'s
/// Monday-first order.
DateTime _mondayOf(DateTime date) {
  final day = _dateOnly(date);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}
