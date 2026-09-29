import 'package:chismosa/services/identity/secret_store.dart';
import 'package:chismosa/services/storage/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the browser store keeps, returns and forgets the secret', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SecretStore store = KeyValueSecretStore(
      KeyValueStore(await SharedPreferences.getInstance()),
    );

    expect(await store.read(), isNull);
    await store.write('secret-123');
    expect(await store.read(), 'secret-123');
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('a blank value reads as no secret', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'identity_key': '  ',
    });
    final SecretStore store = KeyValueSecretStore(
      KeyValueStore(await SharedPreferences.getInstance()),
    );

    expect(await store.read(), isNull);
  });
}
