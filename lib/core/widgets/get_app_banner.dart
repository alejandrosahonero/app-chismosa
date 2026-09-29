import 'package:chismosa/core/config/links_config.dart';
import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/theme/app_colors.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/utils/open_url.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this is the web app running in an Android browser: the only place
/// where offering the app makes sense, because Google Play is the only store.
/// Flutter web reports the platform from the browser's user agent.
bool get isAndroidBrowser =>
    kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Opens the Play listing. On Android the link hands over to the Play Store.
void openPlayStore() => openUrl(LinksConfig.playStore);

/// A one-line strip above the deck offering the Android app, with a close
/// button. Closing it is remembered: after that the drawer entry is enough.
///
/// Renders nothing outside an Android browser.
class GetAppBanner extends ConsumerStatefulWidget {
  const GetAppBanner({super.key});

  static const String dismissedKey = 'get_app_banner_dismissed';

  @override
  ConsumerState<GetAppBanner> createState() => _GetAppBannerState();
}

class _GetAppBannerState extends ConsumerState<GetAppBanner> {
  late bool _hidden =
      !isAndroidBrowser ||
      ref.read(keyValueStoreProvider).getBool(GetAppBanner.dismissedKey);

  void _dismiss() {
    setState(() => _hidden = true);
    ref
        .read(keyValueStoreProvider)
        .setBool(GetAppBanner.dismissedKey, value: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();

    return Material(
      color: AppColors.maroon,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                context.l10n.webGetAppBody,
                style: context.texts.bodyMedium?.copyWith(
                  color: AppColors.bone,
                ),
              ),
            ),
            TextButton(
              onPressed: openPlayStore,
              style: TextButton.styleFrom(foregroundColor: AppColors.bone),
              child: Text(
                context.l10n.webGetAppCta,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: _dismiss,
              icon: const Icon(Icons.close, color: AppColors.bone),
              tooltip: context.l10n.commonClose,
            ),
          ],
        ),
      ),
    );
  }
}
