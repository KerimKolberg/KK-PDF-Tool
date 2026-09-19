import 'dart:typed_data';

import 'package:flutter/material.dart';

double _clampD(double v, double lo, double hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

/// Displays [imageBytes] scaled to fit and overlays a draggable axis-aligned
/// rectangle (via its top-left and bottom-right corners) for defining a
/// crop area - simpler than [CornerCropOverlay] since PDF pages don't need
/// perspective correction, just a margin trim.
class RectCropOverlay extends StatefulWidget {
  final Uint8List imageBytes;
  final double imageWidth;
  final double imageHeight;

  const RectCropOverlay({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  State<RectCropOverlay> createState() => RectCropOverlayState();
}

class RectCropOverlayState extends State<RectCropOverlay> {
  late Offset _topLeft;
  late Offset _bottomRight;

  @override
  void initState() {
    super.initState();
    final mx = widget.imageWidth * 0.08;
    final my = widget.imageHeight * 0.08;
    _topLeft = Offset(mx, my);
    _bottomRight = Offset(widget.imageWidth - mx, widget.imageHeight - my);
  }

  /// Current crop rectangle as fractions (0..1) of the image dimensions.
  ({double left, double top, double right, double bottom}) get fractionalRect => (
        left: _topLeft.dx / widget.imageWidth,
        top: _topLeft.dy / widget.imageHeight,
        right: _bottomRight.dx / widget.imageWidth,
        bottom: _bottomRight.dy / widget.imageHeight,
      );

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

        final dTopLeft = toDisplay(_topLeft);
        final dBottomRight = toDisplay(_bottomRight);

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
                      painter: _RectPainter(dTopLeft, dBottomRight),
                    ),
                  ),
                ),
                _handle(
                  position: dTopLeft,
                  onDrag: (delta) {
                    setState(() {
                      final next = Offset(
                        _clampD(dTopLeft.dx + delta.dx, 0, dBottomRight.dx - 20),
                        _clampD(dTopLeft.dy + delta.dy, 0, dBottomRight.dy - 20),
                      );
                      _topLeft = toImage(next);
                    });
                  },
                ),
                _handle(
                  position: dBottomRight,
                  onDrag: (delta) {
                    setState(() {
                      final next = Offset(
                        _clampD(dBottomRight.dx + delta.dx, dTopLeft.dx + 20, displayW),
                        _clampD(dBottomRight.dy + delta.dy, dTopLeft.dy + 20, displayH),
                      );
                      _bottomRight = toImage(next);
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _handle({
    required Offset position,
    required ValueChanged<Offset> onDrag,
  }) {
    const size = 32.0;
    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDrag(details.delta),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.blueAccent, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}

class _RectPainter extends CustomPainter {
  final Offset topLeft;
  final Offset bottomRight;

  _RectPainter(this.topLeft, this.bottomRight);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(topLeft, bottomRight);
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutout = Path.combine(
      PathOperation.difference,
      full,
      Path()..addRect(rect),
    );
    canvas.drawPath(cutout, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _RectPainter oldDelegate) =>
      oldDelegate.topLeft != topLeft || oldDelegate.bottomRight != bottomRight;
}
