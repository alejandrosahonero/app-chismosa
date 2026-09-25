import 'dart:async';

import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/app_loader.dart';
import 'package:chismosa/core/widgets/confirm_dialog.dart';
import 'package:chismosa/core/widgets/error_view.dart';
import 'package:chismosa/core/widgets/report_reason_sheet.dart';
import 'package:chismosa/features/threads/domain/thread_message.dart';
import 'package:chismosa/features/threads/presentation/providers/thread_controller.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/push/push_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The conversation itself, without deciding how it got on screen.
///
/// The same widget is the sheet that rises out of the deck and the screen the
/// history opens, because they are the same thing: a thread you are already in.
/// Only the frame around it differs.
class ThreadPanel extends ConsumerStatefulWidget {
  const ThreadPanel({required this.onClose, super.key, this.showHandle = true});

  /// Called by the drag handle and the close button.
  final VoidCallback onClose;

  /// The sheet has a handle; the standalone screen has an app bar instead.
  final bool showHandle;

  @override
  ConsumerState<ThreadPanel> createState() => _ThreadPanelState();
}

class _ThreadPanelState extends ConsumerState<ThreadPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ThreadState?> thread = ref.watch(threadControllerProvider);
    final AppLocalizations l10n = context.l10n;

    // A new message must not scroll a reader who has gone back to look at
    // something; only one who is already at the bottom.
    ref.listen(threadControllerProvider, (
      AsyncValue<ThreadState?>? previous,
      AsyncValue<ThreadState?> next,
    ) {
      final int before = previous?.value?.messages.length ?? 0;
      final int after = next.value?.messages.length ?? 0;
      if (after > before) _scrollToBottomIfNear();
    });

    return Material(
      color: context.colors.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            if (widget.showHandle) _Handle(onClose: widget.onClose),
            Expanded(
              child: thread.when(
                loading: () => const AppLoader(),
                error: (Object error, StackTrace _) => ErrorView(
                  message: l10n.storiesOfflineBody,
                  onRetry: widget.onClose,
                ),
                data: (ThreadState? state) => state == null
                    ? const AppLoader()
                    : _Conversation(state: state, scroll: _scroll),
              ),
            ),
            if (thread.value case final ThreadState state)
              state.story.isClosed
                  ? _ClosedNotice(text: l10n.threadClosedNotice)
                  : _Composer(
                      controller: _input,
                      sending: _sending,
                      onSend: _send,
                    ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    // Cleared before the round trip: the message is already on screen as
    // pending, and a field that stays full reads as "it did not go".
    _input.clear();

    try {
      await ref.read(threadControllerProvider.notifier).send(text);
      // The first message is when "tell me when someone answers" starts to
      // mean something, so it is when the permission is asked — once, ever.
      unawaited(ref.read(pushServiceProvider).askPermissionOnce());
    } on Object catch (error) {
      if (!mounted) return;
      // Put the text back so it is not lost to a dropped connection.
      _input.text = text;
      context.showSnack(
        error.toString().contains('too_fast')
            ? context.l10n.threadTooFast
            : error.toString().contains('personal_data')
            ? context.l10n.composeErrorPersonalData
            : context.l10n.threadSendError,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottomIfNear() {
    if (!_scroll.hasClients) return;
    final double distance =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (distance > 240) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    });
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Down on the handle closes it, which is the gesture that opened it in
      // reverse.
      onVerticalDragEnd: (DragEndDetails details) {
        if ((details.primaryVelocity ?? 0) > 200) onClose();
      },
      onTap: onClose,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(
          child: Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.outlineVariant,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        ),
      ),
    );
  }
}

class _Conversation extends ConsumerWidget {
  const _Conversation({required this.state, required this.scroll});

  final ThreadState state;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      children: <Widget>[
        _StoryHeader(state: state),
        if (state.atStart)
          _Divider(text: l10n.threadStart)
        else
          TextButton(
            onPressed: () => unawaited(
              ref.read(threadControllerProvider.notifier).loadOlder(),
            ),
            child: Text(l10n.threadOlder),
          ),
        if (state.messages.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              l10n.threadEmpty,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        for (final ThreadMessage message in state.messages)
          _Bubble(key: ValueKey<String>(message.id), message: message),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _StoryHeader extends ConsumerWidget {
  const _StoryHeader({required this.state});

  final ThreadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: AppSpacing.sm),
        if (state.story.chapter > 1)
          Text(
            l10n.storiesChapter(state.story.chapter),
            style: context.texts.labelLarge?.copyWith(
              color: context.colors.tertiary,
              fontWeight: FontWeight.w800,
            ),
          ),
        Text(state.story.body, style: context.texts.bodyLarge),
        // A saga is walked from inside its threads: back to the part before,
        // on to the part after.
        if (state.story.parentId != null || state.story.nextId != null)
          Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              if (state.story.parentId != null)
                TextButton.icon(
                  onPressed: () => context.pushNamed(
                    AppRoutes.threadName,
                    pathParameters: <String, String>{
                      'id': state.story.parentId!,
                    },
                  ),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(l10n.storiesChapter(state.story.chapter - 1)),
                ),
              if (state.story.nextId != null)
                TextButton.icon(
                  onPressed: () => context.pushNamed(
                    AppRoutes.threadName,
                    pathParameters: <String, String>{'id': state.story.nextId!},
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(l10n.storiesChapter(state.story.chapter + 1)),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                // The alias is stated up front on purpose: knowing which name
                // is yours before you write is what makes the anonymity feel
                // like a costume rather than a void.
                l10n.threadYouAre(state.membership.alias),
                style: context.texts.labelLarge?.copyWith(
                  color: context.colors.primary,
                ),
              ),
            ),
            IconButton(
              onPressed: () => unawaited(
                ref.read(threadControllerProvider.notifier).toggleMute(),
              ),
              tooltip: state.membership.muted
                  ? l10n.threadUnmute
                  : l10n.threadMute,
              icon: Icon(
                state.membership.muted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
              ),
            ),
          ],
        ),
        Text(
          l10n.threadAliasNote,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const Divider(height: AppSpacing.lg),
      ],
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message, super.key});

  final ThreadMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme colors = context.colors;
    final bool mine = message.isMine;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: mine || message.pending
            ? null
            : () => unawaited(_moderate(context, ref)),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          decoration: BoxDecoration(
            color: mine ? colors.primaryContainer : colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (!mine)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      message.alias,
                      style: context.texts.labelSmall?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                    if (message.isAuthor) ...<Widget>[
                      const SizedBox(width: AppSpacing.xs),
                      // Worth marking: in a conversation about somebody's life
                      // that one voice is not interchangeable with the rest.
                      Text(
                        '· ${context.l10n.threadAuthorTag}',
                        style: context.texts.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              Opacity(
                opacity: message.pending ? 0.6 : 1,
                child: Text(message.body, style: context.texts.bodyMedium),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Report or block, on a long press. Never on one's own lines.
  Future<void> _moderate(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final _MessageAction? action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(l10n.threadReportMessage),
              onTap: () => Navigator.of(context).pop(_MessageAction.report),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(l10n.moderationBlockMessageAuthor),
              onTap: () => Navigator.of(context).pop(_MessageAction.block),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    final ThreadController thread = ref.read(threadControllerProvider.notifier);

    switch (action) {
      case _MessageAction.report:
        final ReportReason? reason = await pickReportReason(context);
        if (reason == null) return;
        await thread.report(message.id, reason: reason.id);
        if (context.mounted) context.showSnack(l10n.threadMessageReported);
      case _MessageAction.block:
        final bool ok = await showConfirmDialog(
          context,
          title: l10n.moderationBlockConfirmTitle,
          body: l10n.moderationBlockConfirmBody,
          confirmLabel: l10n.moderationBlock,
        );
        if (!ok) return;
        try {
          await thread.blockAuthorOf(message.id);
          if (context.mounted) context.showSnack(l10n.moderationBlocked);
        } on Object {
          if (context.mounted) context.showSnack(l10n.moderationError);
        }
    }
  }
}

enum _MessageAction { report, block }

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final bool canSend = !sending && controller.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              // Matches the `char_length(body) between 1 and 500` check.
              maxLength: 500,
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => unawaited(onSend()),
              decoration: InputDecoration(
                hintText: context.l10n.threadHint,
                counterText: '',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            onPressed: canSend ? () => unawaited(onSend()) : null,
            tooltip: context.l10n.threadSend,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: context.colors.surfaceContainerHighest,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: context.texts.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: context.texts.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
