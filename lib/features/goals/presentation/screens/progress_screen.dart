import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/routing/app_routes.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/core/widgets/base_screen.dart';
import 'package:aja/core/widgets/section_card.dart';
import 'package:aja/features/goals/domain/goals_state.dart';
import 'package:aja/features/goals/domain/rank.dart';
import 'package:aja/features/goals/presentation/providers/goals_controller.dart';
import 'package:aja/features/goals/presentation/widgets/rank_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Where the goal and the ranks are explained in full.
///
/// A screen of its own rather than a panel on the deck: all of this is worth
/// reading exactly once a day, and the deck cannot afford the height. Reached
/// from the ring in the app bar and from a row in Settings.
///
/// `showBanner: false`: this screen is the reward for a session, and framing a
/// rank-up with an ad is the cheapest possible way to spend it.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoalsState goals = ref.watch(goalsControllerProvider);

    return BaseScreen(
      title: context.l10n.goalsTitle,
      leading: IconButton(
        onPressed: () => context.canPop()
            ? context.pop()
            : context.goNamed(AppRoutes.homeName),
        icon: const Icon(Icons.arrow_back),
      ),
      showBanner: false,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          _RankHeader(goals: goals),
          const SizedBox(height: AppSpacing.lg),
          _TodayCard(goals: goals),
          const SizedBox(height: AppSpacing.md),
          _RankLadder(held: goals.rank),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.l10n.goalsHowItWorks,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// The badge, the name and the bar to the next rank.
class _RankHeader extends StatelessWidget {
  const _RankHeader({required this.goals});

  final GoalsState goals;

  @override
  Widget build(BuildContext context) {
    final Rank rank = goals.rank;
    final int? toNext = rank.pointsTo(goals.points);

    return Column(
      children: <Widget>[
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: context.colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            rank.icon,
            size: 48,
            color: context.colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(rank.label(context), style: context.texts.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.l10n.goalsPoints(goals.points),
          style: context.texts.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: rank.progressTo(goals.points),
            minHeight: 8,
            backgroundColor: context.colors.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          // Measured from this rank's floor, not from zero: a single bar for
          // the whole ladder would sit near empty for weeks.
          toNext == null
              ? context.l10n.goalsMaxRank
              : context.l10n.goalsNextRank(toNext, rank.next!.label(context)),
          textAlign: TextAlign.center,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.goals});

  final GoalsState goals;

  @override
  Widget build(BuildContext context) {
    final Color color = goals.isComplete
        ? context.semanticColors.success
        : context.colors.primary;

    return SectionCard(
      title: context.l10n.goalsTodayTitle,
      icon: Icons.today_outlined,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox.square(
              dimension: 56,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  CircularProgressIndicator(
                    value: goals.progress,
                    strokeWidth: 5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: context.colors.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                  if (goals.isComplete)
                    Icon(Icons.check_rounded, color: color, size: 26),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.goalsTodayProgress(
                      goals.learned.clamp(0, goals.target),
                      goals.target,
                    ),
                    style: context.texts.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    goals.isComplete
                        ? context.l10n.goalsTodayDone(goals.target)
                        : context.l10n.goalsTodayPending(goals.remaining),
                    style: context.texts.bodySmall?.copyWith(
                      color: goals.isComplete
                          ? color
                          : context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The whole ladder, so the next rank is a thing the user can aim at rather
/// than a surprise.
class _RankLadder extends StatelessWidget {
  const _RankLadder({required this.held});

  final Rank held;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: context.l10n.goalsRankLadder,
      icon: Icons.military_tech_outlined,
      children: <Widget>[
        for (final Rank rank in Rank.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: <Widget>[
                Icon(
                  rank.icon,
                  size: 20,
                  // Ranks above the one held are dimmed rather than hidden:
                  // what is coming is the reason to come back tomorrow.
                  color: rank.index <= held.index
                      ? context.colors.primary
                      : context.colors.outlineVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    rank.label(context),
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: rank == held ? FontWeight.w700 : null,
                      color: rank.index <= held.index
                          ? null
                          : context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  context.l10n.goalsRankPointsShort(rank.minPoints),
                  style: context.texts.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
