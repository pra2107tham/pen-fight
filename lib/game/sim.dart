/// Deterministic pen-fight physics. No Flutter imports on purpose — this runs
/// identically on web and native, which is what the netcode rests on.
///
/// Model: each pen is a solid capsule — a segment with radius. Collisions are
/// resolved at the closest points between two pens' spines, so the tip, the
/// middle and a crossed shaft all connect and transfer force differently.
/// Pens slide under table friction, spin about their centre of mass, and die
/// if their centre leaves the table or their ink hits zero.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const double kDt = 1 / 60;
const double kFriction = 2.55; // velocity decay, per second
const double kRestitution = 0.34; // pen-on-pen bounce
const double kStopSpeed = 13.0; // below this a pen snaps to rest
const double kHitSpeed = 55.0; // minimum closing speed that counts as a strike
const double kSpin = 2.2; // angular decay, per second
const double kKineticFriction = 88.0; // constant scrub, units/s^2
const double kStopSpin = 0.12; // below this the pen stops rotating
const double kImpactDamping = 0.62; // speed kept after a collision
const int kMaxTicks = 900; // 15s hard stop; settle() must terminate

/// The most pens one table supports.
const int kMaxPlayers = 5;

/// Pen body dimensions, matching the design's 150x16 rounded bars.
const double kPenLength = 132.0;
const double kPenRadius = 8.0;

/// Impulse applied at 100% power.
const double kMaxImpulse = 2750.0;

/// How much forward drive a full-tip flick trades away for spin (0..1).
const double kTipTranslationLoss = 0.45;

// Precomputed once rather than per pen per tick. The physics is unchanged —
// these are the same values the old inline expressions produced, hoisted out
// of loops that run millions of times during an AI search.
const double _kStopSpeedSq = kStopSpeed * kStopSpeed;
const double _kMinDist = kPenRadius * 2;
const double _kMinDistSq = _kMinDist * _kMinDist;
const double _kHalfSpine = (kPenLength / 2) - kPenRadius;
const double _kKineticDrop = kKineticFriction * kDt;
final double _kVelDecay = math.max(0.0, 1 - kFriction * kDt);
final double _kSpinDecay = math.max(0.0, 1 - kSpin * kDt);

class Vec2 {
  final double x, y;
  const Vec2(this.x, this.y);
  static const zero = Vec2(0, 0);

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);
  double get length => math.sqrt(x * x + y * y);

  /// Avoids the square root when only a comparison is needed. Every hot loop
  /// in here goes through this rather than [length].
  double get lengthSquared => x * x + y * y;

  double dot(Vec2 o) => x * o.x + y * o.y;
  Vec2 get normalized {
    final l = length;
    return l < 1e-9 ? zero : Vec2(x / l, y / l);
  }

  @override
  String toString() => '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

class Pen {
  Vec2 pos;
  Vec2 vel;
  double angle; // radians
  double spin;
  double ink; // 0..100
  bool alive;
  final int seat;

  Pen({
    required this.seat,
    required this.pos,
    this.vel = Vec2.zero,
    this.angle = 0,
    this.spin = 0,
    this.ink = 100,
    this.alive = true,
  });

  bool get resting =>
      vel.lengthSquared < _kStopSpeedSq && spin.abs() < kStopSpin;

  /// The pen's core segment — the capsule spine, tip to tip.
  (Vec2, Vec2) get segment {
    final half = (kPenLength / 2) - kPenRadius;
    final d = Vec2(math.cos(angle) * half, math.sin(angle) * half);
    return (pos - d, pos + d);
  }

  /// Kept for compatibility with anything reading the pen's two ends.
  (Vec2, Vec2) get nubs => segment;

  /// Moment of inertia for a rod of length [kPenLength] about its centre,
  /// normalized to unit mass. Drives how much a hit spins the pen.
  static const double inertia = (kPenLength * kPenLength) / 12;

  /// Velocity of the point [at] on this body, including its rotation.
  Vec2 velocityAt(Vec2 at) {
    final r = at - pos;
    return vel + Vec2(-spin * r.y, spin * r.x);
  }

  Map<String, dynamic> toJson() => {
        'seat': seat,
        'x': pos.x,
        'y': pos.y,
        'vx': vel.x,
        'vy': vel.y,
        'a': angle,
        'ink': ink,
        'alive': alive,
      };

  factory Pen.fromJson(Map<String, dynamic> j) => Pen(
        seat: (j['seat'] as num).toInt(),
        pos: Vec2((j['x'] as num).toDouble(), (j['y'] as num).toDouble()),
        vel: Vec2((j['vx'] as num).toDouble(), (j['vy'] as num).toDouble()),
        angle: (j['a'] as num).toDouble(),
        ink: (j['ink'] as num).toDouble(),
        alive: j['alive'] as bool,
      );

  Pen copy() => Pen(
        seat: seat,
        pos: pos,
        vel: vel,
        angle: angle,
        spin: spin,
        ink: ink,
        alive: alive,
      );
}

// Output slots for [_closestPoints]. Returning a record here would allocate
// two Vec2 and a tuple on every pen pair on every tick — tens of millions of
// objects during one Ruthless search. Dart statics are per-isolate and the sim
// is single-threaded, so plain fields are safe and free.
double _cax = 0, _cay = 0, _cbx = 0, _cby = 0;

// Per-tick scratch for each pen's spine half-vector. A pen's angle is fixed
// for the whole collision pass, so the trig is worth doing once per pen
// instead of once per pair; its position is not, and is re-read live below.
Float64List _spineX = Float64List(kMaxPlayers);
Float64List _spineY = Float64List(kMaxPlayers);

/// Closest points between segments p1..p2 and q1..q2, written to [_cax]..[_cby].
///
/// Allocation-free twin of [closestPointsBetweenSegments]; the arithmetic is
/// line-for-line identical, so both agree bit for bit.
void _closestPoints(double p1x, double p1y, double p2x, double p2y,
    double q1x, double q1y, double q2x, double q2y) {
  final d1x = p2x - p1x, d1y = p2y - p1y;
  final d2x = q2x - q1x, d2y = q2y - q1y;
  final rx = p1x - q1x, ry = p1y - q1y;
  final a = d1x * d1x + d1y * d1y;
  final e = d2x * d2x + d2y * d2y;
  final f = d2x * rx + d2y * ry;

  double s, t;
  if (a <= 1e-9 && e <= 1e-9) {
    _cax = p1x;
    _cay = p1y;
    _cbx = q1x;
    _cby = q1y;
    return;
  }
  if (a <= 1e-9) {
    s = 0;
    t = (f / e).clamp(0.0, 1.0);
  } else {
    final c = d1x * rx + d1y * ry;
    if (e <= 1e-9) {
      t = 0;
      s = (-c / a).clamp(0.0, 1.0);
    } else {
      final b = d1x * d2x + d1y * d2y;
      final denom = a * e - b * b;
      s = denom != 0 ? ((b * f - c * e) / denom).clamp(0.0, 1.0) : 0.0;
      t = (b * s + f) / e;
      if (t < 0) {
        t = 0;
        s = (-c / a).clamp(0.0, 1.0);
      } else if (t > 1) {
        t = 1;
        s = ((b - c) / a).clamp(0.0, 1.0);
      }
    }
  }
  _cax = p1x + d1x * s;
  _cay = p1y + d1y * s;
  _cbx = q1x + d2x * t;
  _cby = q1y + d2y * t;
}

/// Closest points between segments p1..p2 and q1..q2. This is what makes the
/// whole pen solid: contact is found wherever the bodies are actually nearest,
/// tip-to-tip, tip-to-middle or crossed, not just at the ends.
(Vec2, Vec2) closestPointsBetweenSegments(
    Vec2 p1, Vec2 p2, Vec2 q1, Vec2 q2) {
  _closestPoints(p1.x, p1.y, p2.x, p2.y, q1.x, q1.y, q2.x, q2.y);
  return (Vec2(_cax, _cay), Vec2(_cbx, _cby));
}

/// Result of one settled flick — enough for the UI to narrate what happened.
class FlickResult {
  final int ticks;
  final List<int> hits; // seats that took a hit
  final List<int> knockedOff; // seats that left the table
  final Vec2? lastImpact; // where to draw the splat

  const FlickResult(this.ticks, this.hits, this.knockedOff, this.lastImpact);
}

class Sim {
  final List<Pen> pens;
  final double width, height;

  Sim({required this.pens, required this.width, required this.height});

  /// Standard 2-player opening layout. Deterministic — no RNG.
  factory Sim.duel({required double width, required double height}) =>
      Sim.table(width: width, height: height, players: 2);

  /// Opening layout for [players] pens (2–5), spaced evenly around a ring so
  /// nobody starts with a positional advantage. Deterministic — no RNG, so
  /// every client deals the identical table.
  factory Sim.table({
    required double width,
    required double height,
    required int players,
  }) {
    final count = players.clamp(2, kMaxPlayers);

    // Two players face off across the table; three or more sit around it.
    if (count == 2) {
      return Sim(
        width: width,
        height: height,
        pens: [
          Pen(seat: 0, pos: Vec2(width * 0.38, height * 0.74), angle: -0.30),
          Pen(seat: 1, pos: Vec2(width * 0.62, height * 0.26), angle: 0.34),
        ],
      );
    }

    final cx = width / 2, cy = height / 2;
    // Far enough out to leave room to manoeuvre, well inside the danger band.
    final radius = math.min(width, height) * 0.31;

    return Sim(
      width: width,
      height: height,
      pens: [
        for (var i = 0; i < count; i++)
          () {
            // Seat 0 at the bottom (nearest the player holding the device),
            // the rest anticlockwise from there.
            final theta = (math.pi / 2) + (i * 2 * math.pi / count);
            return Pen(
              seat: i,
              pos: Vec2(cx + math.cos(theta) * radius,
                  cy + math.sin(theta) * radius),
              // Lie tangentially, so no pen starts aimed at anyone.
              angle: theta + math.pi / 2,
            );
          }(),
      ],
    );
  }

  Pen? seat(int s) {
    for (final p in pens) {
      if (p.seat == s) return p;
    }
    return null;
  }

  List<Pen> get living => pens.where((p) => p.alive).toList();

  /// How many pens are still on the table, without building a list for it.
  int get livingCount {
    var n = 0;
    for (var i = 0; i < pens.length; i++) {
      if (pens[i].alive) n++;
    }
    return n;
  }

  /// Apply a flick impulse to one pen. [dir] need not be normalized;
  /// [power] is 0..1.
  ///
  /// [grab] is where on the pen the player pulled from, in table coordinates.
  /// The impulse is applied at that exact point, so flicking a tip spins the
  /// pen while flicking the middle drives it straight — the same off-centre
  /// physics that governs pen-on-pen contact. Omit it for a centred push.
  void applyFlick(int seatIndex, Vec2 dir, double power, {Vec2? grab}) {
    final p = seat(seatIndex);
    if (p == null || !p.alive) return;
    final n = dir.normalized;
    final mag = kMaxImpulse * power.clamp(0.0, 1.0);

    // Clamp the grab onto the pen's own spine: you can only push the pen
    // where the pen actually is.
    Vec2 r = Vec2.zero;
    if (grab != null) {
      final (s1, s2) = p.segment;
      final (onPen, _) = closestPointsBetweenSegments(s1, s2, grab, grab);
      r = onPen - p.pos;
    }

    // Linear response falls off as the grab moves out to the tip — a tip
    // flick spends its energy rotating rather than translating.
    final lever = (r.length / (kPenLength / 2)).clamp(0.0, 1.0);
    p.vel = p.vel + n * (mag * (1.0 - kTipTranslationLoss * lever));

    // Torque from applying the impulse off the centre of mass.
    final rCrossN = r.x * n.y - r.y * n.x;
    p.spin += rCrossN * mag / Pen.inertia;
  }

  /// Advance one fixed tick. Returns seats hit this tick.
  ///
  /// Written against raw doubles rather than [Vec2] values. The arithmetic is
  /// unchanged — same operations in the same order, so the result is bit for
  /// bit what the vector form produced — but a tick no longer allocates a few
  /// hundred short-lived objects. That matters because the AI runs this loop
  /// millions of times per turn, and on the web those allocations were the
  /// single biggest cost in the game.
  List<int> step({List<int>? knockedOff, void Function(Vec2)? onImpact}) {
    List<int>? hits;
    final n = pens.length;

    for (var i = 0; i < n; i++) {
      final p = pens[i];
      if (!p.alive) continue;

      var vx = p.vel.x, vy = p.vel.y;
      p.pos = Vec2(p.pos.x + vx * kDt, p.pos.y + vy * kDt);
      p.angle += p.spin * kDt;

      // Table friction: viscous drag plus a constant kinetic term, so pens
      // scrub off speed and actually come to a stop like they do on a desk
      // instead of gliding forever on an exponential tail.
      vx *= _kVelDecay;
      vy *= _kVelDecay;
      final speed = math.sqrt(vx * vx + vy * vy);
      if (speed > 0) {
        if (speed <= _kKineticDrop) {
          vx = 0;
          vy = 0;
        } else {
          final scale = (speed - _kKineticDrop) / speed;
          vx *= scale;
          vy *= scale;
        }
      }

      // Spin scrubs against the felt too, and faster than sliding does.
      p.spin *= _kSpinDecay;

      p.vel = (vx * vx + vy * vy) < _kStopSpeedSq ? Vec2.zero : Vec2(vx, vy);
      if (p.spin.abs() < kStopSpin) p.spin = 0;
    }

    // Angles do not change during the collision pass, so each pen's spine
    // half-vector is computed once here rather than once per pair. Positions
    // do change — an earlier pair can shove a pen — so those are re-read
    // inside the loop, exactly as the vector version did.
    if (_spineX.length < n) {
      _spineX = Float64List(n);
      _spineY = Float64List(n);
    }
    for (var i = 0; i < n; i++) {
      final angle = pens[i].angle;
      _spineX[i] = math.cos(angle) * _kHalfSpine;
      _spineY[i] = math.sin(angle) * _kHalfSpine;
    }

    // Pen-vs-pen: the whole body is solid. Contact is resolved at the closest
    // points between the two capsule spines, so a tip, the middle, or a
    // crossed shaft all connect — and each transfers different force.
    for (var i = 0; i < n; i++) {
      final a = pens[i];
      final aHalfX = _spineX[i], aHalfY = _spineY[i];

      for (var j = i + 1; j < n; j++) {
        final b = pens[j];
        // Re-checked per pair: a pen can be knocked out by an earlier pair
        // in this same tick.
        if (!a.alive || !b.alive) continue;

        final aPos = a.pos, bPos = b.pos;
        final bHalfX = _spineX[j], bHalfY = _spineY[j];

        _closestPoints(
          aPos.x - aHalfX, aPos.y - aHalfY,
          aPos.x + aHalfX, aPos.y + aHalfY,
          bPos.x - bHalfX, bPos.y - bHalfY,
          bPos.x + bHalfX, bPos.y + bHalfY,
        );
        final cax = _cax, cay = _cay, cbx = _cbx, cby = _cby;

        final dx = cbx - cax, dy = cby - cay;
        final distSq = dx * dx + dy * dy;
        // Far apart is overwhelmingly the common case, so reject on the
        // squared distance and never pay for the square root.
        if (distSq >= _kMinDistSq) continue;
        final dist = math.sqrt(distSq);

        // Degenerate exact-overlap (pens crossed dead centre): push apart
        // perpendicular to A's shaft — along it would just slide B through.
        final double nx, ny;
        if (dist < 1e-9) {
          nx = -math.sin(a.angle);
          ny = math.cos(a.angle);
        } else {
          nx = dx / dist;
          ny = dy / dist;
        }

        // Always resolve overlap, even at rest — otherwise pens that stop
        // touching stay embedded and grind against each other forever.
        final overlap = (_kMinDist - dist) / 2;
        a.pos = Vec2(a.pos.x - nx * overlap, a.pos.y - ny * overlap);
        b.pos = Vec2(b.pos.x + nx * overlap, b.pos.y + ny * overlap);

        // Lever arms from each centre of mass to the contact point.
        final rax = cax - a.pos.x, ray = cay - a.pos.y;
        final rbx = cbx - b.pos.x, rby = cby - b.pos.y;

        // Closing speed at the contact point, including spin.
        final avx = a.vel.x, avy = a.vel.y;
        final bvx = b.vel.x, bvy = b.vel.y;
        final relX = (bvx + -b.spin * rby) - (avx + -a.spin * ray);
        final relY = (bvy + b.spin * rbx) - (avy + a.spin * rax);
        final sep = relX * nx + relY * ny;
        if (sep > 0) continue; // already separating

        final victim =
            (avx * avx + avy * avy) > (bvx * bvx + bvy * bvy) ? b : a;

        // Rigid-body impulse with rotation. rn is the lever arm's leverage:
        // a hit near the centre resists (small rn) and drives the pen
        // forward; a hit near a tip spends its energy spinning instead.
        final raCrossN = rax * ny - ray * nx;
        final rbCrossN = rbx * ny - rby * nx;
        final invMassSum = 2.0 +
            (raCrossN * raCrossN) / Pen.inertia +
            (rbCrossN * rbCrossN) / Pen.inertia;
        final impulse = -(1 + kRestitution) * sep / invMassSum;

        // Contact scrubs speed off both pens. Without this the striker keeps
        // sailing after a hit and skates off the far edge, which made almost
        // every exchange a mutual-destruction race.
        a.vel = Vec2((avx - nx * impulse) * kImpactDamping,
            (avy - ny * impulse) * kImpactDamping);
        b.vel = Vec2((bvx + nx * impulse) * kImpactDamping,
            (bvy + ny * impulse) * kImpactDamping);
        a.spin -= raCrossN * impulse / Pen.inertia;
        b.spin += rbCrossN * impulse / Pen.inertia;

        // Only a real strike does damage. Without this, two pens resting
        // in contact bill ink on every tick.
        if (sep.abs() < kHitSpeed) continue;

        onImpact?.call(Vec2((cax + cbx) / 2, (cay + cby) / 2));

        // Each unordered pen pair is visited exactly once per tick, so the
        // loop itself is what bills damage only once per pair.
        //
        // Damage follows the momentum actually delivered, not raw closing
        // speed. The impulse already accounts for leverage, so a tip clip —
        // which spends its energy spinning the pen instead of shoving it —
        // transfers less and therefore hurts less, exactly as it should.
        final dmg = (impulse * 0.055).clamp(3.0, 30.0);
        victim.ink = math.max(0, victim.ink - dmg);
        hits ??= <int>[];
        if (!hits.contains(victim.seat)) hits.add(victim.seat);
        if (victim.ink <= 0) victim.alive = false;
      }
    }

    // Off the table = instant KO, per the design's flag #1.
    for (var i = 0; i < n; i++) {
      final p = pens[i];
      if (!p.alive) continue;
      final x = p.pos.x, y = p.pos.y;
      if (x < 0 || x > width || y < 0 || y > height) {
        p.alive = false;
        p.vel = Vec2.zero;
        knockedOff?.add(p.seat);
      }
    }

    // The overwhelming majority of ticks land no hit at all; handing back a
    // shared empty list keeps them allocation-free.
    return hits ?? const <int>[];
  }

  /// Step until everything is at rest. Bounded so it always terminates.
  FlickResult settle() {
    final hits = <int>[];
    final off = <int>[];
    Vec2? lastImpact;
    var ticks = 0;

    while (ticks < kMaxTicks) {
      final h = step(knockedOff: off, onImpact: (v) => lastImpact = v);
      for (final s in h) {
        if (!hits.contains(s)) hits.add(s);
      }
      ticks++;
      if (allRested) break;
    }
    return FlickResult(ticks, hits, off, lastImpact);
  }

  /// True once every pen left on the table has stopped. A plain loop rather
  /// than `pens.every(...)`, which allocated a closure on every tick.
  bool get allRested {
    for (var i = 0; i < pens.length; i++) {
      final p = pens[i];
      if (p.alive && !p.resting) return false;
    }
    return true;
  }

  /// True once at most one pen is left standing.
  bool get isOver => livingCount <= 1;

  int? get winnerSeat {
    Pen? sole;
    for (var i = 0; i < pens.length; i++) {
      final p = pens[i];
      if (!p.alive) continue;
      if (sole != null) return null;
      sole = p;
    }
    return sole?.seat;
  }

  /// The next seat that still has a pen on the table, rotating upward from
  /// [current]. Returns [current] if nobody else is left.
  int nextLivingSeat(int current) {
    for (var step = 1; step <= pens.length; step++) {
      final candidate = (current + step) % pens.length;
      final p = seat(candidate);
      if (p != null && p.alive) return candidate;
    }
    return current;
  }

  Sim copy() => Sim(
        width: width,
        height: height,
        pens: List<Pen>.generate(pens.length, (i) => pens[i].copy(),
            growable: false),
      );

  List<Map<String, dynamic>> snapshot() =>
      pens.map((p) => p.toJson()).toList(growable: false);

  void restore(List<dynamic> snap) {
    for (final raw in snap) {
      final j = Map<String, dynamic>.from(raw as Map);
      final p = seat((j['seat'] as num).toInt());
      if (p == null) continue;
      p.pos = Vec2((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
      p.vel = Vec2((j['vx'] as num).toDouble(), (j['vy'] as num).toDouble());
      p.angle = (j['a'] as num).toDouble();
      p.ink = (j['ink'] as num).toDouble();
      p.alive = j['alive'] as bool;
      p.spin = 0;
    }
  }
}
