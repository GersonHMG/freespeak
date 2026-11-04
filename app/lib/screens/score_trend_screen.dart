import 'package:flutter/material.dart';

import '../data/grade_trend.dart';
import '../decks/deck_models.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import '../theme/lingo_theme.dart';
import '../widgets/mode_badge.dart';
import '../widgets/score_trend_chart.dart';

ScoreBand _bandOf(int score) =>
    ScoreThresholds.standard.bandFor(score.toDouble());

const Map<Grade, ScoreBand> _gradeBand = {
  Grade.easy: ScoreBand.green,
  Grade.medium: ScoreBand.orange,
  Grade.difficult: ScoreBand.red,
};

String _windowLabel(int days) => '$days days';

/// The score over the latest window, big, with how far it moved since the
/// first window. Shared by the Progress tab's Score
/// card and [ScoreTrendScreen].
class ScoreTrendHeadline extends StatelessWidget {
  const ScoreTrendHeadline({required this.trend, super.key});

  final GradeTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = trend.latest.score;
    final color = score == null
        ? LingoColors.mutedInk
        : colorForBand(theme, _bandOf(score));
    final change = trend.change;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text.rich(
          TextSpan(
            text: score == null ? '–' : '$score',
            style: lingoFont(size: 44, weight: FontWeight.w800, color: color),
            children: [
              TextSpan(
                text: ' / 100',
                style: lingoFont(
                  size: 15,
                  weight: FontWeight.w700,
                  color: LingoColors.mutedInk,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (change != null)
                  _Pill(
                    icon: change >= 0
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    text:
                        '${change.abs()} vs first '
                        '${_windowLabel(trend.window)}',
                    color: LingoColors.tealInk,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: lingoFont(size: 12, weight: FontWeight.w700, color: color),
          ),
        ),
      ],
    ),
  );
}

/// The Progress tab's Score card: the rolling score over the last two weeks,
/// big, and its line (ScoreTrendChart). The whole card is one tap target: it opens
/// ScoreTrendScreen, with the day-by-day breakdown.
class ScoreTrendCard extends StatelessWidget {
  const ScoreTrendCard({required this.trend, super.key});

  final GradeTrend trend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: lingoCardDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: trend.isEmpty
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ScoreTrendScreen(trend: trend),
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Heading(
                        trend.isEmpty
                            ? 'SCORE'
                            : 'SCORE · LAST ${trend.window} DAYS',
                      ),
                    ),
                    if (!trend.isEmpty)
                      Icon(
                        Icons.chevron_right_rounded,
                        color: LingoColors.navInactive,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (trend.isEmpty)
                  Text(
                    'Grade a few Recall cards to see your score here.',
                    style: lingoFont(
                      size: 13,
                      weight: FontWeight.w500,
                      color: LingoColors.mutedInk,
                    ),
                  )
                else ...[
                  ScoreTrendHeadline(trend: trend),
                  const SizedBox(height: 14),
                  ScoreTrendChart(trend: trend, height: 170),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Progress tab's Score card opened up: the trend with a day picked
/// (today, until the learner taps another), what the line means, and every
/// day of the trend with its own mix of grades and score.
class ScoreTrendScreen extends StatefulWidget {
  const ScoreTrendScreen({required this.trend, super.key});

  final GradeTrend trend;

  @override
  State<ScoreTrendScreen> createState() => _ScoreTrendScreenState();
}

class _ScoreTrendScreenState extends State<ScoreTrendScreen> {
  late int _selected = widget.trend.days.length - 1;

  @override
  Widget build(BuildContext context) {
    final trend = widget.trend;
    final window = _windowLabel(trend.window);
    return Scaffold(
      backgroundColor: LingoColors.background,
      appBar: AppBar(
        backgroundColor: LingoColors.background,
        elevation: 0,
        centerTitle: true,
        title: const ModeBadge(label: 'SCORE'),
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
                  _Heading('SCORE · LAST ${window.toUpperCase()}'),
                  const SizedBox(height: 8),
                  ScoreTrendHeadline(trend: trend),
                  const SizedBox(height: 16),
                  ScoreTrendChart(
                    trend: trend,
                    selected: _selected,
                    onSelect: (i) => setState(() => _selected = i),
                  ),
                  const SizedBox(height: 10),
                  const _Legend(),
                  const SizedBox(height: 10),
                  Text(
                    'Perfect is 100, Partial 50 and Wrong 0. The line averages '
                    'every answer in the last $window, so a day with 2 answers '
                    'barely moves it and a day with 50 moves it a lot.',
                    style: lingoFont(
                      size: 12,
                      weight: FontWeight.w500,
                      color: LingoColors.mutedInk,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              decoration: lingoCardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: _Heading('DAY BY DAY'),
                  ),
                  for (var i = trend.days.length - 1; i >= 0; i--)
                    _DayRow(
                      day: trend.days[i],
                      tally: trend.tallies[i],
                      isToday: i == trend.days.length - 1,
                      selected: i == _selected,
                      onTap: () => setState(() => _selected = i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = lingoFont(
      size: 12,
      weight: FontWeight.w500,
      color: LingoColors.mutedInk,
    );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 3,
              decoration: BoxDecoration(
                color: LingoColors.teal,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text('Score', style: style),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 12,
              decoration: BoxDecoration(
                color: LingoColors.indigo.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text('Answers that day', style: style),
          ],
        ),
      ],
    );
  }
}

/// One day: its date and answer count, its grades as one split bar, and its
/// own score. A day with fewer than [kFewAnswers] answers is faded -- too
/// few to read much into.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.tally,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });

  final DateTime day;
  final GradeTally tally;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = tally.score;
    final few = tally.total < kFewAnswers;
    final total = tally.total;
    return Material(
      color: selected ? LingoColors.indigoContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isToday
                          ? 'Today'
                          : '${_weekdays[day.weekday - 1]} ${day.day} '
                                '${kMonthNames[day.month - 1]}',
                      style: lingoFont(
                        size: 13,
                        weight: FontWeight.w600,
                        color: total == 0 ? LingoColors.mutedInk : null,
                      ),
                    ),
                    Text(
                      total == 0
                          ? 'No practice'
                          : '$total ${total == 1 ? 'answer' : 'answers'}',
                      style: lingoFont(
                        size: 11,
                        weight: FontWeight.w500,
                        color: LingoColors.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: total > 0 && few ? 0.45 : 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(100),
                    child: SizedBox(
                      height: 10,
                      child: total == 0
                          ? ColoredBox(color: LingoColors.ringTrack)
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              spacing: 2,
                              children: [
                                for (final grade in Grade.values.reversed)
                                  if (tally.count(grade) > 0)
                                    Expanded(
                                      flex: tally.count(grade),
                                      child: ColoredBox(
                                        color: colorForBand(
                                          theme,
                                          _gradeBand[grade]!,
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  score == null ? '–' : '$score',
                  textAlign: TextAlign.right,
                  style: lingoFont(
                    size: 14,
                    weight: few ? FontWeight.w600 : FontWeight.w800,
                    color: score == null || few
                        ? LingoColors.mutedInk
                        : colorForBand(theme, _bandOf(score)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
