import 'dart:async';

import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/features/stories/data/story_repository.dart';
import 'package:chismosa/features/threads/domain/thread_message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Everything a conversation needs from the server.
///
/// An interface so the thread controller can be tested without a socket: the
/// interesting behaviour — a live message arriving while a page is loading, a
/// message of one's own coming back through Realtime — is exactly the part that
/// is impossible to exercise against a real connection.
abstract interface class ThreadRepository {
  /// Joins the thread, or returns the membership that already exists.
  ///
  /// Entering **is** joining: the swipe up is the only door, and it is the same
  /// call whether it is the first time or the fiftieth.
  Future<ThreadMembership> join(String storyId);

  /// One page, oldest first.
  ///
  /// [before] pages backwards into the history: pass the timestamp of the
  /// oldest message on screen.
  Future<List<ThreadMessage>> messages(
    String storyId, {
    DateTime? before,
    int limit = BackendConfig.threadPageSize,
  });

  /// Alias of every participant, keyed by membership id.
  ///
  /// This is how a Realtime row — which carries `member_id` and nothing else —
  /// gets a name on screen.
  Future<Map<String, ThreadAlias>> aliases(String storyId);

  Future<ThreadMessage> send({
    required String storyId,
    required ThreadMembership membership,
    required String body,
  });

  /// Live rows inserted into this thread.
  Stream<Map<String, dynamic>> watch(String storyId);

  Future<void> markRead(String storyId);

  Future<void> setMuted(String storyId, {required bool muted});

  Future<List<ThreadSummary>> myThreads();

  Future<void> reportMessage(String messageId, {String? reason});
}

/// Alias plus whether it belongs to the story's author.
class ThreadAlias {
  const ThreadAlias({required this.alias, required this.isAuthor});

  final String alias;
  final bool isAuthor;
}

class SupabaseThreadRepository implements ThreadRepository {
  const SupabaseThreadRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) throw const StoryException(StoryFailure.notAuthenticated);
    return id;
  }

  @override
  Future<ThreadMembership> join(String storyId) async {
    final dynamic row = await _guard(
      () => _client.rpc<dynamic>(
        'join_thread',
        params: <String, dynamic>{'p_story': storyId},
      ),
    );
    if (row is! Map<String, dynamic>) {
      throw const StoryException(StoryFailure.storyUnavailable);
    }
    return ThreadMembership.fromRow(row);
  }

  @override
  Future<List<ThreadMessage>> messages(
    String storyId, {
    DateTime? before,
    int limit = BackendConfig.threadPageSize,
  }) async {
    final List<Map<String, dynamic>> rows =
        await _rows('thread_messages', <String, dynamic>{
          'p_story': storyId,
          'p_before': before?.toUtc().toIso8601String(),
          'p_limit': limit,
        });
    // The RPC orders newest first so that a page is the *last* n messages;
    // a conversation is read the other way round.
    return rows
        .map(ThreadMessage.fromRow)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
  }

  @override
  Future<Map<String, ThreadAlias>> aliases(String storyId) async {
    final List<Map<String, dynamic>> rows = await _rows(
      'thread_aliases',
      <String, dynamic>{'p_story': storyId},
    );
    return <String, ThreadAlias>{
      for (final Map<String, dynamic> row in rows)
        row['member_id']! as String: ThreadAlias(
          alias: (row['alias'] as String?) ?? '',
          isAuthor: (row['is_author'] as bool?) ?? false,
        ),
    };
  }

  @override
  Future<ThreadMessage> send({
    required String storyId,
    required ThreadMembership membership,
    required String body,
  }) async {
    final Map<String, dynamic> row = await _guard(
      () => _client
          .from('messages')
          .insert(<String, dynamic>{
            'story_id': storyId,
            'member_id': membership.id,
            'body': body,
          })
          .select('id, created_at')
          .single(),
    );

    return ThreadMessage(
      id: row['id']! as String,
      alias: membership.alias,
      body: body,
      createdAt:
          DateTime.tryParse((row['created_at'] as String?) ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      isMine: true,
      isAuthor: false,
    );
  }

  @override
  Stream<Map<String, dynamic>> watch(String storyId) {
    // One channel per open thread, and only while it is on screen. The free
    // plan allows 200 concurrent Realtime connections, so a deck that
    // subscribed to anything would spend them all on cards nobody is reading.
    final RealtimeChannel channel = _client.channel('thread:$storyId');

    // ignore: close_sinks — the controller is closed by its own onCancel,
    // which is the only place that knows the listener has gone away.
    late final StreamController<Map<String, dynamic>> controller;
    controller = StreamController<Map<String, dynamic>>(
      onCancel: () async {
        await _client.removeChannel(channel);
        await controller.close();
      },
    );

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'story_id',
            value: storyId,
          ),
          callback: (PostgresChangePayload payload) {
            if (!controller.isClosed) controller.add(payload.newRecord);
          },
        )
        .subscribe();

    return controller.stream;
  }

  @override
  Future<void> markRead(String storyId) => _guard(
    () => _client
        .from('thread_members')
        .update(<String, dynamic>{
          'last_read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('story_id', storyId)
        .eq('user_id', _userId),
  );

  @override
  Future<void> setMuted(String storyId, {required bool muted}) => _guard(
    () => _client
        .from('thread_members')
        .update(<String, dynamic>{'muted': muted})
        .eq('story_id', storyId)
        .eq('user_id', _userId),
  );

  @override
  Future<List<ThreadSummary>> myThreads() async {
    final List<Map<String, dynamic>> rows = await _rows(
      'my_threads',
      <String, dynamic>{},
    );
    return rows.map(ThreadSummary.fromRow).toList(growable: false);
  }

  @override
  Future<void> reportMessage(String messageId, {String? reason}) => _guard(
    () => _client.rpc<void>(
      'report_content',
      params: <String, dynamic>{
        'p_target_type': 'message',
        'p_target_id': messageId,
        'p_reason': reason,
      },
    ),
  );

  Future<List<Map<String, dynamic>>> _rows(
    String function,
    Map<String, dynamic> params,
  ) async {
    final dynamic result = await _guard(
      () => _client.rpc<dynamic>(function, params: params),
    );
    if (result is! List) return const <Map<String, dynamic>>[];
    return result.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// Same mapping as [SupabaseStoryRepository]: the triggers raise with the
  /// rule name as the message, so the message is the code.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw StoryException(
        StoryFailure.fromCode(error.message.trim()),
        error.message,
      );
    } on AuthException catch (error) {
      throw StoryException(StoryFailure.notAuthenticated, error.message);
    }
  }
}
