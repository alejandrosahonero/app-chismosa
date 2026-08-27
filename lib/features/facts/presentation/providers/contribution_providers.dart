import 'package:aja/features/facts/data/contribution_service.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kept alive on purpose: it owns the debounce timer that batches "ask for
/// more" taps and an `http.Client` worth reusing. Disposing it between visits
/// to the finished screen would drop taps the user already made.
final Provider<ContributionService> contributionServiceProvider =
    Provider<ContributionService>((Ref ref) {
      final ContributionService service = ContributionService(
        ref.watch(keyValueStoreProvider),
      );
      ref.onDispose(service.dispose);
      return service;
    });
