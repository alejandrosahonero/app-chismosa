import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// The community rules.
///
/// Three of them, and short. Play requires an app with user generated content
/// to publish a standard and to act on it, and a wall of legal text is the
/// version of that nobody reads — which is the same as not having one. The part
/// that actually changes behaviour is the last line: what happens when you
/// break them.
///
/// Linked from the compose screen rather than shown as a gate on first launch.
/// The moment the rules matter is the moment somebody is about to publish, and
/// a screen between a new install and the first card is a screen that gets
/// dismissed unread.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return BaseScreen(
      title: l10n.rulesTitle,
      showBanner: false,
      padding: const EdgeInsets.all(AppSpacing.md),
      body: ListView(
        children: <Widget>[
          Text(l10n.rulesIntro, style: context.texts.bodyLarge),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: <Widget>[
                  _Rule(icon: Icons.badge_outlined, text: l10n.rulesNoNames),
                  const Divider(height: AppSpacing.lg),
                  _Rule(icon: Icons.report_outlined, text: l10n.rulesNoHate),
                  const Divider(height: AppSpacing.lg),
                  _Rule(icon: Icons.block, text: l10n.rulesNoMinors),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.rulesConsequence,
            style: context.texts.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.rulesAccept),
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: context.colors.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(text, style: context.texts.bodyMedium)),
      ],
    );
  }
}
