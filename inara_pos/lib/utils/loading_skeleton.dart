/// Lightweight loading skeleton placeholders.
/// Use instead of spinners for data loading - reduces perceived latency.

import 'package:flutter/material.dart';

/// Shimmer effect for skeleton - uses simple opacity animation.
class ShimmerEffect extends StatefulWidget {
  final Widget child;

  const ShimmerEffect({super.key, required this.child});

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _animation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Opacity(
        opacity: _animation.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Rectangular skeleton placeholder.
Widget buildSkeletonBox({
  double? width,
  double height = 16,
  BorderRadius? borderRadius,
}) {
  return ShimmerEffect(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[350],
        borderRadius: borderRadius ?? BorderRadius.circular(4),
      ),
    ),
  );
}

/// Card skeleton for order/product lists.
Widget buildCardSkeleton({int lines = 3}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSkeletonBox(width: 120, height: 14),
        const SizedBox(height: 12),
        ...List.generate(
          lines,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: buildSkeletonBox(height: 12),
          ),
        ),
      ],
    ),
  );
}

/// Grid of skeleton cards for menu/product grids.
Widget buildGridSkeleton({
  int count = 6,
  int crossAxisCount = 3,
  double aspectRatio = 0.85,
}) {
  return GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      childAspectRatio: aspectRatio,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    ),
    itemCount: count,
    itemBuilder: (_, __) => ShimmerEffect(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}
