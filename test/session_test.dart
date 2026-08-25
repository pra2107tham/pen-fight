import 'package:flutter_test/flutter_test.dart';
import 'package:pen_fight/net/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a saved session can be read back', () async {
    await ActiveSession.save('AB12', isHost: true);
    final s = await ActiveSession.load();

    expect(s, isNotNull);
    expect(s!.code, 'AB12');
    expect(s.isHost, isTrue);
    expect(s.isStale, isFalse);
  });

  test('no session means nothing to offer', () async {
    expect(await ActiveSession.load(), isNull);
  });

  test('clearing removes the rejoin offer', () async {
    await ActiveSession.save('AB12', isHost: false);
    expect(await ActiveSession.load(), isNotNull);

    await ActiveSession.clear();
    expect(await ActiveSession.load(), isNull);
  });

  test('a session older than the room TTL is not offered', () {
    // The room itself expires after 2h, so offering to rejoin past that
    // would send the player into a table that no longer exists.
    final old = ActiveSession(
      code: 'AB12',
      isHost: true,
      joinedAt: DateTime.now().subtract(const Duration(hours: 3)),
    );
    expect(old.isStale, isTrue);

    final fresh = ActiveSession(
      code: 'AB12',
      isHost: true,
      joinedAt: DateTime.now().subtract(const Duration(minutes: 20)),
    );
    expect(fresh.isStale, isFalse);
  });

  test('a stale session is dropped on read rather than surfaced', () async {
    final stale = ActiveSession(
      code: 'AB12',
      isHost: true,
      joinedAt: DateTime.now().subtract(const Duration(hours: 5)),
    );
    SharedPreferences.setMockInitialValues({
      'penfight_active_session': _encode(stale),
    });

    expect(await ActiveSession.load(), isNull);
    // And it is cleaned up, not left to be re-read every launch.
    expect(await ActiveSession.load(), isNull);
  });

  test('corrupt stored data does not crash the home screen', () async {
    SharedPreferences.setMockInitialValues({
      'penfight_active_session': 'not-json-at-all',
    });
    expect(await ActiveSession.load(), isNull);
  });

  test('a malformed code is rejected', () async {
    SharedPreferences.setMockInitialValues({
      'penfight_active_session':
          '{"code":"TOOLONG","isHost":true,"joinedAt":"'
              '${DateTime.now().toIso8601String()}"}',
    });
    expect(await ActiveSession.load(), isNull);
  });

  test('saving twice keeps only the latest table', () async {
    await ActiveSession.save('AAAA', isHost: true);
    await ActiveSession.save('BBBB', isHost: false);

    final s = await ActiveSession.load();
    expect(s!.code, 'BBBB');
    expect(s.isHost, isFalse);
  });
}

String _encode(ActiveSession s) =>
    '{"code":"${s.code}","isHost":${s.isHost},'
    '"joinedAt":"${s.joinedAt.toIso8601String()}"}';
