import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../theme.dart';

/// Ruled notebook paper: 27px lines, a margin rule at x=44, faint dot grid.
/// Recipe matches the design's repeating-linear-gradient exactly.
///
/// The paper sits behind everything and never changes, so it is painted into
/// its own layer. Without that boundary it shared a layer with the game, and
/// every animation frame re-recorded the whole background along with it.
class PaperBackground extends StatelessWidget {
  final Widget child;
  const PaperBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: PF.paper,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _PaperPainter(
                      MediaQuery.devicePixelRatioOf(context)),
                  isComplex: true,
                  willChange: false,
                ),
              ),
            ),
            child,
          ],
        ),
      );
}

/// The dot grid, rendered once into a small repeating tile.
///
/// Drawn dot by dot it was one `drawCircle` every 3px in both directions —
/// roughly a quarter of a million draw calls to cover a desktop window, paid
/// again on every repaint. As a tiled shader it is a single `drawRect`, and
/// the tile is built once per device pixel ratio for the life of the app.
class _DotTile {
  static ui.Image? _image;
  static ui.Shader? _shader;
  static double _forDpr = 0;

  /// Dots every 3 logical pixels, as the design specifies. 4x4 of them per
  /// tile keeps the repeat count down without making the texture large.
  static const double _spacing = 3;
  static const int _perSide = 4;

  static ui.Shader shaderFor(double dpr) {
    final cached = _shader;
    if (cached != null && _forDpr == dpr) return cached;

    const extent = _spacing * _perSide;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(dpr);

    final dot = Paint()..color = PF.black.withValues(alpha: .05);
    for (var i = 0; i < _perSide; i++) {
      for (var j = 0; j < _perSide; j++) {
        // Centred in its cell so no dot is clipped at the tile seam.
        canvas.drawCircle(
          Offset(i * _spacing + _spacing / 2, j * _spacing + _spacing / 2),
          .5,
          dot,
        );
      }
    }

    final side = (extent * dpr).round();
    final image = recorder.endRecording().toImageSync(side, side);
    final shader = ImageShader(
      image,
      TileMode.repeated,
      TileMode.repeated,
      // The tile is rendered at device resolution; scale it back to logical
      // pixels so it stays crisp on high-DPI screens.
      Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1).storage,
    );

    _image?.dispose();
    _shader?.dispose();
    _image = image;
    _shader = shader;
    _forDpr = dpr;
    return shader;
  }
}

class _PaperPainter extends CustomPainter {
  final double dpr;
  const _PaperPainter(this.dpr);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..shader = _DotTile.shaderFor(dpr));

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
  }

  @override
  bool shouldRepaint(covariant _PaperPainter old) => old.dpr != dpr;
}

/// Grid paper used inside the table card.
class GridPaperPainter extends CustomPainter {
  final double cell;
  const GridPaperPainter({this.cell = 26});

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

  // Walking the path metrics and extracting a sub-path per dash costs a few
  // hundred Path allocations. The outline only depends on the size, so the
  // dashes are built once and then just re-stroked when the colour changes.
  Size? _builtFor;
  Path? _dashes;

  Path _dashesFor(Size size) {
    final cached = _dashes;
    if (cached != null && _builtFor == size) return cached;

    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    final path = Path();
    for (final metric in outline.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        path.addPath(
            metric.extractPath(d, (d + dash).clamp(0, metric.length)),
            Offset.zero);
        d += dash + gap;
      }
    }

    _dashes = path;
    _builtFor = size;
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _dashesFor(size),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedPainter o) {
    // Carry the built outline across repaints — the widget rebuilds a fresh
    // painter each time, and only the colour ever actually changes.
    _dashes = o._dashes;
    _builtFor = o._builtFor;
    return o.color != color ||
        o.radius != radius ||
        o.dash != dash ||
        o.gap != gap ||
        o.strokeWidth != strokeWidth;
  }
}
