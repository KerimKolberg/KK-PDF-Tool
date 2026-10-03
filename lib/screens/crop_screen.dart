import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/image_processing.dart';
import '../services/settings_service.dart';
import '../widgets/corner_crop_overlay.dart';

/// Lets the user fine-tune the four document corners on a captured photo,
/// optionally rotate it, and pick a filter, before it is flattened into a
/// single processed page. With cropping off it doubles as a "filter and
/// rotate" editor for pages that are already cropped.
class CropScreen extends StatefulWidget {
  final Uint8List initialBytes;
  final bool initialCropEnabled;

  const CropScreen({
    super.key,
    required this.initialBytes,
    this.initialCropEnabled = true,
  });

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  var _overlayKey = GlobalKey<CornerCropOverlayState>();

  Uint8List? _workingBytes;
  double _imgW = 0;
  double _imgH = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  late bool _cropEnabled = widget.initialCropEnabled;

  ScanFilter _filter = AppPrefs.getEnum('scan.filter', ScanFilter.values, ScanFilter.original);
  bool _removeShadows = AppPrefs.getBool('scan.removeShadows', false);

  /// Small copy of the photo used to render filter previews quickly; the
  /// full-resolution image is only processed once on "Übernehmen".
  Uint8List? _previewBase;
  final Map<String, Uint8List> _previewCache = {};
  Uint8List? _previewBytes;
  bool _previewLoading = false;
  int _previewRequest = 0;

  bool get _needsPreview => _filter != ScanFilter.original || _removeShadows;
  String get _previewKey => '${_filter.name}-${_removeShadows && !_filter.includesShadowRemoval}';
  Uint8List get _displayBytes => (_needsPreview ? _previewBytes : null) ?? _workingBytes!;

  @override
  void initState() {
    super.initState();
    _prepare(widget.initialBytes);
  }

  Future<void> _prepare(Uint8List rawBytes) async {
    try {
      final baked = await compute(bakeOrientationJpegIsolate, rawBytes);
      await _setWorkingImage(baked);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Bild konnte nicht geladen werden: $e';
        _loading = false;
      });
    }
  }

  Future<void> _setWorkingImage(Uint8List bytes) async {
    final size = await _decodeSize(bytes);
    final previewBase = await compute(downscaleJpegIsolate, {'bytes': bytes, 'maxSide': 1000});
    if (!mounted) return;
    setState(() {
      _workingBytes = bytes;
      _imgW = size.width;
      _imgH = size.height;
      _previewBase = previewBase;
      _previewCache.clear();
      _previewBytes = null;
    });
    _updatePreview();
  }

  Future<ui.Size> _decodeSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = ui.Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  Future<void> _updatePreview() async {
    if (!_needsPreview) {
      setState(() => _previewLoading = false);
      return;
    }
    final key = _previewKey;
    final cached = _previewCache[key];
    if (cached != null) {
      setState(() {
        _previewBytes = cached;
        _previewLoading = false;
      });
      return;
    }
    final base = _previewBase;
    if (base == null) return;
    final request = ++_previewRequest;
    setState(() => _previewLoading = true);
    try {
      final bytes = await compute(previewFilterIsolate, {
        'bytes': base,
        'filter': _filter.index,
        'shadows': _removeShadows,
      });
      if (!mounted) return;
      _previewCache[key] = bytes;
      // A newer filter choice may have been made meanwhile.
      if (request != _previewRequest) return;
      setState(() {
        _previewBytes = bytes;
        _previewLoading = false;
      });
    } catch (_) {
      if (mounted && request == _previewRequest) setState(() => _previewLoading = false);
    }
  }

  void _selectFilter(ScanFilter filter) {
    setState(() => _filter = filter);
    AppPrefs.setEnum('scan.filter', filter);
    _updatePreview();
  }

  void _setRemoveShadows(bool value) {
    setState(() => _removeShadows = value);
    AppPrefs.setBool('scan.removeShadows', value);
    _updatePreview();
  }

  List<Offset> get _defaultCorners {
    final mx = _imgW * 0.08;
    final my = _imgH * 0.08;
    return [
      Offset(mx, my),
      Offset(_imgW - mx, my),
      Offset(_imgW - mx, _imgH - my),
      Offset(mx, _imgH - my),
    ];
  }

  Future<void> _rotate() async {
    if (_workingBytes == null || _busy) return;
    setState(() => _busy = true);
    try {
      final rotated = await compute(rotateJpeg90Isolate, _workingBytes!);
      _overlayKey = GlobalKey<CornerCropOverlayState>();
      await _setWorkingImage(rotated);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Drehen fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _confirm() async {
    final bytes = _workingBytes;
    if (bytes == null || _busy) return;

    final corners = _cropEnabled
        ? _overlayKey.currentState?.corners
        : [
            const Offset(0, 0),
            Offset(_imgW, 0),
            Offset(_imgW, _imgH),
            Offset(0, _imgH),
          ];
    if (corners == null) return;

    setState(() => _busy = true);
    final cornersFlat = <double>[
      for (final c in corners) ...[c.dx, c.dy],
    ];
    try {
      final processed = await compute(processPageIsolate, {
        'bytes': bytes,
        'corners': cornersFlat,
        'filter': _filter.index,
        'shadows': _removeShadows,
      });
      if (!mounted) return;
      Navigator.of(context).pop<Uint8List>(processed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verarbeitung fehlgeschlagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_cropEnabled ? 'Zuschneiden' : 'Filter & Drehen'),
        actions: [
          IconButton(
            onPressed: _busy ? null : () => setState(() => _cropEnabled = !_cropEnabled),
            icon: Icon(_cropEnabled ? Icons.crop : Icons.crop_free),
            tooltip: _cropEnabled ? 'Zuschnitt aus' : 'Zuschnitt an',
          ),
          IconButton(
            onPressed: _busy ? null : _rotate,
            icon: const Icon(Icons.rotate_right),
            tooltip: 'Drehen',
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final f in scanFilterOrder)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(f.label),
                                selected: _filter == f,
                                onSelected: _busy ? null : (_) => _selectFilter(f),
                              ),
                            ),
                          FilterChip(
                            avatar: const Icon(Icons.wb_shade, size: 18),
                            label: const Text('Schatten entfernen'),
                            tooltip: _filter.includesShadowRemoval
                                ? 'Bei diesem Filter schon enthalten'
                                : null,
                            selected: _removeShadows || _filter.includesShadowRemoval,
                            onSelected: _busy || _filter.includesShadowRemoval
                                ? null
                                : _setRemoveShadows,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _confirm,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check),
                        label: Text(_busy ? 'Verarbeite…' : 'Übernehmen'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_loading || _workingBytes == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final inner = _cropEnabled
        ? CornerCropOverlay(
            key: _overlayKey,
            imageBytes: _displayBytes,
            imageWidth: _imgW,
            imageHeight: _imgH,
            initialCorners: _defaultCorners,
          )
        : Center(
            child: AspectRatio(
              aspectRatio: _imgW / _imgH,
              child: Image.memory(_displayBytes, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          );
    final content = Stack(
      children: [
        Positioned.fill(child: Padding(padding: const EdgeInsets.all(16), child: inner)),
        if (_previewLoading)
          const Positioned(
            top: 8,
            right: 8,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            ),
          ),
      ],
    );

    return _busy ? IgnorePointer(child: content) : content;
  }
}
