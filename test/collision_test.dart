import 'package:flutter_test/flutter_test.dart';
import 'package:pen_fight/game/sim.dart';

/// Two pens placed deliberately, so the contact point is the only variable.
Sim rig({required double targetOffsetX, double targetAngle = 0}) => Sim(
      width: 340,
      height: 352,
      pens: [
        // Striker: vertical, below, aimed straight up. These are deliberate
        // fixed coordinates, not the match opening — the point is to control
        // exactly where contact lands.
        Pen(seat: 0, pos: const Vec2(170, 250), angle: 1.5708),
        // Target: horizontal bar above. Shifting it sideways changes whether
        // the striker meets its middle or its tip.
        Pen(
          seat: 1,
          pos: Vec2(170 + targetOffsetX, 150),
          angle: targetAngle,
        ),
      ],
    );

void main() {
  _grabTests();

  test('the middle of a pen is solid, not just its ends', () {
    // The striker runs into the centre of a broadside pen. Under the old
    // two-nub model this passed straight through.
    final s = rig(targetOffsetX: 0);
    s.applyFlick(0, const Vec2(0, -1), 0.8);
    final r = s.settle();

    expect(r.hits, contains(1),
        reason: 'a hit on the shaft must register');
    expect(s.seat(1)!.ink, lessThan(100));
  });

  test('a centre hit drives the target further than a tip clip', () {
    final centre = rig(targetOffsetX: 0);
    centre.applyFlick(0, const Vec2(0, -1), 0.8);
    centre.settle();
    final centreTravel = (centre.seat(1)!.pos - const Vec2(170, 150)).length;

    // Same shot, but the target is offset so only its tip is in the way.
    final tip = rig(targetOffsetX: 56);
    tip.applyFlick(0, const Vec2(0, -1), 0.8);
    tip.settle();
    final tipTravel = (tip.seat(1)!.pos - const Vec2(226, 150)).length;

    expect(centreTravel, greaterThan(tipTravel),
        reason: 'a clean centre hit should transfer more push');
  });

  test('a tip hit imparts more spin than a centre hit', () {
    final centre = rig(targetOffsetX: 0);
    centre.applyFlick(0, const Vec2(0, -1), 0.8);
    var centreSpin = 0.0;
    for (var i = 0; i < 40; i++) {
      centre.step();
      centreSpin = centre.seat(1)!.spin.abs() > centreSpin
          ? centre.seat(1)!.spin.abs()
          : centreSpin;
    }

    final tip = rig(targetOffsetX: 56);
    tip.applyFlick(0, const Vec2(0, -1), 0.8);
    var tipSpin = 0.0;
    for (var i = 0; i < 40; i++) {
      tip.step();
      tipSpin =
          tip.seat(1)!.spin.abs() > tipSpin ? tip.seat(1)!.spin.abs() : tipSpin;
    }

    expect(tipSpin, greaterThan(centreSpin),
        reason: 'off-centre contact should spin the pen, not just shove it');
  });

  test('the first impact hurts more when it lands on the centre', () {
    // Compares the FIRST contact only. Over a full settle a tip clip can spin
    // the pen back for a second hit, so cumulative ink is not the right
    // measure of how good a single strike was.
    double firstHit(double offset) {
      final s = rig(targetOffsetX: offset);
      s.applyFlick(0, const Vec2(0, -1), 0.45);
      for (var i = 0; i < 300; i++) {
        s.step();
        if (s.seat(1)!.ink < 100) return 100 - s.seat(1)!.ink;
      }
      return 0;
    }

    // Offset far enough that contact is clearly out near the tip, but the
    // shot still connects.
    expect(firstHit(0), greaterThan(firstHit(56)),
        reason: 'a square centre strike should out-damage a tip clip');
  });

  test('table friction brings pens to a full stop', () {
    final s = rig(targetOffsetX: 999); // target far away, no collision
    s.applyFlick(0, const Vec2(0, -1), 0.5);
    s.settle();
    expect(s.seat(0)!.vel.length, 0);
    expect(s.seat(0)!.spin, 0);
  });

  test('pens crossed dead centre push apart instead of sticking', () {
    final s = Sim(
      width: 340,
      height: 352,
      pens: [
        Pen(seat: 0, pos: const Vec2(170, 176), angle: 0),
        Pen(seat: 1, pos: const Vec2(170, 176), angle: 1.5708), // exact cross
      ],
    );

    // They start perfectly coincident — the degenerate case. A few ticks of
    // separation is enough to prove they are being driven apart, before
    // friction stops them again somewhere in contact.
    for (var i = 0; i < 6; i++) {
      s.step();
    }

    final gap = (s.seat(1)!.pos - s.seat(0)!.pos).length;
    expect(gap, greaterThan(kPenRadius * 2),
        reason: 'coincident pens must resolve, not stay embedded');
  });
}

/// A lone pen on an empty table, so only the flick itself is under test.
Sim solo() => Sim(
      width: 340,
      height: 352,
      pens: [Pen(seat: 0, pos: const Vec2(170, 176), angle: 0)],
    );

void _grabTests() {
  test('flicking a tip spins the pen; flicking the centre does not', () {
    final centre = solo();
    final p = centre.seat(0)!;
    centre.applyFlick(0, const Vec2(0, -1), 0.8, grab: p.pos);

    final tip = solo();
    final t = tip.seat(0)!;
    final (_, tipEnd) = t.segment;
    tip.applyFlick(0, const Vec2(0, -1), 0.8, grab: tipEnd);

    expect(centre.seat(0)!.spin.abs(), lessThan(0.01),
        reason: 'a dead-centre pull should be pure translation');
    expect(tip.seat(0)!.spin.abs(), greaterThan(1.0),
        reason: 'pulling from the tip must impart real rotation');
  });

  test('a centre flick travels further than the same flick from the tip', () {
    final centre = solo();
    centre.applyFlick(0, const Vec2(0, -1), 0.8,
        grab: centre.seat(0)!.pos);
    final centreStart = centre.seat(0)!.pos;
    centre.settle();
    final centreTravel = (centre.seat(0)!.pos - centreStart).length;

    final tip = solo();
    final (_, tipEnd) = tip.seat(0)!.segment;
    tip.applyFlick(0, const Vec2(0, -1), 0.8, grab: tipEnd);
    final tipStart = tip.seat(0)!.pos;
    tip.settle();
    final tipTravel = (tip.seat(0)!.pos - tipStart).length;

    expect(centreTravel, greaterThan(tipTravel),
        reason: 'a tip flick trades forward drive for spin');
  });

  test('opposite tips spin opposite ways', () {
    final a = solo();
    final (headA, tailA) = a.seat(0)!.segment;
    a.applyFlick(0, const Vec2(0, -1), 0.8, grab: headA);

    final b = solo();
    b.applyFlick(0, const Vec2(0, -1), 0.8, grab: tailA);

    expect(a.seat(0)!.spin * b.seat(0)!.spin, lessThan(0),
        reason: 'grabbing each end must rotate the pen in opposite senses');
  });

  test('the grab point is part of the synced input', () {
    // Both clients must land on the same state from the same three values.
    final (_, tipEnd) = solo().seat(0)!.segment;
    final sender = solo()
      ..applyFlick(0, const Vec2(0.2, -1), 0.9, grab: tipEnd);
    sender.settle();

    final receiver = solo()
      ..applyFlick(0, const Vec2(0.2, -1), 0.9, grab: tipEnd);
    receiver.settle();

    expect(receiver.snapshot().toString(), sender.snapshot().toString());
  });
}
