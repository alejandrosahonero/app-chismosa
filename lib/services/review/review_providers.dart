import 'package:chismosa/services/review/review_service.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<ReviewService> reviewServiceProvider = Provider<ReviewService>(
  (Ref ref) => ReviewService(ref.watch(keyValueStoreProvider)),
);
