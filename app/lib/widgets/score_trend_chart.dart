// The score trend as a chart: the rolling score (GradeTrend.rollingScore) as
// one teal line over faint score-band zones, and under it a short strip of
// answers per day, so a reader can see which days carry the most weight.
// The Progress tab's Score card shows it bare; ScoreTrendScreen passes
// [onSelect] so a tap picks a day.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/grade_trend.dart';
import '../scoring/score_band.dart';
import '../scoring/score_palette.dart';
import '../theme/lingo_theme.dart';

/// Short month names, for the dates on the chart and ScoreTrendScreen's days.
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

class ScoreTrendChart extends StatelessWidget {
  const ScoreTrendChart({
    required this.trend,
    this.selected,
    this.onSelect,
    this.height = 196,
    super.key,
  });

  final GradeTrend trend;

  /// The day (index into [GradeTrend.days]) marked on the line, if any.
  final int? selected;

  /// Called with the day under a tap; null leaves the chart untappable.
  final ValueChanged<int>? onSelect;

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final painter = _ScoreTrendPainter(
      trend: trend,
      selected: selected,
      bandColor: (band) => colorForBand(theme, band),
    );
    final chart = CustomPaint(
      size: Size(double.infinity, height),
      painter: painter,
    );
    if (onSelect == null) return chart;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => onSelect!(
          painter.dayAt(details.localPosition.dx, constraints.maxWidth),
        ),
        child: chart,
      ),
    );
  }
}

class _ScoreTrendPainter extends CustomPainter {
  _ScoreTrendPainter({
    required this.trend,
    required this.selected,
    required this.bandColor,
  });

  final GradeTrend trend;
  final int? selected;
  final Color Function(ScoreBand) bandColor;

  // Plot insets: room for the score labels on the left, and under the plot
  // for the answers strip and the dates.
  static const double _left = 26, _right = 10, _top = 16;
  static const double _stripGap = 12, _stripHeight = 24, _dateRow = 18;

  int get _n => trend.days.length;

  double _x(int i, double width) {
    final w = width - _left - _right;
    return _n == 1 ? _left + w / 2 : _left + i / (_n - 1) * w;
  }

  /// The day nearest to [dx] across a chart [width] wide.
  int dayAt(double dx, double width) {
    if (_n <= 1) return 0;
    final w = width - _left - _right;
    return (((dx - _left) / w) * (_n - 1)).round().clamp(0, _n - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (trend.isEmpty) return;
    final plotBottom = size.height - _dateRow - _stripHeight - _stripGap;
    final ph = plotBottom - _top;
    double y(num score) => plotBottom - score / 100 * ph;
    double x(int i) => _x(i, size.width);
    final right = size.width - _right;

    // Faint score-band zones, at the app's own cutoffs.
    const t = ScoreThresholds.standard;
    for (final (from, to, band) in [
      (t.green, 100.0, ScoreBand.green),
      (t.orange, t.green, ScoreBand.orange),
      (0.0, t.orange, ScoreBand.red),
    ]) {
      canvas.drawRect(
        Rect.fromLTRB(_left, y(to), right, y(from)),
        Paint()..color = bandColor(band).withValues(alpha: 0.07),
      );
    }
    final grid = Paint()
      ..color = LingoColors.ringTrack
      ..strokeWidth = 1;
    for (final tick in [0, t.orange.round(), t.green.round(), 100]) {
      canvas.drawLine(Offset(_left, y(tick)), Offset(right, y(tick)), grid);
      _text(
        canvas,
        '$tick',
        Offset(_left - 6, y(tick)),
        align: _Align.rightMiddle,
      );
    }

    // The rolling score, broken wherever its whole window had no grades.
    final segments = <List<Offset>>[[]];
    for (var i = 0; i < _n; i++) {
      final score = trend.rollingScore(i);
      if (score == null) {
        if (segments.last.isNotEmpty) segments.add([]);
      } else {
        segments.last.add(Offset(x(i), y(score)));
      }
    }
    final line = Paint()
      ..color = LingoColors.teal
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          LingoColors.teal.withValues(alpha: 0.26),
          LingoColors.teal.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTRB(0, _top, size.width, plotBottom));
    for (final points in segments.where((s) => s.isNotEmpty)) {
      final path = Path()..addPolygon(points, false);
      canvas.drawPath(
        Path.from(path)
          ..lineTo(points.last.dx, plotBottom)
          ..lineTo(points.first.dx, plotBottom)
          ..close(),
        fill,
      );
      if (points.length == 1) {
        canvas.drawCircle(
          points.single,
          2.5,
          Paint()..color = LingoColors.teal,
        );
      } else {
        canvas.drawPath(path, line);
      }
    }

    // Answers per day.
    final stripTop = plotBottom + _stripGap,
        stripBottom = stripTop + _stripHeight;
    final most = trend.tallies.map((d) => d.total).fold(0, math.max);
    final barWidth = math.min(10.0, (size.width - _left - _right) / _n * 0.5);
    canvas.drawLine(
      Offset(_left, stripBottom),
      Offset(right, stripBottom),
      grid,
    );
    _text(
      canvas,
      '$most',
      Offset(_left - 6, stripTop + 4),
      align: _Align.rightMiddle,
      size: 9,
    );
    for (var i = 0; i < _n; i++) {
      final total = trend.tallies[i].total;
      if (total == 0) continue;
      final h = math.max(1.5, total / most * _stripHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x(i) - barWidth / 2, stripBottom - h, barWidth, h),
          const Radius.circular(2),
        ),
        Paint()
          ..color = LingoColors.indigo.withValues(
            alpha: i == selected || selected == null && i == _n - 1
                ? 0.9
                : 0.35,
          ),
      );
    }

    // Dates: the first day and today, and the picked day between them when
    // it has room.
    final dateY = size.height - _dateRow / 2;
    _text(
      canvas,
      _short(trend.days.first),
      Offset(x(0), dateY),
      align: _n == 1 ? _Align.center : _Align.leftMiddle,
    );
    if (_n > 1) {
      _text(
        canvas,
        'Today',
        Offset(x(_n - 1), dateY),
        align: _Align.rightMiddle,
        bold: selected == _n - 1,
      );
    }

    final sel = selected;
    if (sel == null) return;
    final sx = x(sel);
    canvas.drawLine(
      Offset(sx, _top),
      Offset(sx, stripBottom),
      Paint()
        ..color = LingoColors.ink.withValues(alpha: 0.18)
        ..strokeWidth = 1,
    );
    if (sel > 0 && sel < _n - 1 && sx - x(0) > 44 && x(_n - 1) - sx > 40) {
      _text(canvas, _short(trend.days[sel]), Offset(sx, dateY), bold: true);
    }
    final total = trend.tallies[sel].total;
    if (total > 0) {
      final h = math.max(1.5, total / most * _stripHeight);
      final nearRight = sx > right - 24;
      _text(
        canvas,
        '$total',
        Offset(
          nearRight ? sx - barWidth / 2 - 3 : sx + barWidth / 2 + 3,
          stripBottom - h + 4,
        ),
        align: nearRight ? _Align.rightMiddle : _Align.leftMiddle,
        size: 9,
        bold: true,
      );
    }
    final score = trend.rollingScore(sel);
    if (score != null) {
      final point = Offset(sx, y(score));
      canvas.drawCircle(point, 4.5, Paint()..color = LingoColors.surface);
      canvas.drawCircle(
        point,
        4.5,
        Paint()
          ..color = LingoColors.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      _text(
        canvas,
        '$score',
        Offset(sx.clamp(_left + 10, right - 10), math.max(point.dy - 14, 8)),
        size: 11,
        bold: true,
        color: LingoColors.tealInk,
      );
    }
  }

  static String _short(DateTime d) => '${d.day} ${kMonthNames[d.month - 1]}';

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    _Align align = _Align.center,
    double size = 10,
    bool bold = false,
    Color? color,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: lingoFont(
          size: size,
          weight: bold ? FontWeight.w800 : FontWeight.w500,
          color: color ?? (bold ? LingoColors.ink : LingoColors.mutedInk),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      _Align.rightMiddle => at.dx - painter.width,
      _Align.leftMiddle => at.dx,
      _Align.center => at.dx - painter.width / 2,
    };
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  /// The palette this was painted with -- LingoColors' getters change
  /// under it when night mode flips.
  final bool _dark = LingoColors.dark;

  @override
  bool shouldRepaint(_ScoreTrendPainter old) =>
      old.trend != trend || old.selected != selected || old._dark != _dark;
}

enum _Align { leftMiddle, center, rightMiddle }
