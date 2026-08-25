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

/// A drawn pen — the design renders these as rounded bars with a nib triangle
/// and a highlight band. Used on the home screen and on the table.
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
        child: SizedBox(
          width: length,
          height: thickness,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(thickness / 2),
                  boxShadow: danger
                      ? [
                          BoxShadow(
                              color: PF.red.withValues(alpha: .55),
                              blurRadius: 12,
                              spreadRadius: 3)
                        ]
                      : [
                          const BoxShadow(
                              color: Color(0x2E14161A),
                              offset: Offset(0, 3),
                              blurRadius: 0)
                        ],
                ),
              ),
              // Nib
              Positioned(
                right: -thickness * .7,
                top: thickness * .13,
                child: ClipPath(
                  clipper: _NibClipper(),
                  child: Container(
                    width: thickness * .88,
                    height: thickness * .75,
                    color: PF.black,
                  ),
                ),
              ),
              // Grip highlight
              Positioned(
                left: length * .26,
                top: 0,
                child: Container(
                  width: thickness * 1.2,
                  height: thickness,
                  color: Colors.white.withValues(alpha: .32),
                ),
              ),
            ],
          ),
        ),
      );
}

class _NibClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, s.height / 2)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}
