import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pen_fight/game/sim.dart';
import 'package:pen_fight/screens/battle.dart';

/// Screenshot tool, not a test — it asserts nothing. Lives in tool/ so it is
/// never picked up by `flutter test`, and so its teardown quirks can never be
/// mistaken for a real failure. Renders the battle screen mid-aim to a PNG:
///
///   flutter test tool/capture.dart
///
/// Writes /tmp/penfight_battle.png. The run reports a timeout at teardown
/// (the screen's AnimationController outlives the test binding); the image is
/// already written by then, so that is cosmetic.
void main() {
  testWidgets('capture battle screen', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(780, 1688);

    await t.pumpWidget(const MaterialApp(
      home: RepaintBoundary(
        child: BattleScreen(names: ['BLUE', 'RED']),
      ),
    ));
    await t.pump(const Duration(milliseconds: 32));

    // Mid-drag from the blue pen itself, so the slingshot band, aim guide
    // and power bar are all visible.
    final table = t.getRect(find.byKey(kTableKey));
    final scale = table.width / kTableW;
    final me = Sim.duel(width: kTableW, height: kTableH).seat(0)!;
    // Grab near the pen's TIP, not its centre — this is what proves the
    // pull point is being honoured.
    final (_, tipEnd) = me.segment;
    final penPt =
        table.topLeft + Offset(tipEnd.x * scale, tipEnd.y * scale);

    final g = await t.startGesture(penPt);
    await t.pump();
    await g.moveTo(penPt + const Offset(34, 120));
    await t.pump(const Duration(milliseconds: 32));

    final boundary = t.firstRenderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary));
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('/tmp/penfight_battle.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());

    // Cancel aborts the aim without taking the shot. Use a bounded pump
    // rather than pumpAndSettle — the battle screen keeps a repeating clock
    // ticking, so "settled" never arrives.
    await g.cancel();
    await t.pump(const Duration(milliseconds: 16));
    // Tear the widget tree down so the screen's AnimationController is
    // disposed before the test ends.
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  });
}
