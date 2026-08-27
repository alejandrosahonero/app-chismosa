import 'dart:async';

import 'package:aja/core/config/app_config.dart';
import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/routing/app_routes.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/core/theme/theme_controller.dart';
import 'package:aja/core/widgets/base_screen.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/services/ads/ads_providers.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/notifications/daily_question_service.dart';
import 'package:aja/services/notifications/notification_providers.dart';
import 'package:aja/services/review/review_providers.dart';
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
            leading: const Icon(Icons.bookmarks_outlined),
            title: Text(context.l10n.favoritesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed(AppRoutes.favoritesName),
          ),
          ListTile(
            leading: const Icon(Icons.military_tech_outlined),
            title: Text(context.l10n.goalsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.goNamed(AppRoutes.progressName),
          ),
          const Divider(),
          _SectionHeader(title: context.l10n.settingsNotifications),
          const _DailyQuestionSwitch(),
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

/// The only place in the app allowed to ask for the notification permission.
///
/// Android shows that dialog once and remembers a refusal, so spending it at
/// startup — before the user knows what the app even does — is how a retention
/// feature dies before it ships. Here the switch *is* the consent: the user has
/// already said what they want by touching it.
class _DailyQuestionSwitch extends ConsumerStatefulWidget {
  const _DailyQuestionSwitch();

  @override
  ConsumerState<_DailyQuestionSwitch> createState() =>
      _DailyQuestionSwitchState();
}

class _DailyQuestionSwitchState extends ConsumerState<_DailyQuestionSwitch> {
  late bool _enabled = ref.read(dailyQuestionServiceProvider).isEnabled;
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);

    final DailyQuestionService service = ref.read(dailyQuestionServiceProvider);

    if (!value) {
      await service.disable();
      if (mounted) setState(() => _enabled = false);
      return;
    }

    final String language = Localizations.localeOf(context).languageCode;
    final String title = context.l10n.dailyQuestionNotificationTitle;
    final String denied = context.l10n.settingsDailyQuestionDenied;

    final bool granted = await service.enable(
      facts: await ref.read(factsProvider.future),
      language: language,
      title: title,
    );

    if (!mounted) return;

    // The switch follows the OS, not the tap: leaving it on after a refusal
    // would promise a notification that is never coming.
    setState(() {
      _enabled = granted;
      _busy = false;
    });

    if (!granted) context.showSnack(denied);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_active_outlined),
      title: Text(context.l10n.settingsDailyQuestion),
      subtitle: Text(context.l10n.settingsDailyQuestionBody),
      value: _enabled,
      onChanged: _busy ? null : (bool value) => unawaited(_toggle(value)),
    );
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
