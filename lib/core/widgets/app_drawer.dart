import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_colors.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/billing/premium_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The deck's side menu: every place in the app that is not the deck.
///
/// Writing comes first because it is the one thing here a reader does often.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final bool isPremium = ref.watch(isPremiumProvider);

    void open(String name) {
      Navigator.of(context).pop();
      context.pushNamed(name);
    }

    return NavigationDrawer(
      children: <Widget>[
        Container(
          color: AppColors.maroon,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl + MediaQuery.paddingOf(context).top,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            l10n.appTitle,
            style: context.texts.headlineMedium?.copyWith(
              color: AppColors.bone,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _Item(
          icon: Icons.edit_outlined,
          label: l10n.composeTitle,
          onTap: () => open(AppRoutes.composeName),
        ),
        _Item(
          icon: Icons.edit_note,
          label: l10n.myStoriesTitle,
          onTap: () => open(AppRoutes.myStoriesName),
        ),
        _Item(
          icon: Icons.forum_outlined,
          label: l10n.threadsTitle,
          onTap: () => open(AppRoutes.threadsName),
        ),
        _Item(
          icon: Icons.groups_outlined,
          label: l10n.groupsTitle,
          onTap: () => open(AppRoutes.groupsName),
        ),
        const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
        if (!isPremium)
          _Item(
            icon: Icons.workspace_premium_outlined,
            label: l10n.paywallTitle,
            onTap: () => open(AppRoutes.paywallName),
          ),
        _Item(
          icon: Icons.shield_outlined,
          label: l10n.rulesTitle,
          onTap: () => open(AppRoutes.rulesName),
        ),
        _Item(
          icon: Icons.settings_outlined,
          label: l10n.settingsTitle,
          onTap: () => open(AppRoutes.settingsName),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }
}
