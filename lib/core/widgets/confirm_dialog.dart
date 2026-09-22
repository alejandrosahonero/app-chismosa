import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:flutter/material.dart';

/// Asks before doing something that cannot be taken back quietly.
///
/// Returns true only on an explicit yes. Dismissing the dialog — back, a tap
/// outside — is a no: reporting or blocking somebody by accident is worse than
/// having to ask twice.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
