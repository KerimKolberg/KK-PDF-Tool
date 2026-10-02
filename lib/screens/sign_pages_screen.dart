import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/signature_service.dart';
import 'signature_pad_screen.dart';

Future<Size> _imageSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  frame.image.dispose();
  codec.dispose();
  return size;
}

/// Places one or more signatures on page images. Pops with the signed page
/// images (same order/count as given) once at least one signature was
/// applied, or null when cancelled.
class SignPagesScreen extends StatefulWidget {
  final List<Uint8List> pages;

  const SignPagesScreen({super.key, required this.pages});

  @override
  State<SignPagesScreen> createState() => _SignPagesScreenState();
}

class _SignPagesScreenState extends State<SignPagesScreen> {
  final _signatures = SignatureService();
  late final List<Uint8List> _pages = List.of(widget.pages);
  final Map<int, Size> _pageSizes = {};
  int _index = 0;
  bool _changed = false;
  bool _busy = false;

  // Signature currently being placed (null = not placing).
  Uint8List? _sig;
  Size _sigSize = Size.zero;
  double _left = 0.55, _top = 0.78, _width = 0.3;

  @override
  void initState() {
    super.initState();
    _ensureSize(0);
  }

  Future<void> _ensureSize(int index) async {
    if (_pageSizes.containsKey(index)) return;
    final size = await _imageSize(_pages[index]);
    if (mounted) setState(() => _pageSizes[index] = size);
  }

  void _goTo(int index) {
    setState(() => _index = index);
    _ensureSize(index);
  }

  Future<void> _chooseSignature() async {
    final chosen = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SignaturePickerSheet(service: _signatures),
    );
    if (chosen == null || !mounted) return;
    final size = await _imageSize(chosen);
    setState(() {
      _sig = chosen;
      _sigSize = size;
      _width = 0.3;
      _left = 0.55;
      _top = 0.78;
      _clampPlacement();
    });
  }

  double get _heightFrac {
    final page = _pageSizes[_index];
    if (page == null || _sigSize.width == 0) return 0.1;
    return _width * page.width * (_sigSize.height / _sigSize.width) / page.height;
  }

  void _clampPlacement() {
    _width = _width.clamp(0.08, 1.0);
    _left = _left.clamp(0.0, 1.0 - _width);
    _top = _top.clamp(0.0, (1.0 - _heightFrac).clamp(0.0, 1.0));
  }

  Future<void> _apply() async {
    final sig = _sig;
    if (sig == null || _busy) return;
    setState(() => _busy = true);
    try {
      final stamped = await SignatureService.stamp(
        pageBytes: _pages[_index],
        signaturePng: sig,
        leftFrac: _left,
        topFrac: _top,
        widthFrac: _width,
      );
      if (!mounted) return;
      setState(() {
        _pages[_index] = stamped;
        _pageSizes.remove(_index);
        _sig = null;
        _changed = true;
        _busy = false;
      });
      _ensureSize(_index);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unterschreiben fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageSize = _pageSizes[_index];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unterschreiben'),
        actions: [
          TextButton.icon(
            onPressed: _changed && _sig == null && !_busy
                ? () => Navigator.of(context).pop<List<Uint8List>>(_pages)
                : null,
            icon: const Icon(Icons.check),
            label: const Text('Fertig'),
          ),
        ],
      ),
      body: pageSize == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fitted = applyBoxFit(BoxFit.contain, pageSize, constraints.biggest).destination;
                  final rect = Alignment.center.inscribe(fitted, Offset.zero & constraints.biggest);
                  return Stack(
                    children: [
                      Positioned.fromRect(
                        rect: rect,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6)],
                          ),
                          child: Image.memory(_pages[_index], fit: BoxFit.fill, gaplessPlayback: true),
                        ),
                      ),
                      if (_sig != null) _buildOverlay(rect),
                    ],
                  );
                },
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pages.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _index > 0 && _sig == null ? () => _goTo(_index - 1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('Seite ${_index + 1} von ${_pages.length}'),
                    IconButton(
                      onPressed: _index < _pages.length - 1 && _sig == null
                          ? () => _goTo(_index + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              if (_sig == null)
                FilledButton.icon(
                  onPressed: pageSize == null ? null : _chooseSignature,
                  icon: const Icon(Icons.draw_outlined),
                  label: const Text('Unterschrift einfügen'),
                )
              else ...[
                Text(
                  'Unterschrift verschieben, Ecke unten rechts zum Vergrößern ziehen',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => setState(() => _sig = null),
                        child: const Text('Abbrechen'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _apply,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check),
                        label: const Text('Hier platzieren'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(Rect page) {
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
                child: Image.memory(_sig!, fit: BoxFit.fill),
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
