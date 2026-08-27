import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/routing/app_routes.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/features/goals/domain/goals_state.dart';
import 'package:aja/features/goals/domain/rank.dart';
import 'package:aja/features/goals/presentation/widgets/rank_style.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Tells the user what just happened, weighted by how much it is worth
/// interrupting them for.
///
/// A met goal gets a snack bar: it happens every day, the user is mid-session,
/// and a modal for it would become the thing they learn to dismiss. A new rank
/// gets a dialog — it happens six times in the life of the app, and it is the
/// only payoff the points have.
Future<void> showGoalEvent(BuildContext context, GoalEvent event) async {
  switch (event) {
    case GoalUnchanged():
      return;

    case GoalReached(:final int points):
      context.showSnack(context.l10n.goalsReachedSnack(points));

    case RankReached(:final int points, :final Rank rank):
      final bool? seeProgress = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) =>
            _RankUpDialog(rank: rank, points: points),
      );

      if (!(seeProgress ?? false) || !context.mounted) return;
      context.goNamed(AppRoutes.progressName);
  }
}

class _RankUpDialog extends StatelessWidget {
  const _RankUpDialog({required this.rank, required this.points});

  final Rank rank;
  final int points;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: context.colors.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          rank.icon,
          size: 36,
          color: context.colors.onPrimaryContainer,
        ),
      ),
      title: Text(context.l10n.goalsRankUpTitle, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            rank.label(context),
            textAlign: TextAlign.center,
            style: context.texts.headlineSmall?.copyWith(
              color: context.colors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.goalsRankUpBody(points),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonClose),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n.goalsSeeProgress),
        ),
      ],
    );
  }
}
