import 'package:chismosa/features/groups/data/group_repository.dart';
import 'package:chismosa/features/groups/domain/story_group.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final Provider<GroupRepository?> groupRepositoryProvider =
    Provider<GroupRepository?>((Ref ref) {
      ref.watch(sessionEpochProvider);
      final SupabaseClient? client = ref.watch(supabaseClientProvider);
      if (client == null) return null;
      return SupabaseGroupRepository(client);
    });

/// The reader's groups. Kept alive while the deck is open, because the deck's
/// header needs the name of the group it is showing.
final FutureProvider<List<StoryGroup>> myGroupsProvider =
    FutureProvider<List<StoryGroup>>((Ref ref) async {
      final GroupRepository? repository = ref.watch(groupRepositoryProvider);
      if (repository == null) return const <StoryGroup>[];
      return repository.myGroups();
    }, isAutoDispose: true);
