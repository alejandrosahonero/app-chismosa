import 'dart:js_interop';

import 'package:chismosa/services/identity/captcha/turnstile.dart';

/// Defined in `web/index.html`: renders the invisible widget off-screen and
/// resolves with its token (or null).
@JS('chismosaTurnstile')
external JSPromise<JSString?> _chismosaTurnstile(JSString siteKey);

/// Web: the page itself runs the widget (see `web/index.html`).
Future<String?> solveTurnstile(String siteKey) async {
  try {
    final JSString? token = await _chismosaTurnstile(
      siteKey.toJS,
    ).toDart.timeout(turnstileTimeout, onTimeout: () => null);
    return token?.toDart;
  } on Object {
    return null;
  }
}
