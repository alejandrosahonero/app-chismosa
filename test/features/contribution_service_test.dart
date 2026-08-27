/// Tests for [ContributionService] and [Contribution.validate].
///
/// The endpoint is empty in the committed [ContributionConfig], so every
/// submission here stays on device. That is the promise under test: nothing
/// the user types is lost while the backend does not exist yet.

library;

import 'package:aja/features/facts/data/contribution_service.dart';
import 'package:aja/features/facts/domain/contribution.dart';
import 'package:aja/services/storage/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Contribution.validate', () {
    test('a question shorter than the minimum is refused', () {
      final List<ContributionProblem> problems = Contribution.validate(
        question: 'short',
        answer: 'A perfectly fine answer.',
      );

      expect(problems, contains(ContributionProblem.questionTooShort));
    });

    test('a question longer than the maximum is refused', () {
      final List<ContributionProblem> problems = Contribution.validate(
        question: 'q' * 201,
        answer: 'A perfectly fine answer.',
      );

      expect(problems, contains(ContributionProblem.questionTooLong));
    });

    test('a question and answer within limits pass with no problems', () {
      final List<ContributionProblem> problems = Contribution.validate(
        question: 'Why do cats purr when they are happy?',
        answer: 'It is a self-soothing mechanism.',
      );

      expect(problems, isEmpty);
    });
  });

  group('ContributionService', () {
    late ContributionService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      service = ContributionService(KeyValueStore(prefs));
    });

    tearDown(() => service.dispose());

    test(
      'a contribution is kept on device when there is no endpoint yet',
      () async {
        final ContributionResult result = await service.submit(
          question: 'Why do cats purr when they are happy?',
          answer: 'It is a self-soothing mechanism.',
          source: 'https://example.com/cats',
          language: 'en',
        );

        expect(result, ContributionResult.queued);
        expect(service.outboxSize, equals(1));
      },
    );

    test('a too-short question is refused before it is stored', () async {
      final ContributionResult result = await service.submit(
        question: 'short',
        answer: 'It is a self-soothing mechanism.',
        source: '',
        language: 'en',
      );

      expect(result, ContributionResult.invalid);
      expect(service.outboxSize, equals(0));
    });

    test('a second contribution too soon is refused', () async {
      final ContributionResult first = await service.submit(
        question: 'Why do cats purr when they are happy?',
        answer: 'It is a self-soothing mechanism.',
        source: '',
        language: 'en',
      );
      expect(first, ContributionResult.queued);

      final ContributionResult second = await service.submit(
        question: 'Why do dogs tilt their heads when confused?',
        answer: 'To better locate the source of a sound.',
        source: '',
        language: 'en',
      );

      expect(second, ContributionResult.tooSoon);
      expect(service.outboxSize, equals(1));
    });

    test('ask-for-more taps are counted locally', () async {
      await service.registerMoreRequest();
      await service.registerMoreRequest();
      await service.registerMoreRequest();

      expect(service.pendingMoreRequests, equals(3));
      expect(service.totalMoreRequests, equals(3));
    });
  });
}
