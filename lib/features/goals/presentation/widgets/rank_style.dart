import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/features/goals/domain/rank.dart';
import 'package:flutter/material.dart';

/// Name and icon for each rank, kept out of the domain the same way
/// `FactCategory`'s label is: the enum is a threshold table, not a widget.
extension RankStyle on Rank {
  String label(BuildContext context) => switch (this) {
    Rank.curious => context.l10n.rankCurious,
    Rank.inquisitive => context.l10n.rankInquisitive,
    Rank.knowItAll => context.l10n.rankKnowItAll,
    Rank.scholar => context.l10n.rankScholar,
    Rank.encyclopedia => context.l10n.rankEncyclopedia,
    Rank.oracle => context.l10n.rankOracle,
  };

  /// Reads as a climb even with the labels covered: a single idea, then a
  /// question, then a mind, then study, then a library, then the thing itself.
  IconData get icon => switch (this) {
    Rank.curious => Icons.emoji_objects_outlined,
    Rank.inquisitive => Icons.psychology_alt_outlined,
    Rank.knowItAll => Icons.psychology_outlined,
    Rank.scholar => Icons.school_outlined,
    Rank.encyclopedia => Icons.auto_stories_outlined,
    Rank.oracle => Icons.auto_awesome,
  };
}
