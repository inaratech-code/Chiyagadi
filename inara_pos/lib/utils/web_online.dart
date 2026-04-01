import 'package:flutter/foundation.dart' show kIsWeb;

import 'web_online_impl_stub.dart'
    if (dart.library.html) 'web_online_impl_web.dart' as impl;

/// Mirrors `navigator.onLine` on web (same signal as [ConnectivityNotifier]); non-web is always online.
bool get isNavigatorOnline {
  if (!kIsWeb) return true;
  return impl.webNavigatorOnLine();
}
