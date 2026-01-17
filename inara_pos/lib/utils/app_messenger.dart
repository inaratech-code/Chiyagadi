import 'package:flutter/material.dart';

/// Global app-wide messenger so SnackBars always appear in the same place
/// (the root MaterialApp), regardless of which page/dialog triggers them.
class AppMessenger {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  // Used to get a stable BuildContext for screen sizing (centered snackbars).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static void showSnackBar(
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 3),
    String? leadingAssetPath,
    IconData? leadingIcon,
    Color? leadingIconColor,
  }) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    final ctx = navigatorKey.currentContext;
    final size = ctx != null ? MediaQuery.sizeOf(ctx) : null;
    // Center-ish on screen. Clamp so it never goes off-screen on small devices.
    final bottom = size != null
        ? (size.height * 0.45).clamp(24.0, size.height - 120.0)
        : 120.0;

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: _AnimatedSnackContent(
            message: message,
            duration: duration,
            leadingAssetPath: leadingAssetPath,
            leadingIcon: leadingIcon,
            leadingIconColor: leadingIconColor,
          ),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(left: 16, right: 16, bottom: bottom),
          duration: duration,
        ),
      );
  }
}

class _AnimatedSnackContent extends StatelessWidget {
  final String message;
  final Duration duration;
  final String? leadingAssetPath;
  final IconData? leadingIcon;
  final Color? leadingIconColor;

  const _AnimatedSnackContent({
    required this.message,
    required this.duration,
    this.leadingAssetPath,
    this.leadingIcon,
    this.leadingIconColor,
  });

  Widget _buildLeading(BuildContext context) {
    final iconColor = leadingIconColor ?? Theme.of(context).colorScheme.primary;
    final child = leadingAssetPath != null
        ? Image.asset(
            leadingAssetPath!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              leadingIcon ?? Icons.check_circle,
              size: 18,
              color: iconColor,
            ),
          )
        : (leadingIcon != null
            ? Icon(leadingIcon, size: 18, color: iconColor)
            : Image.asset(
                'assets/images/logo.jpeg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.local_cafe,
                  size: 16,
                  color: Colors.black87,
                ),
              ));

    // Simple “pop in” animation for the image/icon.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.75, end: 1.0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, value, _) => Transform.scale(
        scale: value,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).snackBarTheme.backgroundColor;
    final trackColor = (bg ?? Colors.black).withOpacity(0.18);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
              ),
              child: ClipOval(
                child: _buildLeading(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: 0.0),
            duration: duration,
            builder: (context, value, _) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: trackColor,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
