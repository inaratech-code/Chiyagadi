import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

/// Milliseconds to wait before showing a full-screen loading indicator.
/// Shorter on iOS so feedback appears sooner; avoids spinner flash on fast loads elsewhere.
int get kDeferLoadingMs {
  if (defaultTargetPlatform == TargetPlatform.iOS) return 80;
  return 100;
}
