import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/routing/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Explains why a locked feature is locked, and offers the paywall.
///
/// Reaching for a premium feature *is* the value moment the guide wants the
/// paywall to follow, so this is the right place to sell. It is a dialog and
/// not a straight jump to the paywall on purpose: hijacking the screen after
/// what may have been an accidental swipe reads as a trap, and the user has to
/// be able to say "no" in one tap and keep reading.
Future<void> showPremiumFeatureDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined),
      title: Text(dialogContext.l10n.premiumFeatureTitle),
      content: Text(dialogContext.l10n.premiumFeatureBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.l10n.commonNotNow),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            dialogContext.goNamed(AppRoutes.paywallName);
          },
          child: Text(dialogContext.l10n.premiumFeatureCta),
        ),
      ],
    ),
  );
}
