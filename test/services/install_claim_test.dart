/// The install id is what tells one phone from another for the one-phone rule.
library;

import 'package:chismosa/services/identity/install_claim.dart';
import 'package:chismosa/services/storage/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the install id is created once and then stays the same', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final KeyValueStore store = KeyValueStore(
      await SharedPreferences.getInstance(),
    );
    final InstallClaim claim = InstallClaim(store, () => null);

    final String first = claim.installId;
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(first),
      isTrue,
    );
    expect(InstallClaim(store, () => null).installId, first);
  });

  test('with no backend the answer is unknown, never "moved"', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final InstallClaim claim = InstallClaim(
      KeyValueStore(await SharedPreferences.getInstance()),
      () => null,
    );
    // Being offline must never lock anybody out of their own account.
    expect(await claim.claim(), ClaimResult.unknown);
  });
}
