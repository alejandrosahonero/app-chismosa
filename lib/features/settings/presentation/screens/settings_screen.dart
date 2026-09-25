import 'package:chismosa/core/config/app_config.dart';
import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/theme/theme_controller.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/features/settings/presentation/widgets/account_section.dart';
import 'package:chismosa/services/ads/ads_providers.dart';
import 'package:chismosa/services/billing/premium_controller.dart';
import 'package:chismosa/services/push/push_providers.dart';
import 'package:chismosa/services/review/review_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings screen.
///
/// Three rows here are not optional extras — they are Play/AdMob requirements:
/// * "Restore purchases": its absence is a review rejection and a 1-star magnet.
/// * "Privacy options": required by the EEA consent message when UMP says so.
/// * A visible entry to the paywall.
///
/// `showBanner: false`: dense list of tappable rows, exactly the layout where
/// an accidental ad click happens.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider);
    final bool isPremium = ref.watch(isPremiumProvider);
    final AsyncValue<bool> privacyRequired = ref.watch(
      privacyOptionsRequiredProvider,
    );

    return BaseScreen(
      title: context.l10n.settingsTitle,
      leading: IconButton(
        onPressed: () => context.canPop()
            ? context.pop()
            : context.goNamed(AppRoutes.homeName),
        icon: const Icon(Icons.arrow_back),
      ),
      showBanner: false,
      body: ListView(
        children: <Widget>[
          _SectionHeader(title: context.l10n.accountSection),
          const AccountSection(),
          const Divider(),
          _SectionHeader(title: context.l10n.settingsAppearance),
          RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (ThemeMode? mode) {
              if (mode != null) {
                ref.read(themeModeProvider.notifier).setThemeMode(mode);
              }
            },
            child: Column(
              children: <Widget>[
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text(context.l10n.settingsThemeSystem),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text(context.l10n.settingsThemeLight),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text(context.l10n.settingsThemeDark),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.military_tech_outlined),
            title: Text(context.l10n.goalsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed(AppRoutes.progressName),
          ),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: Text(context.l10n.threadsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed(AppRoutes.threadsName),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(context.l10n.languagesTitle),
            subtitle: Text(context.l10n.languagesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed(AppRoutes.languagesName),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(context.l10n.rulesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed(AppRoutes.rulesName),
          ),
          const Divider(),
          _SectionHeader(title: context.l10n.settingsNotifications),
          // A second door to the permission, for whoever said no the first
          // time or never wrote in a thread. Android only shows its dialog
          // until it has been refused; after that this opens nothing, and the
          // system settings are the way.
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(context.l10n.settingsThreadPush),
            subtitle: Text(context.l10n.settingsThreadPushBody),
            onTap: () => ref.read(pushServiceProvider).requestPermission(),
          ),
          const Divider(),
          _SectionHeader(title: context.l10n.settingsMonetization),
          if (isPremium)
            ListTile(
              leading: const Icon(Icons.verified),
              title: Text(context.l10n.premiumActive),
            )
          else
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(context.l10n.settingsRemoveAds),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.goNamed(AppRoutes.paywallName),
            ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: Text(context.l10n.settingsRestorePurchases),
            onTap: () => _restore(context, ref),
          ),
          // Only rendered when UMP reports the entry point is required.
          if (privacyRequired.value ?? false)
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(context.l10n.settingsPrivacyOptions),
              onTap: () =>
                  ref.read(consentServiceProvider).showPrivacyOptionsForm(),
            ),
          const Divider(),
          _SectionHeader(title: context.l10n.settingsAbout),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text(context.l10n.settingsRateApp),
            onTap: () => ref.read(reviewServiceProvider).openStoreListing(),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(context.l10n.settingsVersion(AppConfig.versionName)),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    await ref.read(premiumControllerProvider.notifier).restorePurchases();
    if (!context.mounted) return;
    context.showSnack(context.l10n.settingsRestoreDone);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: context.texts.labelLarge?.copyWith(
          color: context.colors.primary,
        ),
      ),
    );
  }
}
