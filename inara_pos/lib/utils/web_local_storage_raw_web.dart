import 'dart:html' as html;

/// Unprefixed `localStorage` so React `localStorage.getItem("menu")` matches Flutter.
String? webLocalStorageGet(String key) {
  try {
    return html.window.localStorage[key];
  } catch (_) {
    return null;
  }
}

void webLocalStorageSet(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (_) {}
}

void webLocalStorageRemove(String key) {
  try {
    html.window.localStorage.remove(key);
  } catch (_) {}
}
