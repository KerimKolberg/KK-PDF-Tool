import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/image_processing.dart';
import '../services/settings_service.dart';
import 'capture_screen.dart';
import 'crop_screen.dart';

class _Page {
  final int key;
  Uint8List bytes;
  _Page(this.key, this.bytes);
}

/// Reorder, rotate, delete and add pages. Pops with the edited page images,
/// or null if nothing was changed / the user backed out.
class EditPagesScreen extends StatefulWidget {
  final List<Uint8List> pages;

  const EditPagesScreen({super.key, required this.pages});

  @override
  State<EditPagesScreen> createState() => _EditPagesScreenState();
}

class _EditPagesScreenState extends State<EditPagesScreen> {
  late final List<_Page> _pages = [
    for (var i = 0; i < widget.pages.length; i++) _Page(i, widget.pages[i]),
  ];
  late int _nextKey = widget.pages.length;
  final Set<int> _rotating = {};
  bool _changed = false;

  void _markChanged() => _changed = true;

  Future<void> _rotate(_Page page) async {
    if (_rotating.contains(page.key)) return;
    setState(() => _rotating.add(page.key));
    try {
      final rotated = await compute(rotateJpeg90Isolate, page.bytes);
      if (!mounted) return;
      setState(() {
        page.bytes = rotated;
        _markChanged();
      });
    } finally {
      if (mounted) setState(() => _rotating.remove(page.key));
    }
  }

  void _delete(int index) {
    setState(() {
      _pages.removeAt(index);
      _markChanged();
    });
  }

  Future<void> _addPage() async {
    final cropEnabled = await SettingsService().getCropEnabledDefault();
    if (!mounted) return;
    final raw = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
    );
    if (raw == null || !mounted) return;
    final processed = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => CropScreen(initialBytes: raw, initialCropEnabled: cropEnabled),
      ),
    );
    if (processed == null || !mounted) return;
    setState(() {
      _pages.add(_Page(_nextKey++, processed));
      _markChanged();
    });
  }

  void _save() {
    Navigator.of(context).pop<List<Uint8List>>([for (final p in _pages) p.bytes]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Seiten bearbeiten (${_pages.length})')),
      body: _pages.isEmpty
          ? Center(
              child: Text(
                'Keine Seiten mehr - füge mindestens eine hinzu.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _pages.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = _pages.removeAt(oldIndex);
                  _pages.insert(newIndex, item);
                  _markChanged();
                });
              },
              itemBuilder: (context, i) {
                final page = _pages[i];
                return Card(
                  key: ValueKey(page.key),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.memory(
                            page.bytes,
                            width: 64,
                            height: 88,
                            fit: BoxFit.cover,
                            cacheWidth: 200,
                            gaplessPlayback: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Seite ${i + 1}')),
                        IconButton(
                          tooltip: 'Drehen',
                          onPressed: _rotating.contains(page.key) ? null : () => _rotate(page),
                          icon: _rotating.contains(page.key)
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.rotate_right),
                        ),
                        IconButton(
                          tooltip: 'Löschen',
                          onPressed: () => _delete(i),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        const SizedBox(width: 24), // room for the drag handle
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addPage,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Seite hinzufügen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _changed && _pages.isNotEmpty && _rotating.isEmpty ? _save : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Speichern'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
