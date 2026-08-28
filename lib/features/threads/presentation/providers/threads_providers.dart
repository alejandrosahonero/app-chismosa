import 'package:chismosa/features/threads/data/thread_repository.dart';
import 'package:chismosa/features/threads/domain/thread_message.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Null while there is no client, same as the story repository: the deck and
/// the history both have something to show before sign-in finishes.
final Provider<ThreadRepository?> threadRepositoryProvider =
    Provider<ThreadRepository?>((Ref ref) {
      final SupabaseClient? client = ref.watch(supabaseClientProvider);
      if (client == null) return null;
      return SupabaseThreadRepository(client);
    });

/// The conversations this reader has joined, newest activity first.
///
/// `autoDispose`: it is a snapshot of the server, and it must be re-read on
/// every visit rather than showing yesterday's unread counts.
final FutureProvider<List<ThreadSummary>> myThreadsProvider =
    FutureProvider<List<ThreadSummary>>((Ref ref) async {
      final ThreadRepository? repository = ref.watch(threadRepositoryProvider);
      if (repository == null) return const <ThreadSummary>[];
      return repository.myThreads();
    }, isAutoDispose: true);
