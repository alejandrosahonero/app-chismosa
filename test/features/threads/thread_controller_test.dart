/// Rules of a live conversation.
///
/// The socket is faked, which is the only way to exercise the cases that matter
/// here: a message of one's own coming back through Realtime, a stranger
/// joining mid-conversation, a send that fails.
library;

import 'dart:async';

import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/threads/data/thread_repository.dart';
import 'package:chismosa/features/threads/domain/thread_message.dart';
import 'package:chismosa/features/threads/presentation/providers/thread_controller.dart';
import 'package:chismosa/features/threads/presentation/providers/threads_providers.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Story _story = Story(
  id: 'story-1',
  body: 'Una historia con la longitud suficiente para el check del servidor.',
  category: StoryCategory.anything,
  lang: 'es',
  createdAt: DateTime.utc(2026, 8, 1),
  likesCount: 0,
  messagesCount: 0,
);

ThreadMessage _message(String id, {String alias = 'Otra Persona'}) =>
    ThreadMessage(
      id: id,
      alias: alias,
      body: 'mensaje $id',
      createdAt: DateTime.utc(2026, 8, 1),
      isMine: false,
      isAuthor: false,
    );

class _FakeThreads implements ThreadRepository {
  _FakeThreads({this.history = const <ThreadMessage>[]});

  final List<ThreadMessage> history;

  final StreamController<Map<String, dynamic>> live =
      StreamController<Map<String, dynamic>>.broadcast();

  final List<String> readMarks = <String>[];
  final List<String> reported = <String>[];
  final List<String> sent = <String>[];

  Map<String, ThreadAlias> aliasTable = <String, ThreadAlias>{
    'me': const ThreadAlias(alias: 'Yo Mismo', isAuthor: false),
    'them': const ThreadAlias(alias: 'Otra Persona', isAuthor: true),
  };

  int aliasFetches = 0;
  bool failSend = false;
  bool muted = false;

  @override
  Future<ThreadMembership> join(String storyId) async => ThreadMembership(
    id: 'me',
    storyId: storyId,
    alias: 'Yo Mismo',
    muted: muted,
  );

  @override
  Future<List<ThreadMessage>> messages(
    String storyId, {
    DateTime? before,
    int limit = BackendConfig.threadPageSize,
  }) async => before == null ? history : const <ThreadMessage>[];

  @override
  Future<Map<String, ThreadAlias>> aliases(String storyId) async {
    aliasFetches++;
    return aliasTable;
  }

  @override
  Future<ThreadMessage> send({
    required String storyId,
    required ThreadMembership membership,
    required String body,
  }) async {
    if (failSend) throw Exception('too_fast');
    sent.add(body);
    return ThreadMessage(
      id: 'real-${sent.length}',
      alias: membership.alias,
      body: body,
      createdAt: DateTime.utc(2026, 8, 2),
      isMine: true,
      isAuthor: false,
    );
  }

  @override
  Stream<Map<String, dynamic>> watch(String storyId) => live.stream;

  @override
  Future<void> markRead(String storyId) async => readMarks.add(storyId);

  @override
  Future<void> setMuted(String storyId, {required bool muted}) async =>
      this.muted = muted;

  @override
  Future<List<ThreadSummary>> myThreads() async => const <ThreadSummary>[];

  @override
  Future<void> reportMessage(String messageId, {String? reason}) async =>
      reported.add(messageId);

  /// Stands in for the channel teardown the real repository does on cancel.
  Future<void> dispose() => live.close();
}

void main() {
  late _FakeThreads repository;
  late ProviderContainer container;

  Future<void> boot({
    List<ThreadMessage> history = const <ThreadMessage>[],
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    repository = _FakeThreads(history: history);

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        threadRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await container.read(threadControllerProvider.future);
  }

  ThreadController controller() =>
      container.read(threadControllerProvider.notifier);

  ThreadState? thread() => container.read(threadControllerProvider).value;

  /// Pushes a row the way Realtime would: member id, no name.
  Future<void> arrive(
    String id, {
    String member = 'them',
    String body = 'hola',
  }) async {
    repository.live.add(<String, dynamic>{
      'id': id,
      'member_id': member,
      'body': body,
      'created_at': DateTime.utc(2026, 8, 3).toIso8601String(),
      'hidden': false,
    });
    // Let the subscription callback run.
    await Future<void>.delayed(Duration.zero);
  }

  test('opening a thread joins it and shows who you are here', () async {
    await boot();
    await controller().open(_story);

    expect(thread()!.membership.alias, 'Yo Mismo');
    expect(thread()!.story.id, 'story-1');
  });

  test('opening marks the thread read', () async {
    // On open and not on close: the badge has to clear even if the app is
    // killed with the conversation on screen.
    await boot();
    await controller().open(_story);
    await Future<void>.delayed(Duration.zero);

    expect(repository.readMarks, contains('story-1'));
  });

  test('a short first page means the conversation starts there', () async {
    await boot(history: <ThreadMessage>[_message('1')]);
    await controller().open(_story);

    expect(thread()!.atStart, isTrue);
  });

  test('a live row gets its alias from the membership table', () async {
    // The row itself carries member_id and no name — that is the whole point
    // of the schema, so this is where the name is put back on.
    await boot();
    await controller().open(_story);
    await arrive('m-1');

    expect(thread()!.messages.single.alias, 'Otra Persona');
    expect(thread()!.messages.single.isAuthor, isTrue);
  });

  test('a message that is already on screen is not added twice', () async {
    await boot();
    await controller().open(_story);
    await controller().send('hola');

    // Our own message comes back over the socket with the id the insert
    // returned.
    await arrive('real-1', member: 'me', body: 'hola');

    expect(thread()!.messages, hasLength(1));
  });

  test('a stranger who joined mid-conversation is looked up once', () async {
    await boot();
    await controller().open(_story);
    final int before = repository.aliasFetches;

    repository.aliasTable = <String, ThreadAlias>{
      ...repository.aliasTable,
      'new': const ThreadAlias(alias: 'Recién Llegada', isAuthor: false),
    };
    await arrive('m-2', member: 'new');

    expect(repository.aliasFetches, before + 1);
    expect(thread()!.messages.single.alias, 'Recién Llegada');
  });

  test('a sent message shows before the server confirms it', () async {
    await boot();
    await controller().open(_story);

    final Future<void> sending = controller().send('hola');
    // Painted immediately: a message that only appears once the round trip
    // lands makes a slow connection feel broken.
    expect(thread()!.messages.single.pending, isTrue);

    await sending;
    expect(thread()!.messages.single.pending, isFalse);
    expect(thread()!.messages.single.id, 'real-1');
  });

  test('a send that fails takes its pending line away', () async {
    await boot();
    await controller().open(_story);
    repository.failSend = true;

    await expectLater(controller().send('hola'), throwsA(isA<Exception>()));

    // The alternative is a message the reader believes they sent.
    expect(thread()!.messages, isEmpty);
  });

  test('reporting hides the message for this reader at once', () async {
    await boot();
    await controller().open(_story);
    await arrive('m-3');

    await controller().report('m-3');

    expect(thread()!.messages, isEmpty);
    expect(repository.reported, <String>['m-3']);
  });

  test('muting is remembered by the server', () async {
    await boot();
    await controller().open(_story);

    await controller().toggleMute();

    expect(thread()!.membership.muted, isTrue);
    expect(repository.muted, isTrue);
  });

  test('closing drops the conversation and its socket', () async {
    await boot();
    await controller().open(_story);
    await controller().close();

    expect(thread(), isNull);
    // Nothing is listening any more, so a late row changes nothing.
    await arrive('m-late');
    expect(thread(), isNull);
  });

  test('a hidden row never reaches the screen', () async {
    await boot();
    await controller().open(_story);

    repository.live.add(<String, dynamic>{
      'id': 'm-hidden',
      'member_id': 'them',
      'body': 'algo',
      'created_at': DateTime.utc(2026, 8, 3).toIso8601String(),
      'hidden': true,
    });
    await Future<void>.delayed(Duration.zero);

    expect(thread()!.messages, isEmpty);
  });
}
