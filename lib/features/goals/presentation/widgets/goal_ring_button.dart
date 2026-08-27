import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/routing/app_routes.dart';
import 'package:aja/features/goals/domain/goals_state.dart';
import 'package:aja/features/goals/presentation/providers/goals_controller.dart';
import 'package:aja/features/goals/presentation/widgets/rank_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Today's goal as an app bar action: a ring that fills, with the current rank
/// in the middle.
///
/// It lives in the bar and not over the deck on purpose. The deck already gives
/// up height to the chips and the banner, and this is the third thing that
/// would ask for a strip of it; up here it costs nothing and is still the first
/// thing in the user's line of sight when a card is flipped.
///
/// Note this is **not** the progress indicator the deck is forbidden to have.
/// That rule is about how much of the catalogue is left — a countdown that
/// turns an endless deck into a finite chore. This counts *up*, to a number
/// that resets tomorrow, and says nothing at all about how many cards remain.
class GoalRingButton extends ConsumerWidget {
  const GoalRingButton({super.key});

  static const double _diameter = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoalsState goals = ref.watch(goalsControllerProvider);
    final Color color = goals.isComplete
        ? context.semanticColors.success
        : context.colors.primary;

    return IconButton(
      onPressed: () => context.goNamed(AppRoutes.progressName),
      tooltip: context.l10n.goalsRingTooltip(
        goals.learned.clamp(0, goals.target),
        goals.target,
      ),
      icon: SizedBox.square(
        dimension: _diameter,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            CircularProgressIndicator(
              value: goals.progress,
              strokeWidth: 3,
              strokeCap: StrokeCap.round,
              backgroundColor: context.colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
            Icon(
              goals.isComplete ? Icons.check_rounded : goals.rank.icon,
              size: 15,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
