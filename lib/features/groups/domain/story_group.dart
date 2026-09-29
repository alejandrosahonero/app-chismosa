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
    this.rules = GroupRules.strict,
  });

  factory StoryGroup.fromRow(Map<String, dynamic> row) => StoryGroup(
    id: row['id']! as String,
    name: row['name']! as String,
    memberCount: (row['member_count'] as num?)?.toInt() ?? 1,
    isOwner: row['is_owner'] as bool? ?? false,
    inviteCode: row['invite_code']! as String,
    inviteExpiresAt: DateTime.parse(row['invite_expires_at']! as String),
    rules: GroupRules.fromRow(row),
  );

  final String id;
  final String name;
  final int memberCount;

  /// Only the owner can renew the invite or delete the group.
  final bool isOwner;

  final String inviteCode;
  final DateTime inviteExpiresAt;

  /// Which of the optional rules this group turned off.
  final GroupRules rules;

  bool inviteExpired(DateTime now) => !inviteExpiresAt.isAfter(now);
}

/// The two rules a private group may turn off (0011). Everything else — no
/// phones, e-mails or links, reports, blocks, anything illegal — applies to
/// every group and to the worldwide deck, always.
///
/// Stored as "allowed", so the default (false, false) is every rule on.
class GroupRules {
  const GroupRules({this.allowNames = false, this.allowSwearing = false});

  factory GroupRules.fromRow(Map<String, dynamic> row) => GroupRules(
    allowNames: row['allow_names'] as bool? ?? false,
    allowSwearing: row['allow_swearing'] as bool? ?? false,
  );

  /// Every rule on: the worldwide deck, and a new group by default.
  static const GroupRules strict = GroupRules();

  /// Both optional rules off.
  static const GroupRules relaxed = GroupRules(
    allowNames: true,
    allowSwearing: true,
  );

  /// Names are not held for review in this group.
  final bool allowNames;

  /// The banned-words filter does not apply in this group.
  final bool allowSwearing;

  bool get isRelaxed => allowNames || allowSwearing;

  GroupRules copyWith({bool? allowNames, bool? allowSwearing}) => GroupRules(
    allowNames: allowNames ?? this.allowNames,
    allowSwearing: allowSwearing ?? this.allowSwearing,
  );

  @override
  bool operator ==(Object other) =>
      other is GroupRules &&
      other.allowNames == allowNames &&
      other.allowSwearing == allowSwearing;

  @override
  int get hashCode => Object.hash(allowNames, allowSwearing);
}

/// What an invite leads to, shown before joining.
class InvitePreview {
  const InvitePreview({
    required this.name,
    required this.memberCount,
    required this.rules,
  });

  factory InvitePreview.fromRow(Map<String, dynamic> row) => InvitePreview(
    name: row['name']! as String,
    memberCount: (row['member_count'] as num?)?.toInt() ?? 1,
    rules: GroupRules.fromRow(row),
  );

  final String name;
  final int memberCount;
  final GroupRules rules;
}
