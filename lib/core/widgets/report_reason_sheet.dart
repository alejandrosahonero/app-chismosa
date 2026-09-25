import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:flutter/material.dart';

/// Why something is being reported. The ids are what the server stores and
/// what `after_report_names_someone` (0008) looks for.
enum ReportReason {
  /// Points at a real, identifiable person. The one reason that hides the
  /// content at once, pending a person's review.
  namesSomeone('names_someone'),
  harassment('harassment'),
  sexualOrIllegal('sexual_or_illegal'),
  other('other');

  const ReportReason(this.id);

  final String id;
}

/// Asks why, and doubles as the confirmation: picking a reason is the yes,
/// dismissing the sheet is the no. Reporting by accident is worse than a tap
/// more.
Future<ReportReason?> pickReportReason(BuildContext context) {
  return showModalBottomSheet<ReportReason>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) {
      final l10n = context.l10n;
      Widget option(
        ReportReason reason,
        IconData icon,
        String title, [
        String? subtitle,
      ]) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: () => Navigator.of(context).pop(reason),
      );

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.reportWhy, style: context.texts.titleMedium),
            ),
            option(
              ReportReason.namesSomeone,
              Icons.person_search_outlined,
              l10n.reportNamesSomeone,
              l10n.reportNamesSomeoneBody,
            ),
            option(
              ReportReason.harassment,
              Icons.back_hand_outlined,
              l10n.reportHarassment,
            ),
            option(
              ReportReason.sexualOrIllegal,
              Icons.gpp_bad_outlined,
              l10n.reportSexualOrIllegal,
            ),
            option(ReportReason.other, Icons.flag_outlined, l10n.reportOther),
          ],
        ),
      );
    },
  );
}
