import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _Stroke {
  final List<Offset> points;
  final Color color;
  _Stroke(this.color) : points = [];
}

void _paintStrokes(Canvas canvas, List<_Stroke> strokes, double width) {
  for (final stroke in strokes) {
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final pts = stroke.points;
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, width / 2, paint..style = PaintingStyle.fill);
      continue;
    }
    // Quadratic curves through segment midpoints give a smooth ink line.
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  }
}

class _StrokesPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final double strokeWidth;
  _StrokesPainter(this.strokes, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) => _paintStrokes(canvas, strokes, strokeWidth);

  @override
  bool shouldRepaint(covariant _StrokesPainter oldDelegate) => true;
}

/// Lets the user draw a signature with finger/pen/mouse. Pops with a
/// transparent PNG trimmed to the drawn area.
class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  static const _strokeWidth = 3.5;
  static const _inkColors = [Color(0xFF111111), Color(0xFF0D3B9E)];

  final List<_Stroke> _strokes = [];
  Color _color = _inkColors.first;
  bool _saving = false;

  void _start(Offset p) => setState(() => _strokes.add(_Stroke(_color)..points.add(p)));
  void _extend(Offset p) => setState(() => _strokes.last.points.add(p));

  Future<void> _save() async {
    if (_strokes.isEmpty || _saving) return;
    setState(() => _saving = true);

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final s in _strokes) {
      for (final p in s.points) {
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
    }
    const pad = _strokeWidth * 2;
    final bounds = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
    const ratio = 3.0; // render at 3x for a crisp signature when enlarged

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(ratio)
      ..translate(-bounds.left, -bounds.top);
    _paintStrokes(canvas, _strokes, _strokeWidth);
    final image = await recorder.endRecording().toImage(
          (bounds.width * ratio).ceil(),
          (bounds.height * ratio).ceil(),
        );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (!mounted) return;
    Navigator.of(context).pop<Uint8List>(data!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unterschrift zeichnen'),
        actions: [
          IconButton(
            tooltip: 'Rückgängig',
            onPressed: _strokes.isEmpty ? null : () => setState(_strokes.removeLast),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Leeren',
            onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 48,
                      child: Container(height: 1, color: Colors.black26),
                    ),
                    if (_strokes.isEmpty)
                      const Center(
                        child: Text('Hier unterschreiben', style: TextStyle(color: Colors.black38)),
                      ),
                    Positioned.fill(
                      child: GestureDetector(
                        onPanStart: (d) => _start(d.localPosition),
                        onPanUpdate: (d) => _extend(d.localPosition),
                        child: CustomPaint(painter: _StrokesPainter(_strokes, _strokeWidth)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Farbe:'),
                const SizedBox(width: 8),
                for (final c in _inkColors)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => setState(() => _color = c),
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: c,
                        child: _color == c
                            ? const Icon(Icons.check, size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _strokes.isEmpty || _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Unterschrift speichern'),
          ),
        ),
      ),
    );
  }
}
