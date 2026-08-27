import 'dart:async';

import 'package:aja/core/config/app_config.dart';
import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/routing/app_routes.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/features/facts/presentation/widgets/deck_card_shell.dart';
import 'package:aja/services/ads/ads_providers.dart';
import 'package:aja/services/ads/ads_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// The ad slot of the deck, shaped like any other card.
///
/// Fetching a creative and putting it on screen are two different things, and
/// only the second one is an impression. This widget keeps them apart:
///
/// * The creative is **requested** while the card is still one place down the
///   stack ([AppConfig.deckAdPreloadDepth]), so it is already in memory by the
///   time the card arrives. Asking the network only once the card is on top is
///   what made the ad show up visibly late, after a flash of the fallback.
/// * The `AdWidget` is **mounted only at depth 0**. Cards waiting behind the
///   top one are 95 % covered, and rendering an ad nobody can see is exactly
///   what AdMob counts as an invalid impression. This rule does not relax.
/// * The "Ad" label is always painted. A native-looking ad without a label is a
///   deceptive-ads rejection.
///
/// While the request is in flight the card holds the creative's space empty
/// rather than showing the "remove ads" pitch. The pitch means "nothing filled"
/// — no consent, no inventory, no configured unit — and showing it during a
/// load that is about to succeed is how the card ends up visibly changing its
/// mind in front of the user.
class AdDeckCard extends ConsumerStatefulWidget {
  const AdDeckCard({required this.depth, super.key});

  /// 0 when this card is the one being dragged, 1 for the one behind it.
  final int depth;

  @override
  ConsumerState<AdDeckCard> createState() => _AdDeckCardState();
}

class _AdDeckCardState extends ConsumerState<AdDeckCard> {
  /// 300x250. Big enough to read as a card rather than a strip, and the size
  /// with the deepest inventory after the anchored banner.
  static const AdSize _size = AdSize.mediumRectangle;

  BannerAd? _banner;
  bool _loading = false;

  /// Set once a request comes back empty, so the card can tell "still waiting"
  /// apart from "nothing is coming" and only fall back to the pitch for the
  /// second one.
  bool _failed = false;

  bool get _shouldFetch => widget.depth <= AppConfig.deckAdPreloadDepth;

  @override
  void initState() {
    super.initState();
    if (_shouldFetch) unawaited(_load());
  }

  @override
  void didUpdateWidget(AdDeckCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Depth only ever decreases as the deck advances, but a rebuild can hand
    // this card a new depth at any time; `_load` is idempotent either way.
    if (_shouldFetch) unawaited(_load());
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AdsService ads = ref.read(adsServiceProvider);
    if (_loading || _banner != null) return;

    if (!ads.canShowBanner) {
      // No consent, no configured unit, or the SDK is still starting up. The
      // listener on `adsInitializedProvider` retries in the last case; until
      // something changes there is nothing coming, so the pitch takes over.
      if (mounted && !_failed) setState(() => _failed = true);
      return;
    }

    _loading = true;
    _failed = false;
    final BannerAd banner = BannerAd(
      size: _size,
      adUnitId: ads.bannerAdUnitId,
      request: ads.buildRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _banner = ad as BannerAd;
            _loading = false;
          });
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          AppLogger.debug('Deck ad load failed: $error', name: 'ads');
          ad.dispose();
          _loading = false;
          if (!mounted) return;
          // Only now does the pitch earn the space: nothing is coming.
          setState(() => _failed = true);
        },
      ),
    );

    await banner.load();
  }

  /// What sits in the middle of the card.
  ///
  /// The creative is only handed to an `AdWidget` at depth 0. A loaded ad
  /// waiting behind the top card keeps its space reserved with an empty box of
  /// the same size, so arriving on top is a repaint and not a relayout — and so
  /// AdMob never sees an impression for a card the user cannot look at.
  Widget _slot() {
    final BannerAd? banner = _banner;

    if (banner == null) {
      return _failed
          ? const _RemoveAdsPitch()
          : SizedBox(
              width: _size.width.toDouble(),
              height: _size.height.toDouble(),
            );
    }

    return SizedBox(
      width: _size.width.toDouble(),
      height: _size.height.toDouble(),
      child: widget.depth == 0 ? AdWidget(ad: banner) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The SDK may still have been initializing when this card was built.
    ref.listen<bool>(adsInitializedProvider, (bool? previous, bool next) {
      if (next && _shouldFetch) unawaited(_load());
    });

    return DeckCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _AdLabel(),
          const Spacer(),
          Center(child: _slot()),
          const Spacer(flex: 2),
          Row(
            children: <Widget>[
              Icon(
                Icons.swipe_left_alt,
                size: 18,
                color: context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.l10n.deckHintNext,
                  style: context.texts.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdLabel extends StatelessWidget {
  const _AdLabel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          context.l10n.adLabel,
          style: context.texts.labelMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Shown when no creative could be loaded.
class _RemoveAdsPitch extends StatelessWidget {
  const _RemoveAdsPitch();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.block, size: 40, color: context.colors.primary),
        const SizedBox(height: AppSpacing.md),
        Text(
          context.l10n.paywallHeadline,
          textAlign: TextAlign.center,
          style: context.texts.titleMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: () => context.goNamed(AppRoutes.paywallName),
          child: Text(context.l10n.settingsRemoveAds),
        ),
      ],
    );
  }
}
