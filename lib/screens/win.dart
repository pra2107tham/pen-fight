import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/chunky.dart';

/// The winner's ink floods the screen, per the design.
class WinScreen extends StatelessWidget {
  final String winnerName;
  final Color winnerColor;
  final bool youWon;
  final VoidCallback onRematch;

  /// Overrides the default win/lose line — used for a forfeit.
  final String? subtitle;

  const WinScreen({
    super.key,
    required this.winnerName,
    required this.winnerColor,
    required this.youWon,
    required this.onRematch,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: winnerColor,
        body: Stack(
          children: [
            Positioned(
                top: -60,
                left: -40,
                child: _blob(220, Colors.white.withValues(alpha: .12))),
            Positioned(
                top: 120,
                right: -70,
                child: _blob(200, Colors.white.withValues(alpha: .10))),
            Positioned(
                bottom: 210,
                left: 20,
                child: _blob(90, Colors.black.withValues(alpha: .10))),
            SafeArea(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height - 40),
                  child: Column(
                children: [
                  const SizedBox(height: 40),
                  Text('MATCH OVER',
                      style: PF.code(13,
                          color: Colors.white.withValues(alpha: .8), ls: 3)),
                  const SizedBox(height: 16),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: .86, end: 1),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    builder: (_, v, child) =>
                        Transform.scale(scale: v, child: child),
                    child: Text(
                      '$winnerName\nWINS',
                      textAlign: TextAlign.center,
                      style:
                          PF.marker(58, color: Colors.white, h: .88),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      subtitle ?? (youWon ? 'YOU TOOK THE DESK' : 'DESK LOST'),
                      style: PF.bold(12,
                          color: Colors.white, w: 700, ls: 1.4),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Container(
                      width: 236,
                      height: 236,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .16),
                      ),
                      child: const PenGlyph(
                          color: Colors.white,
                          length: 196,
                          thickness: 22,
                          angle: -.56),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      children: [
                        ChunkyButton(
                          onTap: onRematch,
                          background: Colors.white,
                          shadow: Colors.black.withValues(alpha: .3),
                          minHeight: 58,
                          child: Text('REMATCH, COWARD',
                              style: PF.bold(19, w: 800, ls: .8)),
                        ),
                        const SizedBox(height: 10),
                        ChunkyButton(
                          onTap: () => Navigator.of(context)
                              .popUntil((r) => r.isFirst),
                          background: Colors.transparent,
                          border: Colors.white.withValues(alpha: .8),
                          shadow: Colors.transparent,
                          borderWidth: 2,
                          shadowOffset: 0,
                          minHeight: 52,
                          radius: 14,
                          child: Text('HOME',
                              style: PF.bold(14,
                                  color: Colors.white, w: 700, ls: .8)),
                        ),
                      ],
                    ),
                  ),
                ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _blob(double size, Color c) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c));
}
