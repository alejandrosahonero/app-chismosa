import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Blocking, from wherever something can be blocked.
///
/// A service and not part of the stories or threads feature because it is used
/// from both, and from Settings.
///
/// **A block names what the reader can see — a story, a message — and never an
/// account.** The server resolves the account behind it. The app has no way to
/// name a person, which is the point of the whole schema, so it has no way to
/// ask for one either (see `0004_moderation.sql`).
abstract interface class ModerationService {
  /// Blocks whoever wrote the story. Their other stories leave the deck and
  /// their messages leave every thread.
  Future<void> blockStoryAuthor(String storyId);

  /// Blocks whoever wrote the message.
  Future<void> blockMessageAuthor(String messageId);

  /// How many people this reader has blocked. A number and not a list: there
  /// is no way to describe a blocked account that is not a way to identify it.
  Future<int> blockedCount();

  /// Undoes every block. Returns how many were lifted.
  Future<int> clearBlocks();
}

class SupabaseModerationService implements ModerationService {
  const SupabaseModerationService(this._client);

  final SupabaseClient _client;

  @override
  Future<void> blockStoryAuthor(String storyId) => _client.rpc<void>(
    'block_story_author',
    params: <String, dynamic>{'p_story': storyId},
  );

  @override
  Future<void> blockMessageAuthor(String messageId) => _client.rpc<void>(
    'block_message_author',
    params: <String, dynamic>{'p_message': messageId},
  );

  @override
  Future<int> blockedCount() async {
    final dynamic count = await _client.rpc<dynamic>('blocked_count');
    return (count as num?)?.toInt() ?? 0;
  }

  @override
  Future<int> clearBlocks() async {
    final dynamic count = await _client.rpc<dynamic>('clear_blocks');
    return (count as num?)?.toInt() ?? 0;
  }
}

final Provider<ModerationService?> moderationServiceProvider =
    Provider<ModerationService?>((Ref ref) {
      ref.watch(sessionEpochProvider);
      final SupabaseClient? client = ref.watch(supabaseClientProvider);
      if (client == null) return null;
      return SupabaseModerationService(client);
    });

/// Number shown in Settings. Re-read on every visit.
final FutureProvider<int> blockedCountProvider = FutureProvider<int>((
  Ref ref,
) async {
  final ModerationService? service = ref.watch(moderationServiceProvider);
  if (service == null) return 0;
  return service.blockedCount();
}, isAutoDispose: true);
