import 'dart:async';

import 'package:chismosa/core/utils/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('network failures are not reported as crashes', () {
    expect(
      isOfflineError(
        Exception(
          'ClientException with SocketException: Failed host lookup: '
          "'x.supabase.co' (OS Error: No address associated with hostname)",
        ),
      ),
      isTrue,
    );
    expect(isOfflineError(TimeoutException('slow')), isTrue);
  });

  test('real bugs still are', () {
    expect(isOfflineError(StateError('bad state')), isFalse);
    expect(isOfflineError(const FormatException('bad json')), isFalse);
  });
}
