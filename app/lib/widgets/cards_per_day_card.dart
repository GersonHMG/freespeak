import 'package:flutter/material.dart';

import '../data/daily_activity.dart';
import '../theme/lingo_theme.dart';

/// This week as seven numbers: the cards practised each day, Monday first.
/// A day that met the daily goal is solid indigo, a day short of it
/// tinted, a day with none grey; days still ahead are left blank, and
/// today is marked. Home shows it bare; the Progress tab adds its facts
/// under it as [footer].
class CardsPerDayCard extends StatelessWidget {
  const CardsPerDayCard({
    required this.cardsPerDay,
    this.goalTarget = kDefaultDailyGoalTarget,
    this.footer,
    super.key,
  });

  /// Cards read on each day of this week, Monday first.
  final List<int> cardsPerDay;

  /// Cards per day for a day to count as goal met.
  final int goalTarget;

  /// Drawn under the days, below a divider.
  final Widget? footer;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final todayIndex = DateTime.now().weekday - 1;
    final cardsThisWeek = cardsPerDay.fold(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: lingoCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'CARDS PER DAY',
                    style: lingoFont(
                      size: 11,
                      weight: FontWeight.w700,
                      color: LingoColors.mutedInk,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Text(
                  '$cardsThisWeek',
                  style: lingoFont(size: 22, weight: FontWeight.w800),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'this week',
                    style: lingoFont(
                      size: 13,
                      weight: FontWeight.w600,
                      color: LingoColors.mutedInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _DayCount(
                    cards: cardsPerDay[i],
                    goalMet: cardsPerDay[i] >= goalTarget,
                    label: _labels[i],
                    isToday: i == todayIndex,
                    isAhead: i > todayIndex,
                  ),
                ),
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: LingoColors.ringTrack),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: footer,
            ),
          ],
        ],
      ),
    );
  }
}

/// One day: its count in a rounded tile, and its initial under it.
class _DayCount extends StatelessWidget {
  const _DayCount({
    required this.cards,
    required this.goalMet,
    required this.label,
    required this.isToday,
    required this.isAhead,
  });

  final int cards;
  final bool goalMet;
  final String label;
  final bool isToday;
  final bool isAhead;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color ink;
    if (isAhead) {
      fill = Colors.transparent;
      ink = LingoColors.mutedInk;
    } else if (goalMet) {
      fill = LingoColors.indigo;
      ink = Colors.white;
    } else if (cards > 0) {
      fill = LingoColors.indigoContainer;
      ink = LingoColors.indigo;
    } else {
      fill = LingoColors.ringTrack;
      ink = LingoColors.mutedInk;
    }
    return Column(
      children: [
        Container(
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(14),
            border: isToday
                ? Border.all(color: LingoColors.indigo, width: 2)
                : isAhead
                ? Border.all(color: LingoColors.ringTrack, width: 1.5)
                : null,
          ),
          child: isAhead
              ? null
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$cards',
                    style: lingoFont(
                      size: 17,
                      weight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          isToday ? 'Today' : label,
          style: lingoFont(
            size: 11,
            weight: isToday ? FontWeight.w800 : FontWeight.w600,
            color: isToday ? LingoColors.indigo : LingoColors.mutedInk,
          ),
        ),
      ],
    );
  }
}
