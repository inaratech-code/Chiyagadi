import 'dart:html' as html;

bool webNavigatorOnLine() => html.window.navigator.onLine ?? true;
