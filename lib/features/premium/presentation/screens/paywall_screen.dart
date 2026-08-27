import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/core/widgets/app_loader.dart';
import 'package:aja/core/widgets/base_screen.dart';
import 'package:aja/core/widgets/error_view.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/billing/premium_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Remove ads" paywall.
///
/// `showBanner: false`: showing an ad on the screen that sells ad removal is
/// both absurd and a click-accident risk right next to the purchase button.
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PremiumStatus> status = ref.watch(
      premiumControllerProvider,
    );

    return BaseScreen(
      title: context.l10n.paywallTitle,
      showBanner: false,
      padding: const EdgeInsets.all(AppSpacing.md),
      body: _body(context, ref, status),
    );
  }

  /// `AsyncValue` keeps the last data across refreshes, so a reload never
  /// blanks the screen: data wins over the loading/error flags when present.
  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<PremiumStatus> status,
  ) {
    final PremiumStatus? data = status.value;
    if (data != null) return _PaywallBody(status: data);
    if (status.hasError) {
      return ErrorView(
        message: context.l10n.commonErrorGeneric,
        onRetry: () => ref.invalidate(premiumControllerProvider),
      );
    }
    return const AppLoader();
  }
}

class _PaywallBody extends ConsumerWidget {
  const _PaywallBody({required this.status});

  final PremiumStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (status.isPremium) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.verified,
              size: 56,
              color: context.semanticColors.success,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(context.l10n.premiumActive, style: context.texts.titleMedium),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(context.l10n.paywallHeadline, style: context.texts.headlineSmall),
        const SizedBox(height: AppSpacing.lg),
        const _Benefit(icon: Icons.block, textKey: _BenefitKey.noAds),
        const _Benefit(
          icon: Icons.bookmark_outline,
          textKey: _BenefitKey.favorites,
        ),
        const _Benefit(
          icon: Icons.favorite_outline,
          textKey: _BenefitKey.support,
        ),
        const _Benefit(
          icon: Icons.payments_outlined,
          textKey: _BenefitKey.oneTime,
        ),
        const Spacer(),
        if (status.flow case PurchaseFailed())
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              context.l10n.paywallError,
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
        if (!status.storeAvailable)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              context.l10n.paywallUnavailable,
              style: context.texts.bodyMedium,
            ),
          ),
        FilledButton(
          onPressed: status.canBuy && status.flow is! PurchasePending
              ? () =>
                    ref.read(premiumControllerProvider.notifier).buyRemoveAds()
              : null,
          child: status.flow is PurchasePending
              ? Text(context.l10n.paywallPending)
              : Text(
                  context.l10n.paywallBuy(
                    status.removeAdsProduct?.price ?? '—',
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Restore must be reachable from the paywall AND from Settings.
        TextButton(
          onPressed: () =>
              ref.read(premiumControllerProvider.notifier).restorePurchases(),
          child: Text(context.l10n.paywallRestore),
        ),
      ],
    );
  }
}

enum _BenefitKey { noAds, favorites, support, oneTime }

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.textKey});

  final IconData icon;
  final _BenefitKey textKey;

  @override
  Widget build(BuildContext context) {
    final String text = switch (textKey) {
      _BenefitKey.noAds => context.l10n.paywallBenefitNoAds,
      _BenefitKey.favorites => context.l10n.paywallBenefitFavorites,
      _BenefitKey.support => context.l10n.paywallBenefitSupport,
      _BenefitKey.oneTime => context.l10n.paywallBenefitOneTime,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(icon, color: context.colors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: context.texts.bodyLarge)),
        ],
      ),
    );
  }
}
