import 'dart:async';

import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/services/ads/ads_providers.dart';
import 'package:aja/services/ads/ads_service.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Anchored adaptive banner.
///
/// Renders nothing at all (zero height, no reserved space) when the user is
/// premium, when consent has not been gathered, or when no creative could be
/// loaded. That is deliberate: an empty grey strip looks broken, and a banner
/// that appears over a control is exactly what gets AdMob accounts suspended.
///
/// Adaptive sizing (instead of a fixed 320x50) is what AdMob recommends: it
/// picks the best height for the current screen width and yields a better
/// eCPM.
class AdaptiveBannerAd extends ConsumerStatefulWidget {
  const AdaptiveBannerAd({
    super.key,
    this.anchored = true,
    this.padding = EdgeInsets.zero,
  });

  /// Applied only when a creative is actually on screen.
  ///
  /// Kept here rather than around the widget so the "no ad, no reserved space"
  /// promise holds: a gap wrapped around it from outside survives the empty
  /// case and leaves a hole in the layout.
  final EdgeInsetsGeometry padding;

  /// True when the banner sits at the bottom edge of the screen, where it has
  /// to clear the system navigation bar.
  ///
  /// Set it to false for a banner placed inside the layout: there the system
  /// inset is somebody else's problem, and applying it would open a gap in the
  /// middle of the screen.
  final bool anchored;

  @override
  ConsumerState<AdaptiveBannerAd> createState() => _AdaptiveBannerAdState();
}

class _AdaptiveBannerAdState extends ConsumerState<AdaptiveBannerAd> {
  BannerAd? _banner;
  AdSize? _size;
  bool _loading = false;
  int? _loadedForWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Covers the common case: the SDK was already initialized before this
    // screen was pushed. Also re-runs on rotation (width change).
    unawaited(_load());
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final AdsService ads = ref.read(adsServiceProvider);
    if (!ads.canShowBanner || _loading) return;

    final int width = MediaQuery.sizeOf(context).width.truncate();
    if (_banner != null && _loadedForWidth == width) return;

    _loading = true;
    final AdSize? size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
      width,
    );

    if (!mounted || size == null) {
      _loading = false;
      return;
    }

    _disposeBanner();

    final BannerAd banner = BannerAd(
      size: size,
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
            _size = size;
            _loadedForWidth = width;
            _loading = false;
          });
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          AppLogger.debug('Banner load failed: $error', name: 'ads');
          ad.dispose();
          _loading = false;
        },
      ),
    );

    await banner.load();
  }

  void _disposeBanner() {
    _banner?.dispose();
    _banner = null;
    _size = null;
    _loadedForWidth = null;
  }

  @override
  Widget build(BuildContext context) {
    final bool isPremium = ref.watch(isPremiumProvider);

    // Load as soon as the SDK reports it is ready (consent resolved).
    ref.listen<bool>(adsInitializedProvider, (bool? previous, bool next) {
      if (next) unawaited(_load());
    });

    ref.listen<bool>(isPremiumProvider, (bool? previous, bool next) {
      if (next && _banner != null) setState(_disposeBanner);
    });

    final BannerAd? banner = _banner;
    final AdSize? size = _size;
    if (isPremium || banner == null || size == null) {
      return const SizedBox.shrink();
    }

    final Widget ad = SizedBox(
      width: size.width.toDouble(),
      height: size.height.toDouble(),
      child: AdWidget(ad: banner),
    );

    final Widget padded = Padding(padding: widget.padding, child: ad);

    return widget.anchored ? SafeArea(top: false, child: padded) : padded;
  }
}
