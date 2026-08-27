import 'package:aja/core/config/app_config.dart';
import 'package:aja/services/review/review_service.dart';
import 'package:aja/services/storage/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The review prompt has a limited quota per user: these guards are the
/// difference between getting ratings and burning the dialog forever.
void main() {
  late KeyValueStore store;
  late ReviewService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = KeyValueStore(await SharedPreferences.getInstance());
    service = ReviewService(store);
  });

  test(
    'does not prompt before the minimum number of successful actions',
    () async {
      for (int i = 1; i < AppConfig.reviewMinSuccessfulActions; i++) {
        expect(await service.requestReviewAfterSuccess(), isFalse);
      }
    },
  );

  test('counts every successful action, prompt or not', () async {
    await service.requestReviewAfterSuccess();
    await service.requestReviewAfterSuccess();

    expect(store.getInt('review_success_count'), 2);
  });

  test('does not prompt on a fresh install even with enough actions', () async {
    await service.registerAppStart();

    for (int i = 0; i <= AppConfig.reviewMinSuccessfulActions; i++) {
      expect(await service.requestReviewAfterSuccess(), isFalse);
    }
  });

  test('registerAppStart only records the first launch date', () async {
    await service.registerAppStart();
    final DateTime? first = store.getDateTime('review_first_launch_at');

    await service.registerAppStart();

    expect(store.getDateTime('review_first_launch_at'), first);
  });
}
