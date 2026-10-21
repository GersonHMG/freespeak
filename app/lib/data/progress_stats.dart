// Everything the Progress tab shows, gathered in one place: the
// day-bucketed activity [loadDailyActivity] derives, the grades given
// ([DeckStore.gradeCounts]), and the pronunciation side from
// [PracticeHistoryStore.attemptSummary]. None knows about the others; this
// is the only file that needs all of them.

import '../decks/deck_models.dart';
import '../decks/deck_store.dart';
import 'daily_activity.dart';
import 'practice_history_store.dart';

class ProgressStats {
  const ProgressStats({
    required this.cardsToday,
    required this.currentStreak,
    required this.bestStreak,
    required this.cardsPerDay,
    required this.grades,
    required this.pronunciationAttempts,
    required this.pronunciationAccuracy,
    required this.wordsScored,
    required this.wordsNeedWork,
  });

  /// Cards read today, toward [kDefaultDailyGoalTarget].
  final int cardsToday;

  final int currentStreak;
  final int bestStreak;

  /// Cards read each day this week, Monday first; days still ahead are 0.
  final List<int> cardsPerDay;

  /// How many times each grade was given, ever.
  final Map<Grade, int> grades;

  int get cardsGraded => grades.values.fold(0, (a, b) => a + b);

  /// Every recorded pronunciation attempt.
  final int pronunciationAttempts;

  /// Mean sentence score across [pronunciationAttempts], 0-100.
  final double pronunciationAccuracy;

  /// Distinct words scored at least once, and of those the ones currently
  /// averaging below good.
  final int wordsScored;
  final int wordsNeedWork;

  int get wordsGood => wordsScored - wordsNeedWork;

  /// Cards read this week.
  int get cardsThisWeek => cardsPerDay.fold(0, (a, b) => a + b);
}

Future<ProgressStats> loadProgressStats(
  PracticeHistoryStore history,
  DeckStore decks,
) async {
  final summary = await history.attemptSummary();
  final activity = await loadDailyActivity(history);
  return ProgressStats(
    cardsToday: activity.cardsToday,
    currentStreak: activity.currentStreak,
    bestStreak: activity.bestStreak,
    cardsPerDay: activity.cardsPerDay,
    grades: await decks.gradeCounts(),
    pronunciationAttempts: summary.totalAttempts,
    pronunciationAccuracy: summary.averageAccuracy,
    wordsScored: summary.wordsScored,
    wordsNeedWork: await history.mispronouncedWordCount(),
  );
}
