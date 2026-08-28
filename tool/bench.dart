// Throughput benchmark for the physics sim and the AI search. Not part of the
// test suite.
//
//   dart run tool/bench.dart                     # native
//   dart compile js -O2 -o /tmp/b.js tool/bench.dart && node /tmp/b.js
//
// The second form is the one that matters: the game ships as JavaScript, and
// allocation costs far more there than it does on the VM.
// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:pen_fight/game/ai.dart';
import 'package:pen_fight/game/sim.dart';

const double kTableW = 820;
const double kTableH = 880;

void main() {
  // Warm the JIT.
  for (var i = 0; i < 50; i++) {
    (Sim.table(width: kTableW, height: kTableH, players: 5)
          ..applyFlick(0, Vec2(1, .3), .9, grab: Vec2(400, 600)))
        .settle();
  }

  for (final players in [2, 5]) {
    final rng = math.Random(7);
    var ticks = 0;
    final sw = Stopwatch()..start();
    for (var i = 0; i < 2000; i++) {
      final s = Sim.table(width: kTableW, height: kTableH, players: players)
        ..applyFlick(0, Vec2(rng.nextDouble() - .5, rng.nextDouble() - .5), .95,
            grab: Vec2(400, 600));
      ticks += s.settle().ticks;
    }
    sw.stop();
    print('settle x2000 ($players pens): ${sw.elapsedMilliseconds}ms  '
        '($ticks ticks, ${(ticks / sw.elapsedMicroseconds * 1e6).round()} ticks/s)');
  }

  for (final d in Difficulty.values) {
    final sim = Sim.table(width: kTableW, height: kTableH, players: 2);
    final bot = PenAi(d, seed: 3);
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      bot.chooseShot(sim, 1);
    }
    sw.stop();
    print('chooseShot ${d.label}: ${(sw.elapsedMilliseconds / 10).toStringAsFixed(1)}ms per turn');
  }
}
