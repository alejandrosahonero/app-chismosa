/// Push without Firebase: every call must be a quiet no-op, because tests and
/// any build where FCM failed to start go through exactly this path.
library;

import 'package:chismosa/services/push/push_service.dart';
import 'package:chismosa/services/storage/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SharedPreferences prefs;
  late PushService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    service = PushService(KeyValueStore(prefs));
  });

  test('asking for the permission before start-up spends nothing', () async {
    await service.askPermissionOnce();
    // Android shows that dialog once in the app's life; a call that could not
    // show it must not mark it as spent.
    expect(prefs.getBool('push_permission_asked'), isNull);
  });

  test('attaching before start-up registers no token', () async {
    await service.attach(SupabaseClient('https://example.invalid', 'anon'));
    expect(service.token, isNull);
  });
}
