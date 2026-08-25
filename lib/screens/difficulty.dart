import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/ai.dart';
import '../theme.dart';
import '../widgets/chunky.dart';
import '../widgets/paper.dart';
import 'battle.dart';

/// Pick who you are up against. Mirrors the design's difficulty board:
/// the ink motif escalates from a single dot to a jagged splat on black.
class DifficultyScreen extends StatelessWidget {
  const DifficultyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PaperBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                      child: Row(
                        children: [
                          ChunkyButton(
                            onTap: () => Navigator.of(context).pop(),
                            minHeight: 44,
                            radius: 12,
                            borderWidth: 2,
                            shadowOffset: 0,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            child: Text('‹', style: PF.bold(20, w: 700)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Pick your victim',
                                    style: PF.marker(26)),
                                const SizedBox(height: 5),
                                Text('The bot picks its angle in 0.2s.',
                                    style: PF.bold(12,
                                        w: 500,
                                        color: PF.black
                                            .withValues(alpha: .6))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        children: [
                          for (final d in Difficulty.values) ...[
                            _DifficultyCard(
                              difficulty: d,
                              onTap: () =>
                                  Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => BattleScreen(
                                    ai: d,
                                    names: ['YOU', d.label],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _DifficultyCard extends StatelessWidget {
  final Difficulty difficulty;
  final VoidCallback onTap;

  const _DifficultyCard({required this.difficulty, required this.onTap});

  bool get _dark => difficulty == Difficulty.brutal;

  Color get _accent => switch (difficulty) {
        Difficulty.easy => PF.blue,
        Difficulty.hard => PF.orange,
        Difficulty.brutal => PF.red,
      };

  @override
  Widget build(BuildContext context) => ChunkyButton(
        onTap: onTap,
        background: _dark ? PF.black : Colors.white,
        shadow: _dark ? PF.red : PF.black.withValues(alpha: .3),
        borderWidth: difficulty == Difficulty.easy ? 2 : 2.5,
        radius: 18,
        minHeight: 112,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            _InkMotif(difficulty: difficulty, accent: _accent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(difficulty.label,
                      style: PF.bold(
                        difficulty == Difficulty.brutal ? 24 : 21,
                        w: 800,
                        ls: .4,
                        color: _dark ? Colors.white : PF.black,
                      )),
                  const SizedBox(height: 6),
                  Text(
                    difficulty.blurb,
                    style: PF.bold(12.5,
                        w: 500,
                        h: 1.35,
                        color: _dark
                            ? Colors.white.withValues(alpha: .72)
                            : PF.black.withValues(alpha: .65)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(difficulty.stars, style: PF.code(11, color: _accent)),
          ],
        ),
      );
}

/// One dot → a splash → a jagged splat, escalating with difficulty.
class _InkMotif extends StatelessWidget {
  final Difficulty difficulty;
  final Color accent;

  const _InkMotif({required this.difficulty, required this.accent});

  @override
  Widget build(BuildContext context) {
    switch (difficulty) {
      case Difficulty.easy:
        return Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0xFFEAF0FF)),
          child: Container(
            width: 20,
            height: 20,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: accent),
          ),
        );

      case Difficulty.hard:
        return Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0xFFFFF1E6)),
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 26,
                  height: 26,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: accent),
                ),
              ),
              Positioned(
                top: 8,
                right: 10,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: .7)),
                ),
              ),
              Positioned(
                bottom: 10,
                left: 9,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: .6)),
                ),
              ),
            ],
          ),
        );

      case Difficulty.brutal:
        return SizedBox(
          width: 68,
          height: 68,
          child: CustomPaint(painter: _SplatPainter(accent)),
        );
    }
  }
}

class _SplatPainter extends CustomPainter {
  final Color color;
  _SplatPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color;

    // A ten-point star, matching the design's jagged splat.
    final path = Path();
    const points = 10;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? 19.0 : 8.0;
      final a = (i * 3.14159) / points - 1.5708;
      final p = c + Offset(r * _cos(a), r * _sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);

    canvas.drawCircle(c + const Offset(20, -22), 6,
        Paint()..color = color.withValues(alpha: .9));
    canvas.drawCircle(c + const Offset(-24, 20), 4.5,
        Paint()..color = color.withValues(alpha: .8));
    canvas.drawCircle(c + const Offset(22, 16), 3,
        Paint()..color = color.withValues(alpha: .7));
  }

  double _cos(double a) => math.cos(a);
  double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(covariant _SplatPainter o) => o.color != color;
}
