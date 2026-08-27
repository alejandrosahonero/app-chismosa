import 'package:aja/services/review/review_service.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<ReviewService> reviewServiceProvider = Provider<ReviewService>(
  (Ref ref) => ReviewService(ref.watch(keyValueStoreProvider)),
);
