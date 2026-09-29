import 'package:chismosa/core/utils/open_url_stub.dart'
    if (dart.library.js_interop) 'package:chismosa/core/utils/open_url_web.dart'
    as impl;

/// Opens [url] in the browser. Web only; a no-op on Android, where the app
/// has no reason to send anyone to a web page (and no `url_launcher`).
///
/// Built on `dart:js_interop` through a conditional import instead of adding a
/// package: this is one call to `window.open`.
void openUrl(String url) => impl.openUrl(url);
