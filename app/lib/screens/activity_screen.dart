import 'package:flutter/material.dart';

import '../data/daily_activity.dart';
import '../theme/lingo_theme.dart';
import '../widgets/activity_heatmap.dart';
import '../widgets/mode_badge.dart';

/// The Progress tab's Activity card opened up: this year's heatmap with its
/// key, every number about the year, and the year month by month.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({
    required this.activity,
    required this.currentStreak,
    super.key,
  });

  final YearActivity activity;
  final int currentStreak;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final best = activity.bestDay;
    final goalDays = activity.cardsByDay.values
        .where((cards) => cards >= kDefaultDailyGoalTarget)
        .length;
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: const ModeBadge(label: 'ACTIVITY'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: lingoCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: _Heading('CARDS PER DAY')),
                      Text(
                        '${activity.year}',
                        style: lingoFont(size: 14, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ActivityHeatmap(activity: activity, today: today),
                  const SizedBox(height: 12),
                  const _Key(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: lingoCardDecoration(),
              child: Column(
                children: [
                  _StatRow(
                    left: _Stat(
                      value: '${activity.totalCards}',
                      label: 'cards this year',
                    ),
                    right: _Stat(
                      value: '${activity.daysPracticed}',
                      label: 'of ${activity.daysElapsed} days practised',
                    ),
                  ),
                  _StatRow(
                    left: _Stat(
                      value: '${activity.dailyAverage}',
                      label: 'cards a day on average',
                    ),
                    right: _Stat(
                      value: '${activity.daysLearnedPercent}%',
                      label: 'of days practised',
                    ),
                  ),
                  _StatRow(
                    left: _Stat(
                      value: _days(activity.longestStreak),
                      label: 'longest streak',
                    ),
                    right: _Stat(
                      value: _days(currentStreak),
                      label: 'current streak',
                    ),
                  ),
                  _StatRow(
                    left: _Stat(
                      value: _days(goalDays),
                      label: 'met the goal of $kDefaultDailyGoalTarget',
                    ),
                    right: _Stat(
                      value: best == null ? '–' : '${best.value}',
                      label: best == null
                          ? 'best day'
                          : 'best day, ${_weekdays[best.key.weekday - 1]} '
                                '${best.key.day} '
                                '${kMonthNames[best.key.month - 1]}',
                    ),
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _MonthsCard(
              activity: activity,
              // Months still ahead this year are left out.
              shown: activity.year < today.year ? 12 : today.month,
            ),
          ],
        ),
      ),
    );
  }

  static String _days(int n) => '$n ${n == 1 ? 'day' : 'days'}';
}

/// What the shades mean: none, then the four steps toward the daily goal.
class _Key extends StatelessWidget {
  const _Key();

  @override
  Widget build(BuildContext context) {
    final style = lingoFont(
      size: 11,
      weight: FontWeight.w600,
      color: LingoColors.mutedInk,
    );
    Widget square(Color color) => Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Row(
      children: [
        Text('None', style: style),
        const SizedBox(width: 4),
        square(LingoColors.ringTrack),
        for (var step = 1; step <= 4; step++)
          square(
            Color.lerp(
              LingoColors.indigoContainer,
              LingoColors.indigo,
              step / 4,
            )!,
          ),
        const SizedBox(width: 4),
        Expanded(
          child: Text('$kDefaultDailyGoalTarget+ cards', style: style),
        ),
      ],
    );
  }
}

/// The year month by month: cards, with a bar against the busiest month,
/// and days practised.
class _MonthsCard extends StatelessWidget {
  const _MonthsCard({required this.activity, required this.shown});

  final YearActivity activity;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final months = activity.months.take(shown).toList();
    final most = months.fold(0, (m, month) => month.cards > m ? month.cards : m);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: lingoCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Heading('BY MONTH'),
          const SizedBox(height: 12),
          for (final (i, month) in months.indexed.toList().reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      kMonthNames[i],
                      style: lingoFont(size: 13, weight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: most == 0 ? 0 : month.cards / most,
                        minHeight: 8,
                        backgroundColor: LingoColors.ringTrack,
                        color: LingoColors.indigo,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 108,
                    child: Text(
                      '${month.cards} cards · ${month.days}d',
                      textAlign: TextAlign.right,
                      style: lingoFont(
                        size: 12,
                        weight: FontWeight.w600,
                        color: LingoColors.mutedInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.left, required this.right, this.last = false});

  final Widget left;
  final Widget right;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    ),
  );
}

/// A number over its label.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: lingoFont(size: 22, weight: FontWeight.w800)),
      Text(
        label,
        style: lingoFont(
          size: 12,
          weight: FontWeight.w500,
          color: LingoColors.mutedInk,
        ),
      ),
    ],
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: lingoFont(
      size: 11,
      weight: FontWeight.w700,
      color: LingoColors.mutedInk,
      letterSpacing: 1.2,
    ),
  );
}
