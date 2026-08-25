import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_fight/game/sim.dart';
import 'package:pen_fight/screens/battle.dart';
import 'package:pen_fight/widgets/chunky.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the contact ring is drawn on the pen, not beside it',
      (t) async {
    // Regression: the pen was drawn with Transform.scale, which keeps the
    // child's original layout box. The painted pen sat well right of where
    // Positioned placed it, so the ring floated off the pen entirely.
    await t.pumpWidget(const MaterialApp(
        home: BattleScreen(names: ['BLUE', 'RED'])));
    await t.pumpAndSettle();

    final st = t.state<State<BattleScreen>>(find.byType(BattleScreen));
    final pen = (st as dynamic).debugActingPen as Pen;
    final contact = (st as dynamic).debugContactPoint as Vec2;

    // The strike point must lie on the pen's own spine.
    final (s1, s2) = pen.segment;
    final (onPen, _) =
        closestPointsBetweenSegments(s1, s2, contact, contact);
    expect((contact - onPen).length, lessThan(1.0),
        reason: 'the contact point must be on the pen');

    // Sweeping the slider keeps it on the pen at every position.
    for (final v in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      (st as dynamic).debugSetContact(v);
      await t.pump();

      final c = (st as dynamic).debugContactPoint as Vec2;
      final p = (st as dynamic).debugActingPen as Pen;
      final (a, b) = p.segment;
      final (near, _) = closestPointsBetweenSegments(a, b, c, c);

      expect((c - near).length, lessThan(1.0),
          reason: 'contact $v drifted off the pen');
    }
  });

  testWidgets('the drawn pen is centred on the pen position', (t) async {
    // This is the property the bug broke: Transform.scale kept the child's
    // original layout box, so the PAINTED pen sat far from the coordinate
    // Positioned used — and the ring, positioned correctly, floated off it.
    await t.pumpWidget(const MaterialApp(
        home: BattleScreen(names: ['BLUE', 'RED'])));
    await t.pumpAndSettle();

    final st = t.state<State<BattleScreen>>(find.byType(BattleScreen));
    final pen = (st as dynamic).debugActingPen as Pen;
    final contact = (st as dynamic).debugContactPoint as Vec2;

    final table = t.getRect(find.byKey(kTableKey));
    final scale = math.min(table.width / kTableW, table.height / kTableH);

    // Where the pen's own rendered box actually lands on screen.
    final glyphBoxes = find.byType(PenGlyph).evaluate().map((e) {
      final ro = e.renderObject as RenderBox;
      final tl = ro.localToGlobal(Offset.zero);
      return Rect.fromLTWH(tl.dx, tl.dy, ro.size.width, ro.size.height);
    }).toList();

    // The acting pen's centre, in the same screen space.
    final penCentreOnScreen = Offset(
      table.left + (table.width - kTableW * scale) / 2 + pen.pos.x * scale,
      table.top + (table.height - kTableH * scale) / 2 + pen.pos.y * scale,
    );

    // One of the drawn pens must be centred there, within a pen width.
    final tolerance = kPenRadius * 2 * scale + 4;
    final closest = glyphBoxes
        .map((b) => (b.center - penCentreOnScreen).distance)
        .reduce(math.min);

    expect(closest, lessThan(tolerance),
        reason: 'the painted pen must sit where its position says it does');

    // And the contact ring shares that space.
    expect((contact - pen.pos).length, lessThan(kPenLength / 2));
  });
}
