import 'dart:async';

import 'package:chismosa/core/config/app_config.dart';
import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/features/groups/domain/story_group.dart';
import 'package:chismosa/features/groups/presentation/providers/groups_providers.dart';
import 'package:chismosa/features/stories/data/story_repository.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_deck_controller.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/features/stories/presentation/widgets/story_card_view.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/ads/ads_providers.dart';
import 'package:chismosa/services/ads/ads_service.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:chismosa/services/locale/locale_providers.dart';
import 'package:chismosa/services/locale/locale_settings.dart';
import 'package:flutter/foundation.dart';
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
  const ComposeStoryScreen({super.key, this.continues});

  /// The story this one continues, from "Mis historias". It decides the group
  /// too: part 2 lands wherever part 1 was, whatever deck is open now.
  final OwnStory? continues;

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

    final OwnStory? parent = widget.continues;

    return BaseScreen(
      title: parent == null
          ? l10n.composeTitle
          : l10n.composeContinueTitle(parent.chapter + 1),
      // No banner: an ad next to the send button of a form is exactly the
      // accidental click AdMob suspends accounts over.
      showBanner: false,
      padding: const EdgeInsets.all(AppSpacing.md),
      body: ListView(
        children: <Widget>[
          if (parent != null) ...<Widget>[
            _ContinuesCard(parent: parent),
            const SizedBox(height: AppSpacing.md),
          ],
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
          if (parent == null) const _GroupLine(),
          const SizedBox(height: AppSpacing.lg),
          const _QuotaLine(),
          const SizedBox(height: AppSpacing.sm),
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
      final String id = await repository.publish(
        body: _body.text.trim(),
        category: _category,
        lang: locale.writingLanguage,
        countryCode: locale.countryCode,
        // Into whichever deck the reader came from. Writing from inside a
        // group and landing in front of the whole world would be the worst
        // surprise this app could spring.
        groupId: widget.continues == null
            ? ref.read(feedQueryProvider).groupId
            : widget.continues!.groupId,
        parentId: widget.continues?.id,
      );
      if (!mounted) return;

      // The deck excludes the reader's own stories, so it does not gain a card
      // — but the quota did change, and the next "nothing left" screen should
      // reflect a feed that was asked for again.
      // A story that names someone is published hidden, pending review
      // (0011). The author has to hear that now, not find it later.
      final bool underReview = await repository
          .myStories()
          .then(
            (List<OwnStory> own) =>
                own.any((OwnStory s) => s.id == id && s.underReview),
          )
          .catchError((Object _) => false);
      if (!mounted) return;
      ref
        ..invalidate(storiesDeckControllerProvider)
        ..invalidate(myStoriesProvider);
      context.showSnack(
        underReview ? l10n.composeUnderReview : l10n.composePublished,
      );
      context.pop();
    } on StoryException catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ref.invalidate(publishStatusProvider);
      if (error.failure == StoryFailure.dailyLimitReached) {
        // Not a dead end: the story is written, and the reader is one video
        // away from publishing it. Offering that here, at the moment of
        // refusal, is the only time the offer makes sense. The web has no
        // videos to offer.
        if (kIsWeb) {
          context.showSnack(l10n.composeErrorDailyLimit);
          return;
        }
        await _offerRewardedCredit();
        return;
      }
      context.showSnack(_messageFor(l10n, error.failure));
    } on Object {
      if (!mounted) return;
      setState(() => _sending = false);
      context.showSnack(l10n.composeErrorOffline);
    }
  }

  /// Asks whether to watch a video for one more story, and publishes if the
  /// credit arrives.
  Future<void> _offerRewardedCredit() async {
    final AppLocalizations l10n = context.l10n;
    final bool? watch = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.composeErrorDailyLimit),
        content: Text(l10n.composeWatchAdBody),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
              unawaited(context.pushNamed(AppRoutes.paywallName));
            },
            child: Text(l10n.composeRemoveLimit),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.composeWatchAd),
          ),
        ],
      ),
    );
    if ((watch ?? false) && mounted) await _watchForCredit();
  }

  /// Plays the video, waits for the server to grant the credit, publishes.
  ///
  /// The wait is the unusual part. The reward the SDK reports on the phone
  /// proves nothing — anything on the phone can be faked — so the credit is
  /// written by the server when Google calls it with a signed receipt, a few
  /// seconds after the video closes. Until that row exists, publishing would
  /// just be refused again.
  Future<void> _watchForCredit() async {
    final AppLocalizations l10n = context.l10n;
    final String? userId = ref
        .read(supabaseClientProvider)
        ?.auth
        .currentUser
        ?.id;
    final StoryRepository? repository = ref.read(storyRepositoryProvider);
    if (userId == null || repository == null) {
      context.showSnack(l10n.composeErrorOffline);
      return;
    }

    setState(() => _sending = true);
    final int before = (await _statusOrNull(repository))?.credits ?? 0;

    final RewardOutcome outcome = await ref
        .read(adsServiceProvider)
        .showRewardedForPostCredit(userId: userId);
    if (!mounted) return;

    switch (outcome) {
      case RewardOutcome.unavailable:
        setState(() => _sending = false);
        context.showSnack(l10n.composeAdUnavailable);
        return;
      case RewardOutcome.dismissed:
        setState(() => _sending = false);
        context.showSnack(l10n.composeAdDismissed);
        return;
      case RewardOutcome.earned:
        break;
    }

    context.showSnack(l10n.composeCreditPending);
    final bool arrived = await _awaitCredit(repository, above: before);
    if (!mounted) return;
    ref.invalidate(publishStatusProvider);

    if (!arrived) {
      setState(() => _sending = false);
      // The text stays in the field: nothing is lost, it just has to be sent
      // again once the server catches up.
      context.showSnack(l10n.composeCreditTimeout);
      return;
    }
    await _publish();
  }

  Future<bool> _awaitCredit(
    StoryRepository repository, {
    required int above,
  }) async {
    final DateTime deadline = DateTime.now().add(AppConfig.creditWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(AppConfig.creditPollInterval);
      final PublishStatus? status = await _statusOrNull(repository);
      if (status != null && status.credits > above) return true;
    }
    return false;
  }

  static Future<PublishStatus?> _statusOrNull(
    StoryRepository repository,
  ) async {
    try {
      return await repository.publishStatus();
    } on Object {
      return null;
    }
  }

  static String _messageFor(AppLocalizations l10n, StoryFailure failure) =>
      switch (failure) {
        StoryFailure.dailyLimitReached => l10n.composeErrorDailyLimit,
        StoryFailure.accountBanned => l10n.composeErrorBanned,
        StoryFailure.blockedContent => l10n.composeErrorBlocked,
        StoryFailure.personalData => l10n.composeErrorPersonalData,
        StoryFailure.cannotContinue => l10n.composeErrorCannotContinue,
        _ => l10n.composeErrorOffline,
      };
}

/// How many stories are left today, said before the reader presses publish.
///
/// Silent while it loads or when the server cannot be reached: the quota is
/// enforced by the server either way, and a line that flickers "0 left" before
/// the real number arrives would be the worst thing to show.
class _QuotaLine extends ConsumerWidget {
  const _QuotaLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PublishStatus? status = ref.watch(publishStatusProvider).value;
    if (status == null) return const SizedBox.shrink();

    final int? remaining = status.remaining;
    return Text(
      remaining == null
          ? context.l10n.composeUnlimited
          : context.l10n.composeRemaining(remaining),
      textAlign: TextAlign.center,
      style: context.texts.labelMedium?.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    );
  }
}

/// The part being continued, so the author writes the next one looking at
/// where the last one stopped.
class _ContinuesCard extends StatelessWidget {
  const _ContinuesCard({required this.parent});

  final OwnStory parent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.composeContinuesFrom(parent.chapter),
            style: context.texts.labelLarge?.copyWith(
              color: context.colors.onTertiaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            parent.body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodyMedium?.copyWith(
              color: context.colors.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Says where the story is going when that is not the whole world.
class _GroupLine extends ConsumerWidget {
  const _GroupLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? groupId = ref.watch(
      feedQueryProvider.select((query) => query.groupId),
    );
    if (groupId == null) return const SizedBox.shrink();

    final List<StoryGroup> groups =
        ref.watch(myGroupsProvider).value ?? const <StoryGroup>[];
    final String name =
        groups
            .where((StoryGroup group) => group.id == groupId)
            .map((StoryGroup group) => group.name)
            .firstOrNull ??
        '…';

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(Icons.groups_outlined, size: 18, color: context.colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              context.l10n.composeInGroup(name),
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
