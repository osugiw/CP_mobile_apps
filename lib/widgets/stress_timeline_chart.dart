import 'package:flutter/material.dart';
import '../models/stress_reading.dart';

/// A small line chart of stress score (0 to 100) across the day.
///
/// Drawn with CustomPainter so no chart package is needed.
/// Tap anywhere on the chart to select the nearest reading.
class StressTimelineChart extends StatelessWidget {
  final List<StressReading> readings;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;
  final double height;

  const StressTimelineChart({
    super.key,
    required this.readings,
    required this.onSelect,
    this.selectedIndex,
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No readings yet today')),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geo = _ChartGeometry(
            Size(constraints.maxWidth, height),
            readings.first.timestamp,
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onSelect(geo.nearestIndex(readings, d.localPosition)),
            onHorizontalDragUpdate: (d) =>
                onSelect(geo.nearestIndex(readings, d.localPosition)),
            child: CustomPaint(
              painter: _StressChartPainter(readings, selectedIndex, geo),
            ),
          );
        },
      ),
    );
  }
}

/// Converts (time, score) into pixel positions. Shared by the painter and the
/// tap handler so a tap always matches what is drawn.
class _ChartGeometry {
  static const double left = 30, right = 10, top = 10, bottom = 22;
  static const int startHour = 6, endHour = 22; // visible window: 6 AM to 10 PM

  final Size size;
  final DateTime start;
  final DateTime end;

  _ChartGeometry(this.size, DateTime day)
      : start = DateTime(day.year, day.month, day.day, startHour),
        end = DateTime(day.year, day.month, day.day, endHour);

  double get plotWidth => size.width - left - right;
  double get plotHeight => size.height - top - bottom;

  double xFor(DateTime t) {
    final total = end.difference(start).inMinutes;
    final pos = t.difference(start).inMinutes.clamp(0, total);
    return left + plotWidth * pos / total;
  }

  double yFor(num score) => top + plotHeight * (1 - score.clamp(0, 100) / 100);

  Offset pointFor(StressReading r) => Offset(xFor(r.timestamp), yFor(r.score));

  int nearestIndex(List<StressReading> readings, Offset tap) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < readings.length; i++) {
      final dx = (pointFor(readings[i]).dx - tap.dx).abs();
      if (dx < bestDist) {
        bestDist = dx;
        best = i;
      }
    }
    return best;
  }
}

class _StressChartPainter extends CustomPainter {
  final List<StressReading> readings;
  final int? selected;
  final _ChartGeometry geo;

  _StressChartPainter(this.readings, this.selected, this.geo);

  static const Color logoBlue = Color(0xFF1A335D);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBands(canvas);
    _drawAxes(canvas);
    _drawLine(canvas);
    _drawPoints(canvas);
  }

  // Soft colored zones so the level is readable without looking at numbers.
  void _drawBands(Canvas canvas) {
    void band(double from, double to, Color c) {
      final rect = Rect.fromLTRB(
        _ChartGeometry.left,
        geo.yFor(to),
        geo.size.width - _ChartGeometry.right,
        geo.yFor(from),
      );
      canvas.drawRect(rect, Paint()..color = c.withValues(alpha: 0.12));
    }

    band(0, 40, StressLevel.calm.color);
    band(40, 70, StressLevel.elevated.color);
    band(70, 100, StressLevel.high.color);
  }

  void _drawAxes(Canvas canvas) {
    final grid = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    // Y axis: threshold lines and labels.
    for (final v in [0, 40, 70, 100]) {
      final y = geo.yFor(v);
      canvas.drawLine(
        Offset(_ChartGeometry.left, y),
        Offset(geo.size.width - _ChartGeometry.right, y),
        grid,
      );
      _text(canvas, '$v', Offset(_ChartGeometry.left - 6, y), alignRight: true);
    }

    // X axis: every 4 hours.
    for (var h = _ChartGeometry.startHour; h <= _ChartGeometry.endHour; h += 4) {
      final t = DateTime(geo.start.year, geo.start.month, geo.start.day, h);
      final label = h == 12 ? '12p' : (h < 12 ? '${h}a' : '${h - 12}p');
      _text(canvas, label, Offset(geo.xFor(t), geo.size.height - 8), center: true);
    }
  }

  void _drawLine(Canvas canvas) {
    final path = Path();
    for (var i = 0; i < readings.length; i++) {
      final p = geo.pointFor(readings[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = logoBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawPoints(Canvas canvas) {
    for (var i = 0; i < readings.length; i++) {
      final r = readings[i];
      final p = geo.pointFor(r);
      final isSel = i == selected;

      if (isSel) {
        // Vertical guide line to the time axis.
        canvas.drawLine(
          Offset(p.dx, _ChartGeometry.top),
          Offset(p.dx, geo.size.height - _ChartGeometry.bottom),
          Paint()
            ..color = logoBlue.withValues(alpha: 0.35)
            ..strokeWidth = 1,
        );
      }

      canvas.drawCircle(p, isSel ? 7 : 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(p, isSel ? 5.5 : 3.5, Paint()..color = r.level.color);
      if (isSel) {
        canvas.drawCircle(
          p,
          7,
          Paint()
            ..color = logoBlue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  void _text(Canvas canvas, String s, Offset at,
      {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: const TextStyle(fontSize: 10, color: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _StressChartPainter old) =>
      old.selected != selected || old.readings != readings || old.geo.size != geo.size;
}
