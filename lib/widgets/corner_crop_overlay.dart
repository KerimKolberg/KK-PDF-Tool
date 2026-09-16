import 'dart:typed_data';

import 'package:flutter/material.dart';

double _clampD(double v, double lo, double hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

/// Displays [imageBytes] scaled to fit and overlays a draggable
/// quadrilateral (topLeft, topRight, bottomRight, bottomLeft) that the user
/// can adjust to mark the document edges, similar to classic scanner apps.
class CornerCropOverlay extends StatefulWidget {
  final Uint8List imageBytes;
  final double imageWidth;
  final double imageHeight;
  final List<Offset> initialCorners;

  const CornerCropOverlay({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.initialCorners,
  });

  @override
  State<CornerCropOverlay> createState() => CornerCropOverlayState();
}

class CornerCropOverlayState extends State<CornerCropOverlay> {
  late List<Offset> _corners;

  /// Current corner positions in image pixel space, ordered
  /// topLeft, topRight, bottomRight, bottomLeft.
  List<Offset> get corners => _corners;

  @override
  void initState() {
    super.initState();
    _corners = List.of(widget.initialCorners);
  }

  @override
  void didUpdateWidget(covariant CornerCropOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBytes != widget.imageBytes) {
      _corners = List.of(widget.initialCorners);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final imageAspect = widget.imageWidth / widget.imageHeight;

        double displayW = maxW;
        double displayH = displayW / imageAspect;
        if (displayH > maxH) {
          displayH = maxH;
          displayW = displayH * imageAspect;
        }
        final scale = displayW / widget.imageWidth;

        Offset toDisplay(Offset p) => Offset(p.dx * scale, p.dy * scale);
        Offset toImage(Offset p) => Offset(p.dx / scale, p.dy / scale);

        return Center(
          child: SizedBox(
            width: displayW,
            height: displayH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Image.memory(widget.imageBytes, fit: BoxFit.fill),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter:
                          _QuadPainter(_corners.map(toDisplay).toList()),
                    ),
                  ),
                ),
                for (var i = 0; i < _corners.length; i++)
                  _buildHandle(
                    i,
                    toDisplay(_corners[i]),
                    displayW,
                    displayH,
                    toImage,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHandle(
    int index,
    Offset displayPos,
    double maxW,
    double maxH,
    Offset Function(Offset) toImage,
  ) {
    const handleSize = 32.0;
    return Positioned(
      left: displayPos.dx - handleSize / 2,
      top: displayPos.dy - handleSize / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          setState(() {
            final newDisplay = displayPos + details.delta;
            final clamped = Offset(
              _clampD(newDisplay.dx, 0, maxW),
              _clampD(newDisplay.dy, 0, maxH),
            );
            _corners[index] = toImage(clamped);
          });
        },
        child: Container(
          width: handleSize,
          height: handleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.blueAccent, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final List<Offset> points;

  _QuadPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;
    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutout = Path.combine(PathOperation.difference, full, path);
    canvas.drawPath(cutout, Paint()..color = Colors.black.withValues(alpha: 0.45));

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    for (final pt in points) {
      canvas.drawCircle(pt, 4, Paint()..color = Colors.blueAccent);
    }
  }

  @override
  bool shouldRepaint(covariant _QuadPainter oldDelegate) =>
      oldDelegate.points != points;
}
