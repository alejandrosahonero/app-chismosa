import 'dart:async';

import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/threads/data/thread_repository.dart';
import 'package:chismosa/features/threads/domain/thread_message.dart';
import 'package:chismosa/features/threads/presentation/providers/threads_providers.dart';
import 'package:chismosa/services/moderation/moderation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One open conversation.
@immutable
class ThreadState {
  const ThreadState({
    required this.story,
    required this.membership,
    required this.messages,
    this.loadingOlder = false,
    this.atStart = false,
  });

  final Story story;

  /// Who this reader is *here*. Also the row every message they send points at.
  final ThreadMembership membership;

  /// Oldest first, which is the order a conversation is read in.
  final List<ThreadMessage> messages;

  final bool loadingOlder;

  /// The beginning of the conversation is on screen; there is nothing older.
  final bool atStart;

  ThreadState copyWith({
    ThreadMembership? membership,
    List<ThreadMessage>? messages,
    bool? loadingOlder,
    bool? atStart,
  }) => ThreadState(
    story: story,
    membership: membership ?? this.membership,
    messages: messages ?? this.messages,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    atStart: atStart ?? this.atStart,
  );
}

/// The conversation currently on screen, or null when none is.
///
/// One at a time and not a family: only one thread is ever open — the sheet
/// over the deck, or the screen reached from the history — and a family would
/// quietly keep a Realtime channel alive for every thread the reader has ever
/// looked at. The free plan allows 200 concurrent connections in total.
final AsyncNotifierProvider<ThreadController, ThreadState?>
threadControllerProvider =
    AsyncNotifierProvider<ThreadController, ThreadState?>(ThreadController.new);

class ThreadController extends AsyncNotifier<ThreadState?> {
  StreamSubscription<Map<String, dynamic>>? _live;

  /// Alias of every participant, keyed by membership id.
  ///
  /// Realtime hands over the row exactly as stored — `member_id` and no name —
  /// which is the whole reason the schema is shaped this way. This is where the
  /// name is put back on.
  Map<String, ThreadAlias> _aliases = <String, ThreadAlias>{};

  /// Aliases blocked while this thread is open. Realtime does not know about
  /// blocks — it ships every row to every member — so without this a blocked
  /// person would keep talking until the thread was reopened.
  final Set<String> _blockedAliases = <String>{};

  @override
  Future<ThreadState?> build() async {
    ref.onDispose(() => unawaited(_live?.cancel()));
    return null;
  }

  ThreadRepository? get _repository => ref.read(threadRepositoryProvider);

  /// Joins [story]'s thread and starts listening.
  ///
  /// Entering is joining: there is no separate "join" button anywhere, because
  /// a conversation you can read without being in it is one nobody would ever
  /// answer in.
  Future<void> open(Story story) async {
    final ThreadRepository? repository = _repository;
    if (repository == null) return;

    await _live?.cancel();
    _live = null;
    _blockedAliases.clear();
    state = const AsyncLoading<ThreadState?>();

    try {
      final ThreadMembership membership = await repository.join(story.id);
      final List<ThreadMessage> messages = await repository.messages(story.id);
      _aliases = await repository.aliases(story.id);

      state = AsyncData<ThreadState?>(
        ThreadState(
          story: story,
          membership: membership,
          messages: messages,
          atStart: messages.length < BackendConfig.threadPageSize,
        ),
      );

      _live = repository.watch(story.id).listen(_onLiveRow);
      // Opening is reading. Doing it here and not on close means the badge is
      // cleared even if the app is killed with the thread open.
      unawaited(_swallow(() => repository.markRead(story.id)));
    } on Object catch (error, stackTrace) {
      state = AsyncError<ThreadState?>(error, stackTrace);
    }
  }

  /// Leaves the screen. The membership stays: the thread is in the history now.
  Future<void> close() async {
    final ThreadState? current = state.value;
    await _live?.cancel();
    _live = null;
    if (current != null) {
      unawaited(_swallow(() => _repository!.markRead(current.story.id)));
    }
    state = const AsyncData<ThreadState?>(null);
  }

  /// Sends [body], showing it before the server has confirmed it.
  ///
  /// A message that only appears once the round trip lands makes a slow
  /// connection feel broken, so it is painted straight away with a temporary
  /// id and swapped for the real row when it comes back. If it fails, the
  /// pending line is removed — the alternative is a message the reader believes
  /// they sent and nobody ever received.
  Future<void> send(String body) async {
    final ThreadState? current = state.value;
    final ThreadRepository? repository = _repository;
    final String text = body.trim();
    if (current == null || repository == null || text.isEmpty) return;

    final String tempId = 'pending:${DateTime.now().microsecondsSinceEpoch}';
    final ThreadMessage pending = ThreadMessage(
      id: tempId,
      alias: current.membership.alias,
      body: text,
      createdAt: DateTime.now().toUtc(),
      isMine: true,
      isAuthor: false,
      pending: true,
    );

    state = AsyncData<ThreadState?>(
      current.copyWith(messages: <ThreadMessage>[...current.messages, pending]),
    );

    try {
      final ThreadMessage sent = await repository.send(
        storyId: current.story.id,
        membership: current.membership,
        body: text,
      );
      _replace(tempId, sent);
    } on Object catch (error) {
      AppLogger.debug('Message failed: $error', name: 'threads');
      _remove(tempId);
      rethrow;
    }
  }

  /// One page further back.
  Future<void> loadOlder() async {
    final ThreadState? current = state.value;
    final ThreadRepository? repository = _repository;
    if (current == null ||
        repository == null ||
        current.loadingOlder ||
        current.atStart ||
        current.messages.isEmpty) {
      return;
    }

    state = AsyncData<ThreadState?>(current.copyWith(loadingOlder: true));

    try {
      final List<ThreadMessage> older = await repository.messages(
        current.story.id,
        before: current.messages.first.createdAt,
      );
      final ThreadState now = state.value ?? current;
      state = AsyncData<ThreadState?>(
        now.copyWith(
          messages: <ThreadMessage>[...older, ...now.messages],
          loadingOlder: false,
          atStart: older.length < BackendConfig.threadPageSize,
        ),
      );
    } on Object catch (error) {
      AppLogger.debug('Older page failed: $error', name: 'threads');
      state = AsyncData<ThreadState?>(
        (state.value ?? current).copyWith(loadingOlder: false),
      );
    }
  }

  /// Mutes or unmutes the push notifications of this thread.
  Future<void> toggleMute() async {
    final ThreadState? current = state.value;
    final ThreadRepository? repository = _repository;
    if (current == null || repository == null) return;

    final bool muted = !current.membership.muted;
    state = AsyncData<ThreadState?>(
      current.copyWith(membership: current.membership.copyWith(muted: muted)),
    );
    await _swallow(() => repository.setMuted(current.story.id, muted: muted));
  }

  /// Reports a message and hides it for this reader immediately.
  ///
  /// Whatever the server decides, somebody who has just reported a line should
  /// not have to keep looking at it while three other people make up their
  /// minds.
  Future<void> report(String messageId) async {
    _remove(messageId);
    await _swallow(() => _repository!.reportMessage(messageId));
  }

  /// Blocks whoever wrote [messageId] and clears their lines from the screen.
  ///
  /// Matched by alias, which is unique inside a thread: the app never learns
  /// the account behind a message, only the name it wears here. Their future
  /// messages are dropped by the server (`thread_messages` filters on blocks)
  /// but Realtime ships rows to every member as they are, so the live path
  /// filters them too — see [_blockedAliases].
  Future<void> blockAuthorOf(String messageId) async {
    final ThreadState? current = state.value;
    final ModerationService? moderation = ref.read(moderationServiceProvider);
    if (current == null || moderation == null) return;

    final String alias = current.messages
        .firstWhere((ThreadMessage m) => m.id == messageId)
        .alias;

    await moderation.blockMessageAuthor(messageId);
    _blockedAliases.add(alias);

    final ThreadState now = state.value ?? current;
    state = AsyncData<ThreadState?>(
      now.copyWith(
        messages: now.messages
            .where((ThreadMessage m) => m.alias != alias)
            .toList(growable: false),
      ),
    );
  }

  /// A row that arrived over the socket.
  Future<void> _onLiveRow(Map<String, dynamic> row) async {
    final ThreadState? current = state.value;
    if (current == null) return;

    final String? id = row['id'] as String?;
    final String? memberId = row['member_id'] as String?;
    if (id == null || memberId == null) return;
    if ((row['hidden'] as bool?) ?? false) return;

    // Our own message comes back through the socket too. It is already on
    // screen, with the id the insert returned.
    if (current.messages.any((ThreadMessage m) => m.id == id)) return;

    ThreadAlias? alias = _aliases[memberId];
    if (alias == null) {
      // Somebody joined after this thread was opened. Their name is not in the
      // map yet, and asking for it is cheaper than guessing.
      _aliases =
          await _repository?.aliases(current.story.id) ??
          const <String, ThreadAlias>{};
      alias = _aliases[memberId];
    }

    final ThreadState? now = state.value;
    if (now == null) return;
    if (alias != null && _blockedAliases.contains(alias.alias)) return;

    state = AsyncData<ThreadState?>(
      now.copyWith(
        messages: <ThreadMessage>[
          ...now.messages,
          ThreadMessage(
            id: id,
            alias: alias?.alias ?? '',
            body: (row['body'] as String?) ?? '',
            createdAt:
                DateTime.tryParse(
                  (row['created_at'] as String?) ?? '',
                )?.toUtc() ??
                DateTime.now().toUtc(),
            isMine: memberId == now.membership.id,
            isAuthor: alias?.isAuthor ?? false,
          ),
        ],
      ),
    );
  }

  void _replace(String id, ThreadMessage message) {
    final ThreadState? current = state.value;
    if (current == null) return;
    state = AsyncData<ThreadState?>(
      current.copyWith(
        messages: <ThreadMessage>[
          for (final ThreadMessage m in current.messages)
            if (m.id == id) message else m,
        ],
      ),
    );
  }

  void _remove(String id) {
    final ThreadState? current = state.value;
    if (current == null) return;
    state = AsyncData<ThreadState?>(
      current.copyWith(
        messages: current.messages
            .where((ThreadMessage m) => m.id != id)
            .toList(growable: false),
      ),
    );
  }

  /// Bookkeeping that must never take the screen down with it.
  Future<void> _swallow(Future<void> Function() call) async {
    try {
      await call();
    } on Object catch (error) {
      AppLogger.debug('Thread bookkeeping failed: $error', name: 'threads');
    }
  }
}
