import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A rounded rectangle with a dashed outline - the usual "drop files here"
/// look.
class DashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;

  const DashedBorder({super.key, required this.child, required this.color, this.radius = 14});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(foregroundPainter: _DashedRRectPainter(color, radius), child: child);
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedRRectPainter(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.75),
      );
    const dash = 7.0, gap = 5.0;
    for (final ui.PathMetric metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) => old.color != color || old.radius != radius;
}

/// Shown over a window or tool while files are dragged over it.
class DropOverlay extends StatelessWidget {
  final String message;

  const DropOverlay({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ColoredBox(
        color: scheme.surface.withValues(alpha: 0.85),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DashedBorder(
            color: scheme.primary,
            radius: 20,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_download_outlined, size: 56, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
