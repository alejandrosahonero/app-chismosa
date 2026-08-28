import 'dart:async';

import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/widgets/app_loader.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/core/widgets/error_view.dart';
import 'package:chismosa/features/stories/data/story_repository.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/features/threads/presentation/providers/thread_controller.dart';
import 'package:chismosa/features/threads/presentation/widgets/thread_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A conversation opened from the history rather than from the deck.
///
/// The deck raises the same [ThreadPanel] as a sheet, because there the card is
/// still underneath and going back to it is the point. Coming from the history
/// there is no card to go back to, so it gets a screen and an app bar.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({required this.storyId, super.key});

  final String storyId;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  /// The history knows the story's id and its text, but the thread needs the
  /// whole row — the closed flag decides whether there is a composer at all.
  Future<void> _open() async {
    final StoryRepository? repository = ref.read(storyRepositoryProvider);
    if (repository == null) return;

    try {
      final Story? story = await repository.fetchStory(widget.storyId);
      if (story == null) {
        if (mounted) setState(() => _error = 'story_unavailable');
        return;
      }
      await ref.read(threadControllerProvider.notifier).open(story);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void deactivate() {
    // The channel has to go when the screen does, and `dispose` is too late to
    // touch a provider.
    unawaited(ref.read(threadControllerProvider.notifier).close());
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: context.l10n.threadTitle,
      // No banner: this is a conversation, and an ad wedged under somebody's
      // reply is the placement that gets tapped by accident.
      showBanner: false,
      body: _error != null
          ? ErrorView(
              message: context.l10n.storiesOfflineBody,
              onRetry: () {
                setState(() => _error = null);
                unawaited(_open());
              },
            )
          : ref.watch(threadControllerProvider).value == null
          ? const AppLoader()
          : ThreadPanel(
              showHandle: false,
              onClose: () => Navigator.of(context).maybePop(),
            ),
    );
  }
}
