import 'dart:js_interop';

@JS('open')
external JSAny? _windowOpen(JSString url, JSString target);

/// Same tab: on Android the Play link hands over to the Play Store app.
void openUrl(String url) {
  _windowOpen(url.toJS, '_self'.toJS);
}
