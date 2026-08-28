import 'package:flutter/foundation.dart';

/// One line of a conversation.
///
/// It carries an **alias** and never an account id. That is not a convenience:
/// Realtime ships message rows to every participant exactly as they are stored,
/// so the row itself has to be safe to hand out. It points at a membership
/// (`thread_members.id`), which exists only inside one thread, and the alias is
/// resolved from there.
@immutable
class ThreadMessage {
  const ThreadMessage({
    required this.id,
    required this.alias,
    required this.body,
    required this.createdAt,
    required this.isMine,
    required this.isAuthor,
    this.pending = false,
  });

  /// Parses a row of `thread_messages()`.
  factory ThreadMessage.fromRow(Map<String, dynamic> row) => ThreadMessage(
    id: row['id']! as String,
    alias: (row['alias'] as String?) ?? '',
    body: (row['body'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((row['created_at'] as String?) ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    isMine: (row['is_mine'] as bool?) ?? false,
    isAuthor: (row['is_author'] as bool?) ?? false,
  );

  final String id;

  /// Who said it, inside this thread and nowhere else.
  final String alias;

  final String body;
  final DateTime createdAt;

  /// Whether this reader wrote it.
  final bool isMine;

  /// Whether the writer is the person whose story started the thread. Worth
  /// marking: in a conversation about somebody's life, that one voice is not
  /// interchangeable with the rest.
  final bool isAuthor;

  /// Shown but not yet acknowledged by the server.
  ///
  /// A message that only appears once the round trip lands makes a slow
  /// connection feel broken, so it is painted immediately and replaced by the
  /// real row when it arrives.
  final bool pending;

  ThreadMessage asSent(String realId, DateTime createdAt) => ThreadMessage(
    id: realId,
    alias: alias,
    body: body,
    createdAt: createdAt,
    isMine: isMine,
    isAuthor: isAuthor,
  );

  @override
  bool operator ==(Object other) =>
      other is ThreadMessage && other.id == id && other.pending == pending;

  @override
  int get hashCode => Object.hash(id, pending);
}

/// Who somebody is inside one thread.
@immutable
class ThreadMembership {
  const ThreadMembership({
    required this.id,
    required this.storyId,
    required this.alias,
    required this.muted,
  });

  factory ThreadMembership.fromRow(Map<String, dynamic> row) =>
      ThreadMembership(
        id: row['id']! as String,
        storyId: row['story_id']! as String,
        alias: (row['alias'] as String?) ?? '',
        muted: (row['muted'] as bool?) ?? false,
      );

  /// `thread_members.id` — the surrogate a message points at.
  final String id;

  final String storyId;

  /// The name this reader wears here. Different in every thread on purpose: the
  /// same person is a different character in each conversation, so nobody can
  /// be followed from one story to the next.
  final String alias;

  final bool muted;

  ThreadMembership copyWith({bool? muted}) => ThreadMembership(
    id: id,
    storyId: storyId,
    alias: alias,
    muted: muted ?? this.muted,
  );
}

/// A row of the history screen.
@immutable
class ThreadSummary {
  const ThreadSummary({
    required this.storyId,
    required this.body,
    required this.alias,
    required this.muted,
    required this.messagesCount,
    required this.unreadCount,
    this.lastMessageAt,
  });

  factory ThreadSummary.fromRow(Map<String, dynamic> row) => ThreadSummary(
    storyId: row['story_id']! as String,
    body: (row['body'] as String?) ?? '',
    alias: (row['alias'] as String?) ?? '',
    muted: (row['muted'] as bool?) ?? false,
    messagesCount: (row['messages_count'] as num?)?.toInt() ?? 0,
    unreadCount: (row['unread_count'] as num?)?.toInt() ?? 0,
    lastMessageAt: DateTime.tryParse(
      (row['last_message_at'] as String?) ?? '',
    )?.toUtc(),
  );

  final String storyId;

  /// The story the conversation hangs off, so the row is recognisable without
  /// opening it.
  final String body;

  final String alias;
  final bool muted;
  final int messagesCount;

  /// Messages since this reader last opened the thread.
  final int unreadCount;

  final DateTime? lastMessageAt;
}
