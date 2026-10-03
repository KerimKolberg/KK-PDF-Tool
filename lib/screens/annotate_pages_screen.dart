import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../services/settings_service.dart';
import '../services/signature_service.dart';
import 'signature_pad_screen.dart';

enum AnnotateMode { fill, draw }

/// A freehand stroke; points are fractions (0..1) of the page size.
class _InkStroke {
  final bool marker;
  final Color color;
  final List<Offset> points = [];
  _InkStroke({required this.marker, required this.color});
}

const _penColors = [Color(0xFF111111), Color(0xFF0D3B9E), Color(0xFFC62828)];
const _markerColors = [Color(0xFFFFEB3B), Color(0xFF9CF27A), Color(0xFFFF9AD5)];
const _textColors = [Color(0xFF111111), Color(0xFF0D3B9E), Color(0xFFC62828)];

/// Pen ~0.7 mm and marker ~4.5 mm on an A4 page, relative to page width.
const _penWidthFrac = 0.0028;
const _markerWidthFrac = 0.022;

/// Paints [page] scaled into [size] plus [strokes] on top. Used both for the
/// on-screen preview and for the final full-resolution render, so what the
/// user sees is exactly what gets saved. Marker strokes multiply with the
/// page like a real highlighter (text underneath stays dark).
void _paintPageWithInk(Canvas canvas, Size size, ui.Image page, List<_InkStroke> strokes) {
  canvas.drawImageRect(
    page,
    Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()),
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.medium,
  );
  for (final stroke in strokes) {
    final pts = [
      for (final p in stroke.points) Offset(p.dx * size.width, p.dy * size.height),
    ];
    if (pts.isEmpty) continue;
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = (stroke.marker ? _markerWidthFrac : _penWidthFrac) * size.width
      ..strokeCap = stroke.marker ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = stroke.marker ? BlendMode.multiply : BlendMode.srcOver;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 1) {
      path.lineTo(pts.first.dx + 0.01, pts.first.dy);
    }
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    if (pts.length > 1) path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(path, paint);
  }
}

class _PagePainter extends CustomPainter {
  final ui.Image page;
  final List<_InkStroke> strokes;
  _PagePainter(this.page, this.strokes);

  @override
  void paint(Canvas canvas, Size size) => _paintPageWithInk(canvas, size, page, strokes);

  @override
  bool shouldRepaint(covariant _PagePainter oldDelegate) => true;
}

Uint8List _encodeRgbaJpegIsolate(Map<String, dynamic> args) {
  final rgba = args['rgba'] as Uint8List;
  final image = img.Image.fromBytes(
    width: args['width'] as int,
    height: args['height'] as int,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: 92);
}

Future<Size> _imageSize(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final size = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
  descriptor.dispose();
  buffer.dispose();
  return size;
}

Future<Uint8List> _pictureToPng(ui.Picture picture, int width, int height) async {
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Renders text as a transparent PNG (any language/characters the system
/// fonts support), so it can be placed and stamped like a signature.
Future<Uint8List> _renderTextPng(String text, Color color) async {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: 96, color: color, height: 1.15),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  const pad = 10.0;
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Offset(pad, pad));
  final width = (painter.width + pad * 2).ceil();
  final height = (painter.height + pad * 2).ceil();
  painter.dispose();
  return _pictureToPng(recorder.endRecording(), width, height);
}

/// ✓ / ✗ drawn as vector strokes (no dependency on a font having the glyph).
Future<Uint8List> _renderMarkPng({required bool check, required Color color}) {
  const size = 120.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()
    ..color = color
    ..strokeWidth = 13
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  if (check) {
    canvas.drawPath(
      Path()
        ..moveTo(18, 64)
        ..lineTo(46, 94)
        ..lineTo(102, 26),
      paint,
    );
  } else {
    canvas
      ..drawLine(const Offset(24, 24), const Offset(96, 96), paint)
      ..drawLine(const Offset(96, 24), const Offset(24, 96), paint);
  }
  return _pictureToPng(recorder.endRecording(), size.toInt(), size.toInt());
}

/// Fill in forms (text, date, ✓/✗, signature) and draw/highlight on page
/// images. Pops with the edited pages (same count/order) or null.
class AnnotatePagesScreen extends StatefulWidget {
  final List<Uint8List> pages;
  final AnnotateMode initialMode;

  const AnnotatePagesScreen({
    super.key,
    required this.pages,
    this.initialMode = AnnotateMode.fill,
  });

  @override
  State<AnnotatePagesScreen> createState() => _AnnotatePagesScreenState();
}

class _AnnotatePagesScreenState extends State<AnnotatePagesScreen> {
  static const _maxUndo = 15;
  static const _maxRenderSide = 3500.0;

  final _signatures = SignatureService();
  late final List<Uint8List> _pages = List.of(widget.pages);
  final List<(int, Uint8List)> _undo = [];
  int _index = 0;
  late AnnotateMode _mode = widget.initialMode;
  bool _changed = false;
  bool _busy = false;

  ui.Image? _display;
  Size? _displayFor; // full-resolution size of the page shown in _display
  int _displayRequest = 0;

  // Placement (fill mode).
  Uint8List? _stamp;
  Size _stampSize = Size.zero;
  double _left = 0.1, _top = 0.1, _width = 0.3;

  // Drawing (draw mode).
  final List<_InkStroke> _strokes = [];
  bool _marker = AppPrefs.getBool('annotate.marker', false);
  int _penColor = AppPrefs.getInt('annotate.penColor', 0).clamp(0, _penColors.length - 1);
  int _markerColor = AppPrefs.getInt('annotate.markerColor', 0).clamp(0, _markerColors.length - 1);
  int _textColor = AppPrefs.getInt('annotate.textColor', 0).clamp(0, _textColors.length - 1);

  bool get _placing => _stamp != null;
  bool get _hasUnsaved => _changed || _strokes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadDisplay();
  }

  @override
  void dispose() {
    _display?.dispose();
    super.dispose();
  }

  /// Decodes the current page at screen resolution for the preview.
  Future<void> _loadDisplay() async {
    final request = ++_displayRequest;
    final bytes = _pages[_index];
    final full = await _imageSize(bytes);
    final longer = math.max(full.width, full.height);
    final scale = longer > 1800 ? 1800 / longer : 1.0;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: (full.width * scale).round(),
      targetHeight: (full.height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    // A newer page/version may have been requested meanwhile.
    if (!mounted || request != _displayRequest) {
      frame.image.dispose();
      return;
    }
    setState(() {
      _display?.dispose();
      _display = frame.image;
      _displayFor = full;
    });
  }

  void _pushUndo(int index) {
    _undo.add((index, _pages[index]));
    if (_undo.length > _maxUndo) _undo.removeAt(0);
  }

  Future<void> _replacePage(int index, Uint8List bytes) async {
    _pushUndo(index);
    _pages[index] = bytes;
    _changed = true;
    if (index == _index) await _loadDisplay();
  }

  /// Renders pending strokes into the current page at full resolution.
  Future<void> _commitStrokes() async {
    if (_strokes.isEmpty) return;
    setState(() => _busy = true);
    try {
      final codec = await ui.instantiateImageCodec(_pages[_index]);
      final frame = await codec.getNextFrame();
      codec.dispose();
      final page = frame.image;
      final longer = math.max(page.width, page.height).toDouble();
      final scale = longer > _maxRenderSide ? _maxRenderSide / longer : 1.0;
      final w = (page.width * scale).round();
      final h = (page.height * scale).round();

      final recorder = ui.PictureRecorder();
      _paintPageWithInk(Canvas(recorder), Size(w.toDouble(), h.toDouble()), page, _strokes);
      final rendered = await recorder.endRecording().toImage(w, h);
      page.dispose();
      final rgba = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
      rendered.dispose();
      final jpeg = await compute(_encodeRgbaJpegIsolate, {
        'rgba': rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        'width': w,
        'height': h,
      });
      _strokes.clear();
      await _replacePage(_index, jpeg);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zeichnung konnte nicht übernommen werden: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goTo(int index) async {
    await _commitStrokes();
    if (!mounted) return;
    setState(() {
      _index = index;
      _stamp = null;
    });
    await _loadDisplay();
  }

  Future<void> _setMode(AnnotateMode mode) async {
    if (mode == _mode) return;
    if (_mode == AnnotateMode.draw) await _commitStrokes();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _stamp = null;
    });
  }

  Future<void> _undoLast() async {
    if (_strokes.isNotEmpty) {
      setState(_strokes.removeLast);
      return;
    }
    if (_undo.isEmpty) return;
    final (index, bytes) = _undo.removeLast();
    _pages[index] = bytes;
    _changed = true;
    if (index != _index) {
      setState(() => _index = index);
    }
    await _loadDisplay();
  }

  Future<void> _finish() async {
    await _commitStrokes();
    if (!mounted) return;
    Navigator.of(context).pop<List<Uint8List>>(_pages);
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasUnsaved) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Änderungen verwerfen?'),
        content: const Text('Text, Unterschriften und Zeichnungen gehen verloren.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Verwerfen')),
        ],
      ),
    );
    return discard ?? false;
  }

  // ---- Placing stamps ----

  Future<void> _startPlacing(Uint8List png, {required double heightFracOfPage}) async {
    final size = await _imageSize(png);
    final page = _displayFor;
    if (!mounted || page == null) return;
    // Size the stamp so it's [heightFracOfPage] of the page tall.
    final widthFrac = heightFracOfPage * page.height * (size.width / size.height) / page.width;
    setState(() {
      _stamp = png;
      _stampSize = size;
      _width = widthFrac.clamp(0.04, 0.95);
      _left = (0.5 - _width / 2).clamp(0.0, 1.0);
      _top = 0.45;
      _clampPlacement();
    });
  }

  double get _heightFrac {
    final page = _displayFor;
    if (page == null || _stampSize.width == 0) return 0.1;
    return _width * page.width * (_stampSize.height / _stampSize.width) / page.height;
  }

  void _clampPlacement() {
    _width = _width.clamp(0.03, 1.0);
    _left = _left.clamp(0.0, 1.0 - _width);
    _top = _top.clamp(0.0, (1.0 - _heightFrac).clamp(0.0, 1.0));
  }

  Future<void> _addText() async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => _TextStampDialog(initialColor: _textColor),
    );
    if (result == null || !mounted) return;
    final (text, colorIndex) = result;
    _textColor = colorIndex;
    AppPrefs.setInt('annotate.textColor', colorIndex);
    final lines = '\n'.allMatches(text).length + 1;
    await _startPlacing(await _renderTextPng(text, _textColors[colorIndex]), heightFracOfPage: 0.022 * lines);
  }

  Future<void> _addDate() async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${two(now.day)}.${two(now.month)}.${now.year}';
    await _startPlacing(await _renderTextPng(date, _textColors[_textColor]), heightFracOfPage: 0.022);
  }

  Future<void> _addMark({required bool check}) async {
    await _startPlacing(
      await _renderMarkPng(check: check, color: _textColors[_textColor]),
      heightFracOfPage: 0.02,
    );
  }

  Future<void> _addSignature() async {
    final chosen = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SignaturePickerSheet(service: _signatures),
    );
    if (chosen == null || !mounted) return;
    await _startPlacing(chosen, heightFracOfPage: 0.06);
  }

  Future<void> _applyStamp() async {
    final stamp = _stamp;
    if (stamp == null || _busy) return;
    setState(() => _busy = true);
    try {
      final stamped = await SignatureService.stamp(
        pageBytes: _pages[_index],
        signaturePng: stamp,
        leftFrac: _left,
        topFrac: _top,
        widthFrac: _width,
      );
      if (!mounted) return;
      await _replacePage(_index, stamped);
      if (mounted) setState(() => _stamp = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Einfügen fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Drawing ----

  Color get _inkColor => _marker ? _markerColors[_markerColor] : _penColors[_penColor];

  void _startStroke(Offset local, Rect page) {
    setState(() {
      _strokes.add(_InkStroke(marker: _marker, color: _inkColor)
        ..points.add(_toPage(local, page)));
    });
  }

  void _extendStroke(Offset local, Rect page) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.points.add(_toPage(local, page)));
  }

  Offset _toPage(Offset local, Rect page) => Offset(
        ((local.dx - page.left) / page.width).clamp(0.0, 1.0),
        ((local.dy - page.top) / page.height).clamp(0.0, 1.0),
      );

  @override
  Widget build(BuildContext context) {
    final display = _display;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        final leave = await _confirmDiscard();
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ausfüllen & Zeichnen'),
          actions: [
            IconButton(
              tooltip: 'Rückgängig',
              onPressed: _busy || _placing || (_strokes.isEmpty && _undo.isEmpty) ? null : _undoLast,
              icon: const Icon(Icons.undo),
            ),
            TextButton.icon(
              onPressed: _hasUnsaved && !_placing && !_busy ? _finish : null,
              icon: const Icon(Icons.check),
              label: const Text('Fertig'),
            ),
          ],
        ),
        body: display == null
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pageSize = Size(display.width.toDouble(), display.height.toDouble());
                    final fitted = applyBoxFit(BoxFit.contain, pageSize, constraints.biggest).destination;
                    final rect = Alignment.center.inscribe(fitted, Offset.zero & constraints.biggest);
                    final drawing = _mode == AnnotateMode.draw && !_busy;
                    return Stack(
                      children: [
                        Positioned.fromRect(
                          rect: rect,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6)],
                            ),
                            child: CustomPaint(painter: _PagePainter(display, _strokes)),
                          ),
                        ),
                        if (drawing)
                          Positioned.fill(
                            child: GestureDetector(
                              onPanStart: (d) => _startStroke(d.localPosition, rect),
                              onPanUpdate: (d) => _extendStroke(d.localPosition, rect),
                            ),
                          ),
                        if (_placing) _buildStampOverlay(rect),
                        if (_busy) const Center(child: CircularProgressIndicator()),
                      ],
                    );
                  },
                ),
              ),
        bottomNavigationBar: SafeArea(child: _buildBottomBar()),
      ),
    );
  }

  Widget _buildBottomBar() {
    final outline = Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pages.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _index > 0 && !_placing && !_busy ? () => _goTo(_index - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Seite ${_index + 1} von ${_pages.length}'),
                IconButton(
                  onPressed: _index < _pages.length - 1 && !_placing && !_busy ? () => _goTo(_index + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          if (_placing) ...[
            Text(
              'Verschieben, Ecke unten rechts zum Vergrößern ziehen',
              style: TextStyle(fontSize: 12, color: outline),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => setState(() => _stamp = null),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _applyStamp,
                    icon: const Icon(Icons.check),
                    label: const Text('Hier platzieren'),
                  ),
                ),
              ],
            ),
          ] else ...[
            SegmentedButton<AnnotateMode>(
              segments: const [
                ButtonSegment(value: AnnotateMode.fill, icon: Icon(Icons.edit_note), label: Text('Ausfüllen')),
                ButtonSegment(value: AnnotateMode.draw, icon: Icon(Icons.brush_outlined), label: Text('Zeichnen')),
              ],
              selected: {_mode},
              onSelectionChanged: _busy ? null : (v) => _setMode(v.first),
            ),
            const SizedBox(height: 10),
            if (_mode == AnnotateMode.fill)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ActionChip(avatar: const Icon(Icons.title, size: 18), label: const Text('Text'), onPressed: _busy ? null : _addText),
                  ActionChip(avatar: const Icon(Icons.today_outlined, size: 18), label: const Text('Datum'), onPressed: _busy ? null : _addDate),
                  ActionChip(avatar: const Icon(Icons.check, size: 18), label: const Text('Haken'), onPressed: _busy ? null : () => _addMark(check: true)),
                  ActionChip(avatar: const Icon(Icons.close, size: 18), label: const Text('Kreuz'), onPressed: _busy ? null : () => _addMark(check: false)),
                  ActionChip(avatar: const Icon(Icons.draw_outlined, size: 18), label: const Text('Unterschrift'), onPressed: _busy ? null : _addSignature),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.center,
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.edit, size: 18),
                    label: const Text('Stift'),
                    selected: !_marker,
                    onSelected: (_) {
                      setState(() => _marker = false);
                      AppPrefs.setBool('annotate.marker', false);
                    },
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.highlight, size: 18),
                    label: const Text('Marker'),
                    selected: _marker,
                    onSelected: (_) {
                      setState(() => _marker = true);
                      AppPrefs.setBool('annotate.marker', true);
                    },
                  ),
                  for (var i = 0; i < 3; i++)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        setState(() {
                          if (_marker) {
                            _markerColor = i;
                          } else {
                            _penColor = i;
                          }
                        });
                        AppPrefs.setInt(_marker ? 'annotate.markerColor' : 'annotate.penColor', i);
                      },
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: (_marker ? _markerColors : _penColors)[i],
                        child: (_marker ? _markerColor : _penColor) == i
                            ? Icon(Icons.check, size: 16, color: _marker ? Colors.black : Colors.white)
                            : null,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Zeichnung auf dieser Seite löschen',
                    onPressed: _strokes.isEmpty || _busy ? null : () => setState(_strokes.clear),
                    icon: const Icon(Icons.layers_clear_outlined),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStampOverlay(Rect page) {
    final w = _width * page.width;
    final h = _heightFrac * page.height;
    final color = Theme.of(context).colorScheme.primary;
    return Positioned(
      left: page.left + _left * page.width,
      top: page.top + _top * page.height,
      width: w,
      height: h,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _left += d.delta.dx / page.width;
          _top += d.delta.dy / page.height;
          _clampPlacement();
        }),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: color, width: 1.5)),
                child: Image.memory(_stamp!, fit: BoxFit.fill, gaplessPlayback: true),
              ),
            ),
            Positioned(
              right: -14,
              bottom: -14,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() {
                  _width += d.delta.dx / page.width;
                  _clampPlacement();
                }),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: color,
                  child: const Icon(Icons.open_in_full, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextStampDialog extends StatefulWidget {
  final int initialColor;
  const _TextStampDialog({required this.initialColor});

  @override
  State<_TextStampDialog> createState() => _TextStampDialogState();
}

class _TextStampDialogState extends State<_TextStampDialog> {
  final _controller = TextEditingController();
  late int _color = widget.initialColor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Text einfügen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'z. B. Name, Adresse, Betrag',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Farbe:'),
              const SizedBox(width: 8),
              for (var i = 0; i < _textColors.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = i),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: _textColors[i],
                      child: _color == i ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (_controller.text.trim(), _color)),
          child: const Text('Einfügen'),
        ),
      ],
    );
  }
}

class _SignaturePickerSheet extends StatefulWidget {
  final SignatureService service;
  const _SignaturePickerSheet({required this.service});

  @override
  State<_SignaturePickerSheet> createState() => _SignaturePickerSheetState();
}

class _SignaturePickerSheetState extends State<_SignaturePickerSheet> {
  List<File>? _files;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await widget.service.list();
    if (mounted) setState(() => _files = files);
  }

  Future<void> _drawNew() async {
    final png = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const SignaturePadScreen()),
    );
    if (png == null || !mounted) return;
    await widget.service.save(png);
    if (!mounted) return;
    Navigator.of(context).pop<Uint8List>(png);
  }

  Future<void> _delete(File file) async {
    await widget.service.delete(file);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Unterschrift wählen', style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Neue Unterschrift zeichnen'),
              onTap: _drawNew,
            ),
            if (files == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final file in files)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              final bytes = await file.readAsBytes();
                              if (context.mounted) Navigator.of(context).pop<Uint8List>(bytes);
                            },
                            child: SizedBox(
                              height: 72,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Image.file(file, fit: BoxFit.contain),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Löschen',
                                    color: Colors.black54,
                                    onPressed: () => _delete(file),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
