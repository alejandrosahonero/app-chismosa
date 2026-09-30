import 'dart:async';

import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/core/routing/app_router.dart';
import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/services/identity/captcha/turnstile.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Android: the Turnstile widget in a 1x1 WebView laid over the app for the
/// few seconds it takes, then removed.
///
/// Attached to the widget tree (an [OverlayEntry]) rather than headless: a
/// WebView that is never attached is not guaranteed to run its scripts. The
/// page is loaded under [BackendConfig.turnstileHost], the hostname the widget
/// is registered for in Cloudflare.
Future<String?> solveTurnstile(String siteKey) async {
  final OverlayState? overlay = rootNavigatorKey.currentState?.overlay;
  if (overlay == null) return null;

  final Completer<String?> result = Completer<String?>();
  final WebViewController controller = WebViewController();
  await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  await controller.addJavaScriptChannel(
    'Captcha',
    onMessageReceived: (JavaScriptMessage message) {
      if (result.isCompleted) return;
      final String text = message.message;
      if (text.startsWith('ok:')) {
        result.complete(text.substring(3));
      } else {
        AppLogger.debug('Turnstile failed: $text', name: 'captcha');
        result.complete(null);
      }
    },
  );

  final OverlayEntry entry = OverlayEntry(
    builder: (BuildContext context) => Positioned(
      left: 0,
      top: 0,
      width: 1,
      height: 1,
      child: IgnorePointer(child: WebViewWidget(controller: controller)),
    ),
  );
  overlay.insert(entry);

  try {
    await controller.loadHtmlString(
      _page(siteKey),
      baseUrl: BackendConfig.turnstileHost,
    );
    return await result.future.timeout(turnstileTimeout, onTimeout: () => null);
  } on Object catch (error) {
    AppLogger.debug('Turnstile page failed: $error', name: 'captcha');
    return null;
  } finally {
    entry.remove();
  }
}

String _page(String siteKey) =>
    '''
<!doctype html><html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<script>
function go() {
  turnstile.render('#t', {
    sitekey: '$siteKey',
    callback: function (t) { Captcha.postMessage('ok:' + t); },
    'error-callback': function (e) { Captcha.postMessage('error:' + e); return true; },
    'expired-callback': function () { Captcha.postMessage('expired'); }
  });
}
</script>
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=go&render=explicit" async
  onerror="Captcha.postMessage('error:script')"></script>
</head><body><div id="t"></div></body></html>''';
