// A year of practice as a grid of days: one column per week, Monday at the
// top, shaded by how many cards the day had against the daily goal -- the
// Progress tab's "Activity" card and its details page. Display only: drawn
// with one CustomPainter rather than ~370 widgets, with nothing to tap, and
// sized to the width it is given, so the whole year fits on a phone without
// scrolling.

import 'package:flutter/material.dart';

import '../data/daily_activity.dart';
import '../theme/lingo_theme.dart';

const List<String> kMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({
    required this.activity,
    required this.today,
    this.goal = kDefaultDailyGoalTarget,
    super.key,
  });

  final YearActivity activity;
  final DateTime today;

  /// Cards that make a day fully shaded.
  final int goal;

  static const double _gap = 2;
  static const double _labelHeight = 14;

  @override
  Widget build(BuildContext context) {
    final grid = _YearGrid(activity.year);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell =
            (constraints.maxWidth - _gap * (grid.columns - 1)) / grid.columns;
        final height = _labelHeight + 7 * cell + 6 * _gap;
        return RepaintBoundary(
          child: CustomPaint(
            size: Size(constraints.maxWidth, height),
            painter: _HeatmapPainter(
              grid: grid,
              activity: activity,
              today: DateTime(today.year, today.month, today.day),
              goal: goal,
              cell: cell,
              gap: _gap,
              labelHeight: _labelHeight,
              empty: LingoColors.ringTrack,
              low: LingoColors.indigoContainer,
              high: LingoColors.indigo,
              mutedInk: LingoColors.mutedInk,
            ),
          ),
        );
      },
    );
  }
}

/// Where each day of [year] sits: column 0 is the week holding 1 January,
/// row 0 is Monday.
class _YearGrid {
  factory _YearGrid(int year) {
    final firstMonday = DateTime(year, 1, 1 - (DateTime(year).weekday - 1));
    final weeks = _days(firstMonday, DateTime(year, 12, 31)) ~/ 7 + 1;
    return _YearGrid._(year, firstMonday, weeks);
  }

  _YearGrid._(this.year, this.firstMonday, this.columns);

  final int year;
  final DateTime firstMonday;
  final int columns;

  /// Calendar days from [from] to [to], counted in UTC so a daylight-saving
  /// change in between doesn't shorten one.
  static int _days(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  DateTime dateAt(int column, int row) => DateTime(
    firstMonday.year,
    firstMonday.month,
    firstMonday.day + column * 7 + row,
  );

  /// The day at [column], [row], or null outside [year].
  DateTime? dayAt(int column, int row) {
    if (column < 0 || column >= columns || row < 0 || row > 6) return null;
    final day = dateAt(column, row);
    return day.year == year ? day : null;
  }

  int columnOf(DateTime day) => _days(firstMonday, day) ~/ 7;
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.grid,
    required this.activity,
    required this.today,
    required this.goal,
    required this.cell,
    required this.gap,
    required this.labelHeight,
    required this.empty,
    required this.low,
    required this.high,
    required this.mutedInk,
  });

  final _YearGrid grid;
  final YearActivity activity;
  final DateTime today;
  final int goal;
  final double cell;
  final double gap;
  final double labelHeight;
  final Color empty;
  final Color low;
  final Color high;
  final Color mutedInk;

  /// Four steps toward [goal]: a quarter, half, three quarters, and full
  /// once the goal is met.
  Color _shade(int cards) {
    if (cards == 0) return empty;
    final step = (4 * cards / goal).ceil().clamp(1, 4);
    return Color.lerp(low, high, step / 4)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (var month = 1; month <= 12; month++) {
      final label = TextPainter(
        text: TextSpan(
          text: kMonthNames[month - 1],
          style: lingoFont(size: 9, weight: FontWeight.w600, color: mutedInk),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = grid.columnOf(DateTime(grid.year, month)) * (cell + gap);
      if (x + label.width <= size.width) label.paint(canvas, Offset(x, 0));
    }

    final radius = Radius.circular(cell * 0.25);
    final fill = Paint();
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var column = 0; column < grid.columns; column++) {
      for (var row = 0; row < 7; row++) {
        final day = grid.dayAt(column, row);
        if (day == null) continue;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            column * (cell + gap),
            labelHeight + row * (cell + gap),
            cell,
            cell,
          ),
          radius,
        );
        fill.color = day.isAfter(today)
            ? empty.withValues(alpha: 0.4)
            : _shade(activity.cardsOn(day));
        canvas.drawRRect(rect, fill);
        if (day == today) canvas.drawRRect(rect, outline..color = high);
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.activity != activity ||
      old.today != today ||
      old.cell != cell ||
      old.high != high;
}
