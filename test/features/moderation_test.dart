/// Blocking and the publish quota.
///
/// The server resolves who a block is against; what the app has to get right
/// is what disappears from the screen, and that it keeps disappearing.
library;

import 'dart:async';

import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/threads/data/thread_repository.dart';
import 'package:chismosa/features/threads/domain/thread_message.dart';
import 'package:chismosa/features/threads/presentation/providers/thread_controller.dart';
import 'package:chismosa/features/threads/presentation/providers/threads_providers.dart';
import 'package:chismosa/services/moderation/moderation_service.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Moderation implements ModerationService {
  final List<String> blockedMessages = <String>[];
  final List<String> blockedStories = <String>[];

  @override
  Future<void> blockMessageAuthor(String messageId) async =>
      blockedMessages.add(messageId);

  @override
  Future<void> blockStoryAuthor(String storyId) async =>
      blockedStories.add(storyId);

  @override
  Future<int> blockedCount() async => blockedMessages.length;

  @override
  Future<int> clearBlocks() async => 0;
}

ThreadMessage _msg(String id, String alias) => ThreadMessage(
  id: id,
  alias: alias,
  body: 'mensaje $id',
  createdAt: DateTime.utc(2026, 8, 1),
  isMine: false,
  isAuthor: false,
);

class _Threads implements ThreadRepository {
  final StreamController<Map<String, dynamic>> live =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<ThreadMembership> join(String storyId) async =>
      ThreadMembership(id: 'me', storyId: storyId, alias: 'Yo', muted: false);

  @override
  Future<List<ThreadMessage>> messages(
    String storyId, {
    DateTime? before,
    int limit = BackendConfig.threadPageSize,
  }) async => <ThreadMessage>[
    _msg('1', 'Pesada'),
    _msg('2', 'Amable'),
    _msg('3', 'Pesada'),
  ];

  @override
  Future<Map<String, ThreadAlias>> aliases(String storyId) async =>
      const <String, ThreadAlias>{
        'm-pesada': ThreadAlias(alias: 'Pesada', isAuthor: false),
        'm-amable': ThreadAlias(alias: 'Amable', isAuthor: false),
      };

  @override
  Future<ThreadMessage> send({
    required String storyId,
    required ThreadMembership membership,
    required String body,
  }) async => throw UnimplementedError();

  @override
  Stream<Map<String, dynamic>> watch(String storyId) => live.stream;

  @override
  Future<void> markRead(String storyId) async {}

  @override
  Future<void> setMuted(String storyId, {required bool muted}) async {}

  @override
  Future<List<ThreadSummary>> myThreads() async => const <ThreadSummary>[];

  @override
  Future<void> reportMessage(String messageId, {String? reason}) async {}

  Future<void> dispose() => live.close();
}

final Story _story = Story(
  id: 's',
  body: 'Una historia lo bastante larga para el check del servidor.',
  category: StoryCategory.anything,
  lang: 'es',
  createdAt: DateTime.utc(2026, 8, 1),
  likesCount: 0,
  messagesCount: 0,
);

void main() {
  group('PublishStatus', () {
    test('counts what is left of the day plus bought credits', () {
      const PublishStatus status = PublishStatus(
        postedToday: 1,
        dailyLimit: 1,
        credits: 2,
        isPremium: false,
      );
      expect(status.remaining, 2);
      expect(status.canPublish, isTrue);
    });

    test('spent quota and no credits means no more today', () {
      const PublishStatus status = PublishStatus(
        postedToday: 1,
        dailyLimit: 1,
        credits: 0,
        isPremium: false,
      );
      expect(status.remaining, 0);
      expect(status.canPublish, isFalse);
    });

    test('premium has no limit to show', () {
      const PublishStatus status = PublishStatus(
        postedToday: 9,
        dailyLimit: 1,
        credits: 0,
        isPremium: true,
      );
      expect(status.remaining, isNull);
      expect(status.canPublish, isTrue);
    });
  });

  group('blocking inside a thread', () {
    late _Threads threads;
    late _Moderation moderation;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      threads = _Threads();
      moderation = _Moderation();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          threadRepositoryProvider.overrideWithValue(threads),
          moderationServiceProvider.overrideWithValue(moderation),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(threads.dispose);
      await container.read(threadControllerProvider.future);
      await container.read(threadControllerProvider.notifier).open(_story);
    });

    List<String> aliasesOnScreen() => container
        .read(threadControllerProvider)
        .value!
        .messages
        .map((ThreadMessage m) => m.alias)
        .toList();

    test('names the message, never an account', () async {
      await container
          .read(threadControllerProvider.notifier)
          .blockAuthorOf('1');
      expect(moderation.blockedMessages, <String>['1']);
    });

    test('every line of theirs leaves the screen at once', () async {
      await container
          .read(threadControllerProvider.notifier)
          .blockAuthorOf('1');
      expect(aliasesOnScreen(), <String>['Amable']);
    });

    test('they stay gone when they keep writing live', () async {
      // Realtime ships every row to every member; it knows nothing about
      // blocks. Without the local filter the blocked voice would come straight
      // back.
      await container
          .read(threadControllerProvider.notifier)
          .blockAuthorOf('1');

      threads.live.add(<String, dynamic>{
        'id': '4',
        'member_id': 'm-pesada',
        'body': 'sigo aquí',
        'created_at': DateTime.utc(2026, 8, 2).toIso8601String(),
        'hidden': false,
      });
      await Future<void>.delayed(Duration.zero);

      expect(aliasesOnScreen(), <String>['Amable']);
    });
  });
}
