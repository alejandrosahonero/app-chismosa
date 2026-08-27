import 'package:aja/core/widgets/adaptive_banner_ad.dart';
import 'package:flutter/material.dart';

/// Standard screen shell for the app.
///
/// Every screen should be built on top of this instead of a bare [Scaffold] so
/// the banner placement policy lives in exactly one place.
///
/// The banner is laid out **below** the content inside a [Column], never
/// stacked on top of it. Content therefore shrinks by the banner height instead
/// of being covered, which is what keeps accidental clicks — and AdMob
/// suspensions — away.
///
/// Set `showBanner: false` on screens with dense controls, forms, onboarding,
/// or any destructive action near the bottom edge. The project guide only
/// recommends banners on list/consultation screens.
class BaseScreen extends StatelessWidget {
  const BaseScreen({
    required this.body,
    super.key,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.bottomBar,
    this.showBanner = true,
    this.padding = EdgeInsets.zero,
    this.leading,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;

  /// Navigation bar, rendered under the banner.
  final Widget? bottomBar;

  final bool showBanner;
  final EdgeInsetsGeometry padding;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: title == null
          ? null
          : AppBar(title: Text(title!), actions: actions, leading: leading),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(padding: padding, child: body),
            ),
            if (showBanner) const AdaptiveBannerAd(),
          ],
        ),
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}
