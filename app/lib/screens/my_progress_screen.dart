// The Progress tab: the streak, this week's cards against the daily goal,
// the year's activity, and the pronunciation side. No flashcard jargon -- "mature",
// "retention", "reviews" -- on screen.
//
// Every number derives from the two stores; the whole body rebuilds on
// either one's `changes` (the same way HomeScreen does) so coming back from
// a sitting shows updated numbers without a manual refresh.

import 'package:flutter/material.dart';

import '../data/daily_activity.dart';
import '../data/practice_history_scope.dart';
import '../data/progress_stats.dart';
import '../decks/deck_models.dart';
import '../decks/deck_store_scope.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import '../theme/lingo_theme.dart';
import '../widgets/activity_heatmap.dart';
import '../widgets/cards_per_day_card.dart';
import '../widgets/grade_buttons.dart';
import 'activity_screen.dart';
import 'practised_cards_screen.dart';
import 'revisit_screen.dart';

class MyProgressScreen extends StatelessWidget {
  const MyProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = PracticeHistoryScope.of(context);
    final decks = DeckStoreScope.of(context);

    return Scaffold(
      backgroundColor: LingoColors.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: ListenableBuilder(
            listenable: Listenable.merge([history.changes, decks.changes]),
            builder: (context, _) => FutureBuilder<ProgressStats>(
              future: loadProgressStats(history, decks),
              builder: (context, snapshot) {
                final stats = snapshot.data;
                if (stats == null) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _Body(stats: stats);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats});

  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(currentStreak: stats.currentStreak),
        const SizedBox(height: 20),
        _WeekCard(stats: stats),
        const SizedBox(height: 12),
        _ActivityCard(currentStreak: stats.currentStreak),
        const SizedBox(height: 12),
        _GradesCard(grades: stats.grades),
        const SizedBox(height: 12),
        _PronunciationCard(stats: stats),
      ],
    );
  }
}

/// "Progress" / "Your week" heading, and the streak pill -- the same shape
/// as the Home tab's header.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.currentStreak});

  final int currentStreak;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Progress',
                style: lingoFont(
                  size: 13,
                  weight: FontWeight.w400,
                  color: LingoColors.mutedInk,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Your week',
                style: lingoFont(size: 18, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: LingoColors.streakContainer,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 16,
                color: LingoColors.streak,
              ),
              const SizedBox(width: 6),
              Text(
                '$currentStreak day streak',
                style: lingoFont(
                  size: 14,
                  weight: FontWeight.w600,
                  color: LingoColors.streak,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// [CardsPerDayCard], with how many days met the goal and the best streak
/// under it.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.stats});

  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final daysMet = stats.cardsPerDay
        .where((n) => n >= kDefaultDailyGoalTarget)
        .length;
    return CardsPerDayCard(
      cardsPerDay: stats.cardsPerDay,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Fact(
            icon: Icons.flag_rounded,
            text: 'Goal of $kDefaultDailyGoalTarget met $daysMet of 7 days',
          ),
          const SizedBox(height: 6),
          _Fact(
            icon: Icons.emoji_events_rounded,
            text: 'Best streak ${stats.bestStreak}',
          ),
        ],
      ),
    );
  }
}

/// This year's practice as a heatmap (ActivityHeatmap), and under it the
/// daily average, the share of days practised, and the longest and current
/// streaks. The whole card is one tap target: it opens ActivityScreen, with
/// every number about the year.
class _ActivityCard extends StatefulWidget {
  const _ActivityCard({required this.currentStreak});

  final int currentStreak;

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  /// Loaded once, and again only when the parent rebuilds -- which it does
  /// on new practice.
  Future<YearActivity>? _activity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(_ActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() => _activity = loadYearActivity(
    PracticeHistoryScope.of(context),
    DateTime.now().year,
  );

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return FutureBuilder<YearActivity>(
      future: _activity,
      builder: (context, snapshot) {
        final activity = snapshot.data;
        return DecoratedBox(
          decoration: lingoCardDecoration(),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: activity == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ActivityScreen(
                          activity: activity,
                          currentStreak: widget.currentStreak,
                        ),
                      ),
                    ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: _Heading('ACTIVITY')),
                        Text(
                          '${today.year}',
                          style: lingoFont(size: 14, weight: FontWeight.w700),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: LingoColors.navInactive,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (activity == null)
                      const SizedBox(
                        height: 80,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      ActivityHeatmap(activity: activity, today: today),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: LingoColors.ringTrack),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _Stat(
                            value: '${activity.dailyAverage}',
                            label: 'cards a day on average',
                          ),
                          _Stat(
                            value: '${activity.daysLearnedPercent}%',
                            label: 'of days practised',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _Stat(
                            value: _days(activity.longestStreak),
                            label: 'longest streak',
                          ),
                          _Stat(
                            value: _days(widget.currentStreak),
                            label: 'current streak',
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _days(int n) => '$n ${n == 1 ? 'day' : 'days'}';
}

/// A number over its label, half a row wide.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: lingoFont(size: 20, weight: FontWeight.w800)),
          Text(
            label,
            style: lingoFont(
              size: 12,
              weight: FontWeight.w500,
              color: LingoColors.mutedInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Every grade the learner has given: "10 Wrong · 20 Partial · 100
/// Perfect", in the grade buttons' own colours and icons, over one bar
/// split in the same proportions. Tapping it lists the cards
/// (PractisedCardsScreen); tapping one grade lists the cards given it.
class _GradesCard extends StatelessWidget {
  const _GradesCard({required this.grades});

  final Map<Grade, int> grades;

  static const Map<Grade, ScoreBand> _band = {
    Grade.difficult: ScoreBand.red,
    Grade.medium: ScoreBand.orange,
    Grade.easy: ScoreBand.green,
  };

  /// The cards behind the numbers: all of them, or those given [grade].
  void _open(BuildContext context, Grade? grade) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PractisedCardsScreen(grade: grade)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = grades.values.fold(0, (a, b) => a + b);
    return DecoratedBox(
      decoration: lingoCardDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () => _open(context, null),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: _Heading('CARDS PRACTISED')),
                    Text(
                      '$total total',
                      style: lingoFont(
                        size: 12,
                        weight: FontWeight.w600,
                        color: LingoColors.mutedInk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final grade in Grade.values)
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _open(context, grade),
                          child: _GradeCount(
                            grade: grade,
                            count: grades[grade] ?? 0,
                            color: colorForBand(theme, _band[grade]!),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 8,
                    child: total == 0
                        ? ColoredBox(color: LingoColors.ringTrack)
                        : Row(
                            children: [
                              for (final grade in Grade.values)
                                if ((grades[grade] ?? 0) > 0)
                                  Expanded(
                                    flex: grades[grade]!,
                                    child: ColoredBox(
                                      color: colorForBand(theme, _band[grade]!),
                                    ),
                                  ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GradeCount extends StatelessWidget {
  const _GradeCount({
    required this.grade,
    required this.count,
    required this.color,
  });

  final Grade grade;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(GradeButtons.iconFor(grade), size: 18, color: color),
        ),
        const SizedBox(height: 8),
        Text('$count', style: lingoFont(size: 24, weight: FontWeight.w800)),
        Text(
          GradeButtons.labelFor(grade),
          style: lingoFont(
            size: 12,
            weight: FontWeight.w600,
            color: LingoColors.mutedInk,
          ),
        ),
      ],
    );
  }
}

/// A small icon and a line of text, for the facts under the chart.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: LingoColors.indigo),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: lingoFont(
              size: 13,
              weight: FontWeight.w600,
              color: LingoColors.mutedInk,
            ),
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: lingoFont(
      size: 11,
      weight: FontWeight.w700,
      color: color ?? LingoColors.mutedInk,
      letterSpacing: 1.2,
    ),
  );
}

/// The pronunciation mode's numbers: average accuracy, and words mastered
/// out of everything scored, with a ring showing that share. Tapping it
/// opens the mispronounced words and sentences (RevisitScreen).
class _PronunciationCard extends StatelessWidget {
  const _PronunciationCard({required this.stats});

  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final percent = stats.wordsScored == 0
        ? 0
        : ((stats.wordsGood / stats.wordsScored) * 100).clamp(0, 100).round();
    final faded = Colors.white.withValues(alpha: 0.75);
    return Material(
      color: LingoColors.accentCard,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const RevisitScreen())),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Heading('PRONUNCIATION', color: faded),
                    const SizedBox(height: 12),
                    Text(
                      stats.pronunciationAttempts == 0
                          ? '–'
                          : '${stats.pronunciationAccuracy.round()}%',
                      style: lingoFont(
                        size: 36,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'average accuracy · ${stats.wordsGood} words mastered',
                      style: lingoFont(
                        size: 12,
                        weight: FontWeight.w500,
                        color: faded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox.square(
                dimension: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 72,
                      child: CircularProgressIndicator(
                        value: percent / 100,
                        strokeWidth: 5,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: lingoFont(
                        size: 15,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
