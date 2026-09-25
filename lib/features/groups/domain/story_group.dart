/// A private deck: stories published into it are dealt only to its members.
///
/// Named `StoryGroup` and not `Group` because Flutter already has several
/// things called that, and an import clash is a bad first impression.
///
/// There is no owner id and no member list, and there never will be: inside a
/// group of six friends, a list of who is in it is all it takes to put a name
/// to a story. The server hands out a count.
class StoryGroup {
  const StoryGroup({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.isOwner,
    required this.inviteCode,
    required this.inviteExpiresAt,
  });

  factory StoryGroup.fromRow(Map<String, dynamic> row) => StoryGroup(
    id: row['id']! as String,
    name: row['name']! as String,
    memberCount: (row['member_count'] as num?)?.toInt() ?? 1,
    isOwner: row['is_owner'] as bool? ?? false,
    inviteCode: row['invite_code']! as String,
    inviteExpiresAt: DateTime.parse(row['invite_expires_at']! as String),
  );

  final String id;
  final String name;
  final int memberCount;

  /// Only the owner can renew the invite or delete the group.
  final bool isOwner;

  final String inviteCode;
  final DateTime inviteExpiresAt;

  bool inviteExpired(DateTime now) => !inviteExpiresAt.isAfter(now);
}
