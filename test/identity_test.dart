import 'package:flutter_test/flutter_test.dart';
import 'package:pen_fight/net/identity.dart';

void main() {
  // Deliberately NOT registering a shared_preferences mock: this reproduces
  // the real failure, where the platform channel is missing and
  // getInstance() throws MissingPluginException.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('identity still resolves when storage is unavailable', () async {
    // Regression: PlayerIdentity used to let the exception escape, which
    // killed the join flow before it ever created a room — surfacing to the
    // player as "No table with that code" for a perfectly valid code.
    final id = await PlayerIdentity.mine().timeout(const Duration(seconds: 8));

    expect(id, isNotEmpty);
    expect(id.length, greaterThan(30), reason: 'should be a uuid');
  });

  test('the id is stable within a session even without storage', () async {
    final first = await PlayerIdentity.mine();
    final second = await PlayerIdentity.mine();
    expect(second, first,
        reason: 'a rejoin in the same session must look like the same player');
  });
}
