import 'dart:async';

import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/app_loader.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/core/widgets/confirm_dialog.dart';
import 'package:chismosa/core/widgets/error_view.dart';
import 'package:chismosa/features/groups/data/group_repository.dart';
import 'package:chismosa/features/groups/domain/story_group.dart';
import 'package:chismosa/features/groups/presentation/providers/groups_providers.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

/// Private decks, and the way back to the worldwide one.
///
/// Picking a row switches the deck and goes back to it: this screen is a
/// picker first, and a place to manage groups second.
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key, this.inviteCode});

  /// From an invite link. Pre-fills the join dialog; it never joins by itself.
  final String? inviteCode;

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  @override
  void initState() {
    super.initState();
    final String? code = widget.inviteCode;
    if (code != null && code.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_join(prefill: code));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<StoryGroup>> groups = ref.watch(myGroupsProvider);
    final String? selected = ref.watch(
      feedQueryProvider.select((query) => query.groupId),
    );

    return BaseScreen(
      title: l10n.groupsTitle,
      showBanner: false,
      body: groups.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => ErrorView(
          message: l10n.storiesOfflineBody,
          onRetry: () => ref.invalidate(myGroupsProvider),
        ),
        data: (List<StoryGroup> rows) => ListView.builder(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          // The world, the two actions, a header, then the groups.
          itemCount: rows.length + 4,
          itemBuilder: (BuildContext context, int index) {
            switch (index) {
              case 0:
                return ListTile(
                  leading: const Icon(Icons.public),
                  title: Text(l10n.groupsWorldwide),
                  subtitle: Text(l10n.groupsWorldwideBody),
                  selected: selected == null,
                  trailing: selected == null ? const Icon(Icons.check) : null,
                  onTap: () => _open(null),
                );
              case 1:
                return ListTile(
                  leading: const Icon(Icons.group_add_outlined),
                  title: Text(l10n.groupsCreate),
                  onTap: () => unawaited(_create()),
                );
              case 2:
                return ListTile(
                  leading: const Icon(Icons.vpn_key_outlined),
                  title: Text(l10n.groupsJoin),
                  onTap: () => unawaited(_join()),
                );
              case 3:
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    rows.isEmpty ? l10n.groupsEmpty : l10n.groupsMine,
                    style: context.texts.titleSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                );
            }
            final StoryGroup group = rows[index - 4];
            return _GroupTile(
              group: group,
              selected: group.id == selected,
              onOpen: () => _open(group.id),
              onAction: (_GroupAction action) => unawaited(_act(group, action)),
            );
          },
        ),
      ),
    );
  }

  void _open(String? groupId) {
    ref.read(feedQueryProvider.notifier).selectGroup(groupId);
    context.goNamed(AppRoutes.homeName);
  }

  Future<void> _create() async {
    final AppLocalizations l10n = context.l10n;
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _TextPrompt(
        title: l10n.groupsCreate,
        body: l10n.groupsCreateBody,
        hint: l10n.groupsNameField,
        confirmLabel: l10n.groupsCreateConfirm,
        maxLength: 40,
      ),
    );
    if (name == null || name.trim().length < 2 || !mounted) return;

    await _run((GroupRepository repository) async {
      final String id = await repository.create(name);
      ref.invalidate(myGroupsProvider);
      if (mounted) _open(id);
    });
  }

  Future<void> _join({String? prefill}) async {
    final AppLocalizations l10n = context.l10n;
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _TextPrompt(
        title: l10n.groupsJoin,
        body: l10n.groupsJoinBody,
        hint: l10n.groupsCodeField,
        confirmLabel: l10n.groupsJoinConfirm,
        initial: prefill,
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    await _run((GroupRepository repository) async {
      final String id = await repository.joinByCode(code);
      ref.invalidate(myGroupsProvider);
      if (!mounted) return;
      context.showSnack(l10n.groupsJoined);
      _open(id);
    });
  }

  Future<void> _act(StoryGroup group, _GroupAction action) async {
    final AppLocalizations l10n = context.l10n;
    switch (action) {
      case _GroupAction.invite:
        await _share(group.name, group.inviteCode);
      case _GroupAction.rotate:
        final bool ok = await showConfirmDialog(
          context,
          title: l10n.groupsRotate,
          body: l10n.groupsRotateBody,
          confirmLabel: l10n.groupsRotate,
        );
        if (!ok) return;
        await _run((GroupRepository repository) async {
          final String code = await repository.rotateInvite(group.id);
          ref.invalidate(myGroupsProvider);
          if (mounted) await _share(group.name, code);
        });
      case _GroupAction.leave:
        final bool ok = await showConfirmDialog(
          context,
          title: l10n.groupsLeave,
          body: l10n.groupsLeaveBody(group.name),
          confirmLabel: l10n.groupsLeave,
        );
        if (!ok) return;
        await _run((GroupRepository repository) async {
          await repository.leave(group.id);
          _forget(group.id);
        });
      case _GroupAction.delete:
        final bool ok = await showConfirmDialog(
          context,
          title: l10n.groupsDelete,
          body: l10n.groupsDeleteBody(group.name),
          confirmLabel: l10n.groupsDelete,
        );
        if (!ok) return;
        await _run((GroupRepository repository) async {
          await repository.delete(group.id);
          _forget(group.id);
        });
    }
  }

  /// Out of a group the deck may be showing: back to the world.
  void _forget(String groupId) {
    ref.invalidate(myGroupsProvider);
    if (ref.read(feedQueryProvider).groupId == groupId) {
      ref.read(feedQueryProvider.notifier).selectGroup(null);
    }
  }

  Future<void> _share(String name, String code) async {
    final AppLocalizations l10n = context.l10n;
    await SharePlus.instance.share(
      ShareParams(
        text: l10n.groupsInviteMessage(name, code, inviteLink(code)),
        subject: name,
      ),
    );
  }

  Future<void> _run(Future<void> Function(GroupRepository) action) async {
    final AppLocalizations l10n = context.l10n;
    final GroupRepository? repository = ref.read(groupRepositoryProvider);
    if (repository == null) {
      context.showSnack(l10n.composeErrorOffline);
      return;
    }
    try {
      await action(repository);
    } on GroupException catch (error) {
      if (mounted) context.showSnack(groupFailureMessage(l10n, error.failure));
    } on Object {
      if (mounted) context.showSnack(l10n.composeErrorOffline);
    }
  }
}

/// The invite link. The host is a placeholder: go_router only sees the path,
/// and a custom scheme with the code as its host would lose it.
String inviteLink(String code) => 'chismosa://app/join/$code';

String groupFailureMessage(AppLocalizations l10n, GroupFailure failure) =>
    switch (failure) {
      GroupFailure.invalidName => l10n.groupsErrorName,
      GroupFailure.blockedContent => l10n.composeErrorBlocked,
      GroupFailure.tooManyGroups => l10n.groupsErrorTooMany,
      GroupFailure.invalidInvite => l10n.groupsErrorInvalidCode,
      GroupFailure.expiredInvite => l10n.groupsErrorExpiredCode,
      GroupFailure.ownerCannotLeave => l10n.groupsErrorOwnerLeave,
      GroupFailure.notTheOwner ||
      GroupFailure.unknown => l10n.composeErrorOffline,
    };

enum _GroupAction { invite, rotate, leave, delete }

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    required this.selected,
    required this.onOpen,
    required this.onAction,
  });

  final StoryGroup group;
  final bool selected;
  final VoidCallback onOpen;
  final ValueChanged<_GroupAction> onAction;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool expired = group.inviteExpired(DateTime.now());

    return ListTile(
      leading: const Icon(Icons.groups_outlined),
      title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        expired
            ? '${l10n.groupsMembers(group.memberCount)} · '
                  '${l10n.groupsInviteExpired}'
            : l10n.groupsMembers(group.memberCount),
      ),
      selected: selected,
      onTap: onOpen,
      trailing: PopupMenuButton<_GroupAction>(
        tooltip: l10n.groupsOptions,
        onSelected: onAction,
        itemBuilder: (BuildContext context) => <PopupMenuEntry<_GroupAction>>[
          // An expired code cannot be shared usefully; the owner renews it,
          // everyone else has to ask them.
          if (!expired)
            PopupMenuItem<_GroupAction>(
              value: _GroupAction.invite,
              child: Text(l10n.groupsInvite),
            ),
          if (group.isOwner)
            PopupMenuItem<_GroupAction>(
              value: _GroupAction.rotate,
              child: Text(l10n.groupsRotate),
            ),
          if (group.isOwner)
            PopupMenuItem<_GroupAction>(
              value: _GroupAction.delete,
              child: Text(l10n.groupsDelete),
            )
          else
            PopupMenuItem<_GroupAction>(
              value: _GroupAction.leave,
              child: Text(l10n.groupsLeave),
            ),
        ],
      ),
    );
  }
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.body,
    required this.hint,
    required this.confirmLabel,
    this.initial,
    this.maxLength,
  });

  final String title;
  final String body;
  final String hint;
  final String confirmLabel;
  final String? initial;
  final int? maxLength;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _input = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.body),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _input,
            autofocus: true,
            maxLength: widget.maxLength,
            decoration: InputDecoration(
              hintText: widget.hint,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_input.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
