import 'package:aja/core/config/contribution_config.dart';
import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/features/facts/domain/contribution.dart';
import 'package:aja/features/facts/presentation/providers/contribution_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks the user for a question and its answer.
///
/// Shows the result itself rather than handing it back to the caller: every
/// outcome here is a one-line message, and threading four of them through a
/// return value would only move the `switch` somewhere with less context.
Future<void> showContributeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) => const _ContributeDialog(),
  );
}

class _ContributeDialog extends ConsumerStatefulWidget {
  const _ContributeDialog();

  @override
  ConsumerState<_ContributeDialog> createState() => _ContributeDialogState();
}

class _ContributeDialogState extends ConsumerState<_ContributeDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _question = TextEditingController();
  final TextEditingController _answer = TextEditingController();
  final TextEditingController _source = TextEditingController();

  bool _sending = false;

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_form.currentState?.validate() ?? false) || _sending) return;
    setState(() => _sending = true);

    final ContributionResult result = await ref
        .read(contributionServiceProvider)
        .submit(
          question: _question.text,
          answer: _answer.text,
          source: _source.text,
          language: Localizations.localeOf(context).languageCode,
        );

    if (!mounted) return;

    // Queued and sent read the same to the user on purpose: from where they are
    // standing the suggestion is in, and whether the endpoint answered right
    // now is not their problem.
    final String message = switch (result) {
      ContributionResult.sent ||
      ContributionResult.queued => context.l10n.contributeThanks,
      ContributionResult.tooSoon => context.l10n.contributeTooSoon,
      ContributionResult.invalid => context.l10n.contributeInvalid,
    };

    if (result == ContributionResult.tooSoon ||
        result == ContributionResult.invalid) {
      setState(() => _sending = false);
      context.showSnack(message);
      return;
    }

    Navigator.of(context).pop();
    context.showSnack(message);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.contributeTitle),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.contributeIntro,
                style: context.texts.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _Field(
                controller: _question,
                label: context.l10n.contributeQuestionLabel,
                hint: context.l10n.contributeQuestionHint,
                maxLength: ContributionConfig.maxQuestionLength,
                minLength: ContributionConfig.minQuestionLength,
                lines: 2,
              ),
              const SizedBox(height: AppSpacing.sm),
              _Field(
                controller: _answer,
                label: context.l10n.contributeAnswerLabel,
                hint: context.l10n.contributeAnswerHint,
                maxLength: ContributionConfig.maxAnswerLength,
                minLength: ContributionConfig.minAnswerLength,
                lines: 3,
              ),
              const SizedBox(height: AppSpacing.sm),
              // Optional, but asked for anyway: the catalogue's own rule is
              // that no fact ships without a source, so a suggestion that
              // brings one is worth ten that do not.
              _Field(
                controller: _source,
                label: context.l10n.contributeSourceLabel,
                hint: context.l10n.contributeSourceHint,
                maxLength: ContributionConfig.maxSourceLength,
                minLength: 0,
                lines: 1,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: Text(context.l10n.contributeSend),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.maxLength,
    required this.minLength,
    required this.lines,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLength;

  /// 0 makes the field optional.
  final int minLength;

  final int lines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      maxLength: maxLength,
      maxLines: lines,
      textInputAction: TextInputAction.next,
      textCapitalization: TextCapitalization.sentences,
      validator: (String? value) {
        final String text = (value ?? '').trim();
        if (minLength == 0) return null;
        return text.length < minLength ? context.l10n.contributeRequired : null;
      },
    );
  }
}
