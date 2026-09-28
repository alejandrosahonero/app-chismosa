import 'dart:async';

import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/confirm_dialog.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:chismosa/services/identity/anonymous_identity_service.dart';
import 'package:chismosa/services/identity/install_claim.dart';
import 'package:chismosa/services/moderation/moderation_service.dart';
import 'package:chismosa/services/push/push_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The recovery code, restoring another account, blocked people, and
/// deleting the account.
///
/// This is the only place the code is ever shown. The account has no e-mail
/// and no password anybody knows; Auto Backup brings it back after most
/// reinstalls, but not all of them, and never onto a different phone. The code
/// is the guarantee — which is why it is behind a tap and never on screen by
/// default: whoever reads it off somebody's phone gets in as them.
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  /// Revealed for this visit only. Leaving Settings hides it again.
  bool _revealed = false;

  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AnonymousIdentityService? identity = ref.watch(
      identityServiceProvider,
    );
    final String? code = identity?.identity?.code.formatted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: Text(l10n.accountCodeTitle),
          subtitle: Text(l10n.accountCodeBody),
          isThreeLine: true,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: code == null
              ? Text(
                  l10n.accountCodeUnavailable,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                )
              : _revealed
              ? _CodeBox(code: code)
              : OutlinedButton.icon(
                  onPressed: () => setState(() => _revealed = true),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(l10n.accountCodeShow),
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ListTile(
          leading: const Icon(Icons.restore),
          title: Text(l10n.accountRestoreTitle),
          trailing: const Icon(Icons.chevron_right),
          enabled: identity != null,
          onTap: () => unawaited(_restore(identity!)),
        ),
        const _BlockedTile(),
        ListTile(
          leading: Icon(Icons.delete_forever, color: context.colors.error),
          title: Text(
            l10n.accountDeleteTitle,
            style: TextStyle(color: context.colors.error),
          ),
          subtitle: Text(l10n.accountDeleteSubtitle),
          enabled: identity != null && !_deleting,
          onTap: () => unawaited(_delete(identity!)),
        ),
      ],
    );
  }

  /// Google Play requires in-app deletion for apps that create accounts. The
  /// phone carries on with a brand-new empty account afterwards: the app has
  /// no signed-out state to fall back to.
  Future<void> _delete(AnonymousIdentityService identity) async {
    final AppLocalizations l10n = context.l10n;
    final bool ok = await showConfirmDialog(
      context,
      title: l10n.accountDeleteTitle,
      body: l10n.accountDeleteBody,
      confirmLabel: l10n.accountDeleteConfirm,
    );
    if (!ok || !mounted) return;

    setState(() => _deleting = true);
    try {
      await identity.deleteAccount();
      ref.read(sessionEpochProvider.notifier).bump();
      // The device row went with the old account; register it on the new one.
      final SupabaseClient? client = ref.read(supabaseClientProvider);
      if (client != null) {
        unawaited(ref.read(pushServiceProvider).attach(client));
      }
      unawaited(ref.read(installClaimProvider).claim());
      if (!mounted) return;
      setState(() => _revealed = false);
      context.showSnack(l10n.accountDeleted);
    } on Object {
      if (mounted) context.showSnack(l10n.accountDeleteError);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _restore(AnonymousIdentityService identity) async {
    final AppLocalizations l10n = context.l10n;
    final String? input = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _RestoreDialog(),
    );
    if (input == null || input.trim().isEmpty || !mounted) return;

    try {
      await identity.restoreFromCode(input);
      // Everything built on the previous account — the deck, the history, the
      // block count — is rebuilt against the restored one.
      ref.read(sessionEpochProvider.notifier).bump();
      // This phone's notifications follow the account now using it.
      final SupabaseClient? client = ref.read(supabaseClientProvider);
      if (client != null) {
        unawaited(ref.read(pushServiceProvider).attach(client));
      }
      if (!mounted) return;
      setState(() => _revealed = false);
      context.showSnack(l10n.accountRestored);
      // Restoring onto this phone while another still uses the account: the
      // moved screen offers to bring it here (free) or keep both (premium).
      final ClaimResult claim = await ref.read(installClaimProvider).claim();
      if (claim == ClaimResult.moved && mounted) {
        ref.read(accountMovedProvider.notifier).set(moved: true);
        context.goNamed(AppRoutes.movedName);
      }
    } on Object {
      if (mounted) context.showSnack(l10n.accountRestoreInvalid);
    }
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SelectableText(
              code,
              style: context.texts.titleMedium?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 1.2,
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.accountCodeCopy,
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) {
                context.showSnack(context.l10n.accountCodeCopied);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog();

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    // Scrollable: with the keyboard up the dialog is shorter than its
    // content ("bottom overflowed" on small phones).
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.accountRestoreTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.accountRestoreBody),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _input,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: l10n.accountRestoreField,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_input.text),
          child: Text(l10n.accountRestore),
        ),
      ],
    );
  }
}

class _BlockedTile extends ConsumerWidget {
  const _BlockedTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final int count = ref.watch(blockedCountProvider).value ?? 0;

    return ListTile(
      leading: const Icon(Icons.block),
      title: Text(l10n.accountBlockedTitle),
      subtitle: Text(l10n.accountBlockedCount(count)),
      trailing: count == 0
          ? null
          : TextButton(
              onPressed: () => unawaited(_clear(context, ref)),
              child: Text(l10n.accountUnblockAll),
            ),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final bool ok = await showConfirmDialog(
      context,
      title: l10n.accountUnblockAll,
      body: l10n.accountUnblockAllBody,
      confirmLabel: l10n.accountUnblockAll,
    );
    if (!ok) return;

    try {
      await ref.read(moderationServiceProvider)?.clearBlocks();
      ref.invalidate(blockedCountProvider);
      if (context.mounted) context.showSnack(l10n.accountUnblocked);
    } on Object {
      if (context.mounted) context.showSnack(l10n.moderationError);
    }
  }
}
