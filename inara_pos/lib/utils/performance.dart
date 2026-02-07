/// Performance utilities for buttery-smooth POS UX.
/// Platform-aware scroll physics, optimized routes, and reuse helpers.

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

/// Page route with 60fps animation for instant-feel transitions.
/// Avoids heavy MaterialPageRoute default animation.
PageRouteBuilder<T> smoothPageRoute<T>({
  required Widget builder,
  RouteSettings? settings,
  Duration duration = const Duration(milliseconds: 200),
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => builder,
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
