import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/identity/install_claim.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Shown when this account is being used on another phone and is not premium.
///
/// Two ways out, and the free one comes first: bringing the account here is
/// always allowed (a lost phone must never hold an account hostage); keeping
/// it on both phones at once is what premium adds.
class AccountMovedScreen extends ConsumerStatefulWidget {
  const AccountMovedScreen({super.key});

  @override
  ConsumerState<AccountMovedScreen> createState() => _AccountMovedScreenState();
}

class _AccountMovedScreenState extends ConsumerState<AccountMovedScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BaseScreen(
      title: l10n.appTitle,
      showBanner: false,
      padding: const EdgeInsets.all(AppSpacing.lg),
      body: ListView(
        children: <Widget>[
          const SizedBox(height: AppSpacing.xl),
          Icon(Icons.phonelink_lock, size: 56, color: context.colors.primary),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.movedTitle, style: context.texts.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.movedBody, style: context.texts.bodyLarge),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _busy ? null : () => _claim(take: true),
            child: Text(l10n.movedTakeHere),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
                    await context.pushNamed(AppRoutes.paywallName);
                    // Back from the paywall: a premium account is allowed on
                    // any number of phones, so asking again lets them in.
                    if (mounted) await _claim(take: false);
                  },
            child: Text(l10n.movedGoPremium),
          ),
        ],
      ),
    );
  }

  Future<void> _claim({required bool take}) async {
    setState(() => _busy = true);
    final ClaimResult result = await ref
        .read(installClaimProvider)
        .claim(take: take);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == ClaimResult.moved) return;
    ref.read(accountMovedProvider.notifier).set(moved: false);
    context.goNamed(AppRoutes.homeName);
  }
}
