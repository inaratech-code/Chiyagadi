/// Performance utilities for buttery-smooth POS UX.
/// Platform-aware scroll physics, optimized routes, debounce, and reuse helpers.

import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

/// Platform-aware scroll physics: BouncingScrollPhysics on iOS/Web, ClampingScrollPhysics on Android.
/// Use for ListView, GridView, CustomScrollView for native feel.
ScrollPhysics get platformScrollPhysics {
  if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
    return const BouncingScrollPhysics();
  }
  return const ClampingScrollPhysics();
}

/// Default cache extent for ListView/GridView - preloads offscreen items for smooth scroll.
const double kDefaultCacheExtent = 500;

/// Page route with 60fps fade animation. Lightweight, hardware-accelerated.
PageRouteBuilder<T> smoothPageRoute<T>({
  required Widget Function(BuildContext) builder,
  RouteSettings? settings,
  Duration duration = const Duration(milliseconds: 200),
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ),
        child: child,
      );
    },
    transitionDuration: duration,
  );
}

/// Slide-up page route for modal-style screens (settings, detail).
PageRouteBuilder<T> smoothSlidePageRoute<T>({
  required Widget Function(BuildContext) builder,
  RouteSettings? settings,
  Duration duration = const Duration(milliseconds: 250),
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(0.0, 0.05);
      const end = Offset.zero;
      const curve = Curves.easeOutCubic;
      var tween = Tween(begin: begin, end: end).chain(
        CurveTween(curve: curve),
      );
      return SlideTransition(
        position: animation.drive(tween),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: curve),
          child: child,
        ),
      );
    },
    transitionDuration: duration,
  );
}

/// Debounces rapid taps to prevent double-submit and input lag. Use for POS buttons.
class TapDebouncer {
  TapDebouncer({this.cooldownMs = 300});

  final int cooldownMs;
  DateTime? _lastTap;

  bool get canTap {
    if (_lastTap == null) return true;
    return DateTime.now().difference(_lastTap!).inMilliseconds >= cooldownMs;
  }

  void recordTap() => _lastTap = DateTime.now();

  /// Returns true if tap was allowed (not debounced). Call recordTap() when action completes.
  bool onTap(VoidCallback action) {
    if (!canTap) return false;
    _lastTap = DateTime.now();
    action();
    return true;
  }
}

/// Async debouncer for search/filter - delays execution until user stops typing.
class Debouncer {
  Debouncer({this.milliseconds = 300});

  final int milliseconds;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void cancel() {
    _timer?.cancel();
  }
}
