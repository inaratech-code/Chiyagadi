import 'package:flutter/foundation.dart' show kIsWeb;

import 'web_online_impl_stub.dart'
    if (dart.library.html) 'web_online_impl_web.dart' as impl;

/// Mirrors `navigator.onLine` on web; non-web is always "online" (SQLite).
bool get isNavigatorOnline {
  if (!kIsWeb) return true;
  return impl.webNavigatorOnLine();
}
