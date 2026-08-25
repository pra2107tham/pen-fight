import 'package:flutter/material.dart';
import '../theme.dart';

/// Ruled notebook paper: 27px lines, a margin rule at x=44, faint dot grid.
/// Recipe matches the design's repeating-linear-gradient exactly.
class PaperBackground extends StatelessWidget {
  final Widget child;
  const PaperBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        color: PF.paper,
        child: CustomPaint(
          painter: _PaperPainter(),
          child: child,
        ),
      );
}

class _PaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = PF.rule
      ..strokeWidth = 1.2;
    for (double y = 27; y < size.height; y += 28.2) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    canvas.drawLine(
      const Offset(44, 0),
      Offset(44, size.height),
      Paint()
        ..color = PF.margin.withValues(alpha: .85)
        ..strokeWidth = 1.5,
    );

    final dot = Paint()..color = PF.black.withValues(alpha: .05);
    for (double y = 0; y < size.height; y += 3) {
      for (double x = 0; x < size.width; x += 3) {
        canvas.drawCircle(Offset(x, y), .5, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Grid paper used inside the table card.
class GridPaperPainter extends CustomPainter {
  final double cell;
  GridPaperPainter({this.cell = 26});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = PF.black.withValues(alpha: .05)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Dashed rounded rectangle — the design uses these for the pad and insets.
class DashedRect extends StatelessWidget {
  final double radius, gap, dash, strokeWidth;
  final Color color;
  final Widget? child;

  const DashedRect({
    super.key,
    this.radius = 20,
    this.gap = 5,
    this.dash = 7,
    this.strokeWidth = 2,
    this.color = PF.black,
    this.child,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashedPainter(radius, gap, dash, strokeWidth, color),
        child: child,
      );
}

class _DashedPainter extends CustomPainter {
  final double radius, gap, dash, strokeWidth;
  final Color color;
  _DashedPainter(this.radius, this.gap, this.dash, this.strokeWidth, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, (d + dash).clamp(0, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter o) => o.color != color;
}
