import 'dart:async';

import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/locale/locale_providers.dart';
import 'package:chismosa/services/locale/locale_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Languages the deck is allowed to deal in.
///
/// Seeded from the phone's own locale, which is why there is no country picker
/// next to it: the country comes from the device and is not a preference. The
/// languages are, because plenty of people read more than the one their phone
/// is set to — and the deck is worldwide, so that choice is the difference
/// between a deck with content in it and an empty one.
class LanguagePreferencesScreen extends ConsumerWidget {
  const LanguagePreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final LocaleSettings settings = ref.watch(localeSettingsProvider);

    return BaseScreen(
      title: l10n.languagesTitle,
      showBanner: false,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Text(
              l10n.languagesSubtitle,
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          for (final String code in kSelectableLanguages)
            CheckboxListTile(
              value: settings.languages.contains(code),
              title: Text(_label(l10n, code)),
              onChanged: (bool? checked) {
                final List<String> next = <String>[...settings.languages];
                if (checked ?? false) {
                  next.add(code);
                } else {
                  next.remove(code);
                }
                // An empty selection is refused by the controller rather than
                // stored: a reader with no languages gets an empty deck, and
                // there would be no card left on screen to explain why.
                unawaited(
                  ref.read(localeSettingsProvider.notifier).setLanguages(next),
                );
              },
            ),
        ],
      ),
    );
  }

  static String _label(AppLocalizations l10n, String code) => switch (code) {
    'es' => l10n.languageEs,
    'en' => l10n.languageEn,
    'pt' => l10n.languagePt,
    'fr' => l10n.languageFr,
    'it' => l10n.languageIt,
    'de' => l10n.languageDe,
    _ => code,
  };
}
