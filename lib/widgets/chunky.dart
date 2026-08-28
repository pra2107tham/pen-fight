import 'package:flutter/material.dart';
import '../theme.dart';

/// The design's press behaviour: the button translates into its own shadow.
/// `transform:translate(3px,3px); box-shadow:1px 1px` on active.
class ChunkyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color background, border, shadow;
  final double radius, minHeight, borderWidth, shadowOffset;
  final EdgeInsets padding;

  const ChunkyButton({
    super.key,
    required this.child,
    this.onTap,
    this.background = Colors.white,
    this.border = PF.black,
    this.shadow = PF.black,
    this.radius = 16,
    this.minHeight = 44,
    this.borderWidth = 2.5,
    this.shadowOffset = 4,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
  });

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final press = _down && enabled ? widget.shadowOffset - 1 : 0.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          transform: Matrix4.translationValues(press, press, 0),
          constraints: BoxConstraints(minHeight: widget.minHeight),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.background,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: widget.border, width: widget.borderWidth),
            boxShadow: [
              BoxShadow(
                color: widget.shadow,
                offset: Offset(widget.shadowOffset - press,
                    widget.shadowOffset - press),
                blurRadius: 0,
              )
            ],
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}

/// Paints one pen centred on the canvas origin, lying along +x.
///
/// The table draws every pen straight onto one canvas rather than as a widget
/// each, so this is the single definition of what a pen looks like — the two
/// call sites can never drift apart.
void paintPen(
  Canvas canvas, {
  required Color color,
  required double length,
  required double thickness,
  bool danger = false,
}) {
  final body = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: length, height: thickness),
    Radius.circular(thickness / 2),
  );

  if (danger) {
    // Matches BoxShadow(color: red .55, blurRadius: 12, spreadRadius: 3).
    canvas.drawRRect(
      body.inflate(3),
      Paint()
        ..color = PF.red.withValues(alpha: .55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _dangerSigma),
    );
  } else {
    // The design's solid offset shadow — never blurred.
    canvas.drawRRect(
        body.shift(const Offset(0, 3)), Paint()..color = const Color(0x2E14161A));
  }

  canvas.drawRRect(body, Paint()..color = color);

  // Nib: a black triangle just past the tip.
  final nibLeft = length / 2 - thickness * .18;
  final nibTop = -thickness * .37;
  final nibW = thickness * .88, nibH = thickness * .75;
  canvas.drawPath(
    Path()
      ..moveTo(nibLeft, nibTop)
      ..lineTo(nibLeft + nibW, nibTop + nibH / 2)
      ..lineTo(nibLeft, nibTop + nibH)
      ..close(),
    Paint()..color = PF.black,
  );

  // Grip highlight.
  canvas.drawRect(
    Rect.fromLTWH(length * .26 - length / 2, -thickness / 2, thickness * 1.2,
        thickness),
    Paint()..color = Colors.white.withValues(alpha: .32),
  );
}

/// Flutter converts a BoxShadow's blur radius to a sigma this way; matching it
/// keeps the danger glow identical to the widget version it replaced.
const double _dangerSigma = 12 * 0.57735 + 0.5;

/// A drawn pen — the design renders these as rounded bars with a nib triangle
/// and a highlight band. Used on the home screen and on the win screen.
class PenGlyph extends StatelessWidget {
  final Color color;
  final double length, thickness, angle;
  final bool danger;

  const PenGlyph({
    super.key,
    required this.color,
    this.length = 150,
    this.thickness = 16,
    this.angle = 0,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: angle,
        child: CustomPaint(
          size: Size(length, thickness),
          painter: _PenGlyphPainter(color, length, thickness, danger),
        ),
      );
}

class _PenGlyphPainter extends CustomPainter {
  final Color color;
  final double length, thickness;
  final bool danger;

  const _PenGlyphPainter(this.color, this.length, this.thickness, this.danger);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    paintPen(canvas,
        color: color, length: length, thickness: thickness, danger: danger);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PenGlyphPainter o) =>
      o.color != color ||
      o.length != length ||
      o.thickness != thickness ||
      o.danger != danger;
}
