import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/services/identity/captcha/turnstile_mobile.dart'
    if (dart.library.js_interop) 'package:chismosa/services/identity/captcha/turnstile_web.dart'
    as impl;

/// Returns a fresh, single-use Cloudflare Turnstile token, or null when none
/// could be obtained (no network, widget error, timeout).
///
/// Why: signing up anonymously is free, so a script could mint accounts
/// forever and burn the free plan's quotas. With "CAPTCHA protection" on in
/// Supabase Auth, every anonymous sign-up and password sign-in must carry one
/// of these tokens, and only a real browser or a real app can produce it. The
/// widget is Turnstile's *invisible* mode: nobody ever sees a challenge.
typedef CaptchaTokenSource = Future<String?> Function();

/// Null while no site key is configured: then no token is asked for, which
/// matches Supabase with CAPTCHA protection off.
CaptchaTokenSource? turnstileTokenSource() {
  const String key = BackendConfig.turnstileSiteKey;
  if (key.isEmpty) return null;
  return () => impl.solveTurnstile(key);
}

/// How long to wait for a token before giving up. The sign-in then fails like
/// any other network error, and the app retries on the next start.
const Duration turnstileTimeout = Duration(seconds: 20);
