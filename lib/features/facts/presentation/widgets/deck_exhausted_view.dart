import 'dart:async';

import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/core/widgets/empty_state.dart';
import 'package:aja/features/facts/presentation/providers/contribution_providers.dart';
import 'package:aja/features/facts/presentation/providers/deck_controller.dart';
import 'package:aja/features/facts/presentation/widgets/contribute_dialog.dart';
import 'package:aja/features/facts/presentation/widgets/heart_burst.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The end of a category: the only screen in the app with nothing to swipe.
///
/// It offers three ways out, in descending order of how much they give back:
/// go round again in a new order, write a question of your own, or just say you
/// want more. The last one does nothing the user can verify, which is exactly
/// why it had to be the one that feels best to press.
class DeckExhaustedView extends ConsumerStatefulWidget {
  const DeckExhaustedView({super.key});

  @override
  ConsumerState<DeckExhaustedView> createState() => _DeckExhaustedViewState();
}

class _DeckExhaustedViewState extends ConsumerState<DeckExhaustedView> {
  @override
  void initState() {
    super.initState();
    // Reaching this screen means the app is open and, most likely, online.
    // Anything the endpoint missed last time goes out now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(contributionServiceProvider).flush());
    });
  }

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.check_circle_outline,
      title: context.l10n.deckFinishedTitle,
      message: context.l10n.deckFinishedBody,
      action: Column(
        children: <Widget>[
          FilledButton.icon(
            onPressed: () =>
                unawaited(ref.read(deckControllerProvider.notifier).restart()),
            icon: const Icon(Icons.shuffle),
            label: Text(context.l10n.deckRestart),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => unawaited(showContributeDialog(context)),
            icon: const Icon(Icons.edit_outlined),
            label: Text(context.l10n.deckContribute),
          ),
          // Extra room above: the hearts fly up out of the button and would
          // otherwise cross the one above it.
          const SizedBox(height: AppSpacing.xl),
          HeartBurstButton(
            label: context.l10n.deckAskForMore,
            onPressed: () => unawaited(
              ref.read(contributionServiceProvider).registerMoreRequest(),
            ),
          ),
        ],
      ),
    );
  }
}
