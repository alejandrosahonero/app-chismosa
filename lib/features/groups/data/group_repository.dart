import 'package:chismosa/features/groups/domain/story_group.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why the server refused a group operation.
enum GroupFailure {
  invalidName,
  blockedContent,
  tooManyGroups,
  invalidInvite,
  expiredInvite,
  ownerCannotLeave,
  notTheOwner,
  unknown;

  static GroupFailure fromCode(String? code) => switch (code) {
    'invalid_name' => GroupFailure.invalidName,
    'blocked_content' => GroupFailure.blockedContent,
    'too_many_groups' => GroupFailure.tooManyGroups,
    'invalid_invite' => GroupFailure.invalidInvite,
    'expired_invite' => GroupFailure.expiredInvite,
    'owner_cannot_leave' => GroupFailure.ownerCannotLeave,
    'not_the_owner' => GroupFailure.notTheOwner,
    _ => GroupFailure.unknown,
  };
}

class GroupException implements Exception {
  const GroupException(this.failure, [this.detail]);

  final GroupFailure failure;
  final String? detail;

  @override
  String toString() => 'GroupException(${failure.name}, $detail)';
}

/// Everything a client can do with a group. Every call is an RPC: the tables
/// themselves are closed to the app (see `0005_groups.sql`), because a row of
/// `groups` carries the owner's account id.
abstract interface class GroupRepository {
  Future<List<StoryGroup>> myGroups();

  /// Returns the new group's id. The creator is its first member.
  Future<String> create(String name, {GroupRules rules = GroupRules.strict});

  /// The group an invite leads to, without joining it.
  Future<InvitePreview> previewInvite(String code);

  /// Returns the id of the group joined. Joining twice is not an error.
  Future<String> joinByCode(String code);

  /// Owner only. Switches relaxed rules back on; the server never relaxes one.
  Future<void> tightenRules(String groupId, GroupRules rules);

  Future<void> leave(String groupId);

  /// Owner only. Takes every story and thread in the group with it.
  Future<void> delete(String groupId);

  /// Owner only. Kills every copy of the old code that ever escaped.
  Future<String> rotateInvite(String groupId);
}

class SupabaseGroupRepository implements GroupRepository {
  const SupabaseGroupRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<StoryGroup>> myGroups() async {
    final dynamic rows = await _guard(() => _client.rpc<dynamic>('my_groups'));
    if (rows is! List) return const <StoryGroup>[];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(StoryGroup.fromRow)
        .toList(growable: false);
  }

  @override
  Future<String> create(
    String name, {
    GroupRules rules = GroupRules.strict,
  }) async {
    final dynamic id = await _guard(
      () => _client.rpc<dynamic>(
        'create_group',
        params: <String, dynamic>{
          'p_name': name.trim(),
          'p_allow_names': rules.allowNames,
          'p_allow_swearing': rules.allowSwearing,
        },
      ),
    );
    return id as String;
  }

  @override
  Future<InvitePreview> previewInvite(String code) async {
    final dynamic rows = await _guard(
      () => _client.rpc<dynamic>(
        'invite_preview',
        params: <String, dynamic>{'p_code': normalizeInviteCode(code)},
      ),
    );
    if (rows is List && rows.isNotEmpty) {
      return InvitePreview.fromRow(rows.first as Map<String, dynamic>);
    }
    throw const GroupException(GroupFailure.invalidInvite);
  }

  @override
  Future<void> tightenRules(String groupId, GroupRules rules) => _guard(
    () => _client.rpc<void>(
      'tighten_group_rules',
      params: <String, dynamic>{
        'p_group': groupId,
        'p_allow_names': rules.allowNames,
        'p_allow_swearing': rules.allowSwearing,
      },
    ),
  );

  @override
  Future<String> joinByCode(String code) async {
    final dynamic rows = await _guard(
      () => _client.rpc<dynamic>(
        'join_group_by_code',
        params: <String, dynamic>{'p_code': normalizeInviteCode(code)},
      ),
    );
    if (rows is List && rows.isNotEmpty) {
      return (rows.first as Map<String, dynamic>)['id']! as String;
    }
    throw const GroupException(GroupFailure.unknown);
  }

  @override
  Future<void> leave(String groupId) => _guard(
    () => _client.rpc<void>(
      'leave_group',
      params: <String, dynamic>{'p_group': groupId},
    ),
  );

  @override
  Future<void> delete(String groupId) => _guard(
    () => _client.rpc<void>(
      'delete_group',
      params: <String, dynamic>{'p_group': groupId},
    ),
  );

  @override
  Future<String> rotateInvite(String groupId) async {
    final dynamic code = await _guard(
      () => _client.rpc<dynamic>(
        'rotate_invite',
        params: <String, dynamic>{'p_group': groupId},
      ),
    );
    return code as String;
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw GroupException(
        GroupFailure.fromCode(error.message.trim()),
        error.message,
      );
    }
  }
}

/// Accepts the code however it was pasted: with spaces, in capitals, or as
/// the whole invite message — the code is the only run of 12 hex characters in
/// it.
String normalizeInviteCode(String input) {
  final String lower = input.toLowerCase();
  final RegExpMatch? match = RegExp(
    r'(?<![0-9a-f])[0-9a-f]{12}(?![0-9a-f])',
  ).firstMatch(lower);
  return match?.group(0) ?? lower.replaceAll(RegExp(r'\s'), '');
}
