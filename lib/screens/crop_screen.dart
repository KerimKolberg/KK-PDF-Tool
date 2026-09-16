import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/image_processing.dart';
import '../widgets/corner_crop_overlay.dart';

/// Lets the user fine-tune the four document corners on a captured photo,
/// optionally rotate it, and pick a filter, before it is flattened into a
/// single processed page.
class CropScreen extends StatefulWidget {
  final Uint8List initialBytes;

  const CropScreen({super.key, required this.initialBytes});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _overlayKey = GlobalKey<CornerCropOverlayState>();

  Uint8List? _workingBytes;
  double _imgW = 0;
  double _imgH = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  ScanFilter _filter = ScanFilter.original;

  static const _grayscaleMatrix = <double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  void initState() {
    super.initState();
    _prepare(widget.initialBytes);
  }

  Future<void> _prepare(Uint8List rawBytes) async {
    try {
      final baked = await compute(bakeOrientationJpegIsolate, rawBytes);
      final size = await _decodeSize(baked);
      if (!mounted) return;
      setState(() {
        _workingBytes = baked;
        _imgW = size.width;
        _imgH = size.height;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Bild konnte nicht geladen werden: $e';
        _loading = false;
      });
    }
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
      final size = await _decodeSize(rotated);
      if (!mounted) return;
      setState(() {
        _workingBytes = rotated;
        _imgW = size.width;
        _imgH = size.height;
        _busy = false;
      });
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
    final overlayState = _overlayKey.currentState;
    if (bytes == null || overlayState == null || _busy) return;

    setState(() => _busy = true);
    final corners = overlayState.corners;
    final cornersFlat = <double>[
      for (final c in corners) ...[c.dx, c.dy],
    ];
    try {
      final processed = await compute(processPageIsolate, {
        'bytes': bytes,
        'corners': cornersFlat,
        'filter': _filter.index,
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

  ColorFilter? get _previewColorFilter {
    switch (_filter) {
      case ScanFilter.original:
      case ScanFilter.enhanced:
        return null;
      case ScanFilter.grayscale:
      case ScanFilter.blackAndWhite:
        return const ColorFilter.matrix(_grayscaleMatrix);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Zuschneiden'),
        actions: [
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
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: ScanFilter.values.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final f = ScanFilter.values[i];
                          return ChoiceChip(
                            label: Text(f.label),
                            selected: _filter == f,
                            onSelected: _busy
                                ? null
                                : (_) => setState(() => _filter = f),
                          );
                        },
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
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
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

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: _previewColorFilter == null
          ? CornerCropOverlay(
              key: _overlayKey,
              imageBytes: _workingBytes!,
              imageWidth: _imgW,
              imageHeight: _imgH,
              initialCorners: _defaultCorners,
            )
          : ColorFiltered(
              colorFilter: _previewColorFilter!,
              child: CornerCropOverlay(
                key: _overlayKey,
                imageBytes: _workingBytes!,
                imageWidth: _imgW,
                imageHeight: _imgH,
                initialCorners: _defaultCorners,
              ),
            ),
    );

    return _busy ? IgnorePointer(child: content) : content;
  }
}
