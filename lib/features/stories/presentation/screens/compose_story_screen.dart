import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/features/stories/data/story_repository.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_deck_controller.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/features/stories/presentation/widgets/story_card_view.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/locale/locale_providers.dart';
import 'package:chismosa/services/locale/locale_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Where a story is written.
///
/// The limits are the ones the database enforces, repeated here only so the
/// reader finds out before they press publish rather than after. The server is
/// still the authority: everything that can refuse a story — the daily quota,
/// the ban, the word filter — is a trigger, because a limit the client enforces
/// is a limit that does not exist.
class ComposeStoryScreen extends ConsumerStatefulWidget {
  const ComposeStoryScreen({super.key});

  /// Matches the `char_length(body) between 20 and 600` check on `stories`.
  static const int minLength = 20;
  static const int maxLength = 600;

  @override
  ConsumerState<ComposeStoryScreen> createState() => _ComposeStoryScreenState();
}

class _ComposeStoryScreenState extends ConsumerState<ComposeStoryScreen> {
  final TextEditingController _body = TextEditingController();

  StoryCategory _category = StoryCategory.anything;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // The counter and the publish button both depend on the text, and both are
    // cheap to rebuild; the alternative is a ValueNotifier for two widgets.
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final int length = _body.text.trim().length;
    final bool canSend =
        !_sending &&
        length >= ComposeStoryScreen.minLength &&
        length <= ComposeStoryScreen.maxLength;

    return BaseScreen(
      title: l10n.composeTitle,
      // No banner: an ad next to the send button of a form is exactly the
      // accidental click AdMob suspends accounts over.
      showBanner: false,
      padding: const EdgeInsets.all(AppSpacing.md),
      body: ListView(
        children: <Widget>[
          Text(
            l10n.composeHint,
            style: context.texts.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _body,
            maxLength: ComposeStoryScreen.maxLength,
            maxLines: 8,
            minLines: 6,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: l10n.composeField,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
              // The built-in counter already says "n/600"; this one says how
              // much further there is to go before the story can be sent.
              counterText: length < ComposeStoryScreen.minLength
                  ? l10n.composeTooShort(ComposeStoryScreen.minLength)
                  : l10n.composeCounter(length, ComposeStoryScreen.maxLength),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.composeCategory, style: context.texts.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final StoryCategory category in StoryCategory.values)
                ChoiceChip(
                  label: Text(categoryLabel(l10n, category)),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _AnonymityNote(onRules: () => context.pushNamed(AppRoutes.rulesName)),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: canSend ? _publish : null,
            child: _sending
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.composePublish),
          ),
        ],
      ),
    );
  }

  Future<void> _publish() async {
    final StoryRepository? repository = ref.read(storyRepositoryProvider);
    final AppLocalizations l10n = context.l10n;

    if (repository == null) {
      context.showSnack(l10n.composeErrorOffline);
      return;
    }

    setState(() => _sending = true);
    final LocaleSettings locale = ref.read(localeSettingsProvider);

    try {
      await repository.publish(
        body: _body.text.trim(),
        category: _category,
        lang: locale.writingLanguage,
        countryCode: locale.countryCode,
      );
      if (!mounted) return;

      // The deck excludes the reader's own stories, so it does not gain a card
      // — but the quota did change, and the next "nothing left" screen should
      // reflect a feed that was asked for again.
      ref.invalidate(storiesDeckControllerProvider);
      context.showSnack(l10n.composePublished);
      context.pop();
    } on StoryException catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      context.showSnack(_messageFor(l10n, error.failure));
    } on Object {
      if (!mounted) return;
      setState(() => _sending = false);
      context.showSnack(l10n.composeErrorOffline);
    }
  }

  static String _messageFor(AppLocalizations l10n, StoryFailure failure) =>
      switch (failure) {
        StoryFailure.dailyLimitReached => l10n.composeErrorDailyLimit,
        StoryFailure.accountBanned => l10n.composeErrorBanned,
        StoryFailure.blockedContent => l10n.composeErrorBlocked,
        _ => l10n.composeErrorOffline,
      };
}

class _AnonymityNote extends StatelessWidget {
  const _AnonymityNote({required this.onRules});

  final VoidCallback onRules;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.visibility_off_outlined,
          size: 18,
          color: context.colors.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.composeAnonymousNote,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              TextButton(
                onPressed: onRules,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(l10n.rulesTitle),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
