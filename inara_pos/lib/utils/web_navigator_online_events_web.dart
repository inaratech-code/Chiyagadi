import 'dart:html' as html;

/// Fires [onChanged] when `navigator.onLine` may have changed (`online` / `offline`).
void registerNavigatorOnlineChanged(void Function() onChanged) {
  html.window.onOnline.listen((_) => onChanged());
  html.window.onOffline.listen((_) => onChanged());
}
