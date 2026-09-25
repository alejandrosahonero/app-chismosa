import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/features/goals/domain/rank.dart';
import 'package:flutter/material.dart';

/// Name and icon for each rank, kept out of the domain the same way
/// `StoryCategory`'s label is: the enum is a threshold table, not a widget.
extension RankStyle on Rank {
  String label(BuildContext context) => switch (this) {
    Rank.curious => context.l10n.rankCurious,
    Rank.inquisitive => context.l10n.rankInquisitive,
    Rank.knowItAll => context.l10n.rankKnowItAll,
    Rank.scholar => context.l10n.rankScholar,
    Rank.encyclopedia => context.l10n.rankEncyclopedia,
    Rank.oracle => context.l10n.rankOracle,
  };

  /// Reads as a climb even with the labels covered: an ear, then eyes, then
  /// a word, then a conversation, then a megaphone, then the whole block's
  /// radio — from listening to being the one everybody listens to.
  IconData get icon => switch (this) {
    Rank.curious => Icons.hearing,
    Rank.inquisitive => Icons.visibility_outlined,
    Rank.knowItAll => Icons.chat_bubble_outline,
    Rank.scholar => Icons.forum_outlined,
    Rank.encyclopedia => Icons.campaign_outlined,
    Rank.oracle => Icons.radio,
  };
}
