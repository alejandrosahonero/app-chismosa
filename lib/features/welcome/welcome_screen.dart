import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_colors.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/storage/key_value_store.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Whether the first-run screens have been completed.
const String welcomeDoneKey = 'welcome_done';

/// First run: three screens, in the order a stranger needs them.
///
/// 1. **What this is**, in one sentence — the store listing got them here, but
///    the promise has to be repeated at the door.
/// 2. **The four gestures.** The deck hides its most important action (the
///    thread) behind an upward swipe nobody guesses; explaining it once beats
///    a thousand readers who never find the conversations.
/// 3. **The rules, the age check and an explicit yes.** Play requires users of
///    an app with user-generated content to accept its terms before posting,
///    and an anonymous app lives or dies by whether people read the three
///    rules at least once.
///
/// Its own feature folder and nothing else touches it: a first-run flow is the
/// kind of thing that gets redesigned wholesale, and it should be deletable.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final PageController _pages = PageController();
  int _page = 0;
  bool _adult = false;
  bool _accepted = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final bool last = _page == 2;

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (int page) => setState(() => _page = page),
                children: <Widget>[
                  const _Hero(),
                  const _Gestures(),
                  _Rules(
                    adult: _adult,
                    accepted: _accepted,
                    onAdult: (bool value) => setState(() => _adult = value),
                    onAccepted: (bool value) =>
                        setState(() => _accepted = value),
                  ),
                ],
              ),
            ),
            _Dots(page: _page),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.spice,
                  foregroundColor: AppColors.ink,
                  disabledBackgroundColor: AppColors.paper.withValues(
                    alpha: 0.12,
                  ),
                  disabledForegroundColor: AppColors.paper.withValues(
                    alpha: 0.4,
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                onPressed: !last
                    ? () => _pages.nextPage(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                      )
                    : (_adult && _accepted ? _finish : null),
                child: Text(last ? l10n.welcomeStart : l10n.welcomeNext),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finish() async {
    final KeyValueStore store = ref.read(keyValueStoreProvider);
    await store.setBool(welcomeDoneKey, value: true);
    if (mounted) context.goNamed(AppRoutes.homeName);
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '“',
            style: TextStyle(
              fontSize: 120,
              height: 0.8,
              fontWeight: FontWeight.w900,
              color: AppColors.spice,
            ),
          ),
          Text(
            l10n.welcomeHeadline,
            style: context.texts.displaySmall?.copyWith(
              color: AppColors.paper,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1.05,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.welcomeBody,
            style: context.texts.titleMedium?.copyWith(
              color: AppColors.paper.withValues(alpha: 0.75),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Gestures extends StatelessWidget {
  const _Gestures();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.welcomeGesturesTitle,
            style: context.texts.headlineMedium?.copyWith(
              color: AppColors.paper,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _GestureRow(
            icon: Icons.arrow_upward_rounded,
            color: AppColors.lavender,
            text: l10n.welcomeGestureUp,
            emphasis: true,
          ),
          _GestureRow(
            icon: Icons.arrow_forward_rounded,
            color: AppColors.spice,
            text: l10n.welcomeGestureRight,
          ),
          _GestureRow(
            icon: Icons.arrow_back_rounded,
            color: AppColors.paper,
            text: l10n.welcomeGestureLeft,
          ),
          _GestureRow(
            icon: Icons.edit_outlined,
            color: AppColors.lime,
            text: l10n.welcomeGestureWrite,
          ),
        ],
      ),
    );
  }
}

class _GestureRow extends StatelessWidget {
  const _GestureRow({
    required this.icon,
    required this.color,
    required this.text,
    this.emphasis = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: context.texts.titleMedium?.copyWith(
                color: AppColors.paper,
                fontWeight: emphasis ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules({
    required this.adult,
    required this.accepted,
    required this.onAdult,
    required this.onAccepted,
  });

  final bool adult;
  final bool accepted;
  final ValueChanged<bool> onAdult;
  final ValueChanged<bool> onAccepted;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextStyle? rule = context.texts.bodyLarge?.copyWith(
      color: AppColors.paper,
      height: 1.4,
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: <Widget>[
        Text(
          l10n.welcomeRulesTitle,
          style: context.texts.headlineMedium?.copyWith(
            color: AppColors.paper,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.rulesIntro,
          style: rule?.copyWith(color: AppColors.paper.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final String text in <String>[
          l10n.rulesNoNames,
          l10n.rulesNoHate,
          l10n.rulesNoMinors,
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.close_rounded, color: AppColors.spice),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(text, style: rule)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        _Check(value: adult, label: l10n.welcomeAge, onChanged: onAdult),
        _Check(
          value: accepted,
          label: l10n.welcomeAccept,
          onChanged: onAccepted,
        ),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (bool? next) => onChanged(next ?? false),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppColors.spice,
      checkColor: AppColors.ink,
      side: const BorderSide(color: AppColors.paper, width: 1.5),
      title: Text(
        label,
        style: context.texts.bodyLarge?.copyWith(color: AppColors.paper),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < 3; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == page ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == page
                  ? AppColors.spice
                  : AppColors.paper.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
      ],
    );
  }
}
