import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/image_processing.dart';
import '../services/settings_service.dart';
import 'capture_screen.dart';
import 'crop_screen.dart';
import '../l10n.dart';

class _Page {
  final int key;
  Uint8List bytes;
  _Page(this.key, this.bytes);
}

/// Reorder, rotate, delete, duplicate and add pages - one at a time or
/// several selected pages together. Pops with the edited page images,
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
      _selected.remove(_pages[index].key);
      _pages.removeAt(index);
      _markChanged();
    });
  }

  // --- Selection: several pages can be moved, rotated, duplicated or
  // deleted together.

  final Set<int> _selected = {};

  bool get _selecting => _selected.isNotEmpty;
  List<_Page> get _selectedPages => [for (final p in _pages) if (_selected.contains(p.key)) p];

  void _toggle(_Page page) => setState(() {
        if (!_selected.remove(page.key)) _selected.add(page.key);
      });

  void _selectAll() => setState(() {
        if (_selected.length == _pages.length) {
          _selected.clear();
        } else {
          _selected.addAll(_pages.map((p) => p.key));
        }
      });

  void _deleteSelected() {
    setState(() {
      _pages.removeWhere((p) => _selected.contains(p.key));
      _selected.clear();
      _markChanged();
    });
  }

  Future<void> _rotateSelected() async {
    await Future.wait(_selectedPages.map(_rotate));
  }

  void _duplicateSelected() {
    setState(() {
      for (final page in _selectedPages.reversed) {
        final index = _pages.indexOf(page);
        _pages.insert(index + 1, _Page(_nextKey++, page.bytes));
      }
      _markChanged();
    });
  }

  /// Moves the selected pages as one block so it starts at [index] of the
  /// remaining (unselected) pages.
  void _moveSelectedTo(int index) {
    setState(() {
      final block = _selectedPages;
      final others = [for (final p in _pages) if (!_selected.contains(p.key)) p];
      others.insertAll(index.clamp(0, others.length), block);
      _pages
        ..clear()
        ..addAll(others);
      _markChanged();
    });
  }

  /// Moves the selected pages one step up (-1) or down (1).
  void _shiftSelected(int delta) {
    final firstSelected = _pages.indexWhere((p) => _selected.contains(p.key));
    final unselectedBefore =
        _pages.take(firstSelected).where((p) => !_selected.contains(p.key)).length;
    _moveSelectedTo(unselectedBefore + delta);
  }

  void _onReorder(int oldIndex, int newIndex) {
    final dragged = _pages[oldIndex];
    if (!_selected.contains(dragged.key) || _selected.length == 1) {
      setState(() {
        _pages.insert(newIndex, _pages.removeAt(oldIndex));
        _markChanged();
      });
      return;
    }
    // Dragging one of several selected pages moves all of them: they land
    // together in front of the first unselected page at the drop position.
    final rest = [..._pages]..removeAt(oldIndex);
    final anchor = rest.skip(newIndex).where((p) => !_selected.contains(p.key)).firstOrNull;
    final others = [for (final p in _pages) if (!_selected.contains(p.key)) p];
    _moveSelectedTo(anchor == null ? others.length : others.indexOf(anchor));
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

  PreferredSizeWidget _appBar() {
    if (!_selecting) {
      return AppBar(
        title: Text(tr('Seiten bearbeiten (${_pages.length})', 'Edit pages (${_pages.length})')),
        actions: [
          if (_pages.isNotEmpty)
            IconButton(
              tooltip: tr('Mehrere auswählen', 'Select several'),
              icon: const Icon(Icons.checklist),
              onPressed: _selectAll,
            ),
        ],
      );
    }
    final busy = _rotating.isNotEmpty;
    return AppBar(
      leading: IconButton(
        tooltip: tr('Auswahl aufheben', 'Clear selection'),
        icon: const Icon(Icons.close),
        onPressed: () => setState(_selected.clear),
      ),
      title: Text(tr('${_selected.length} ausgewählt', '${_selected.length} selected')),
      actions: [
        IconButton(
          tooltip: tr('Nach oben', 'Move up'),
          icon: const Icon(Icons.arrow_upward),
          onPressed: () => _shiftSelected(-1),
        ),
        IconButton(
          tooltip: tr('Nach unten', 'Move down'),
          icon: const Icon(Icons.arrow_downward),
          onPressed: () => _shiftSelected(1),
        ),
        IconButton(
          tooltip: tr('Drehen', 'Rotate'),
          icon: const Icon(Icons.rotate_right),
          onPressed: busy ? null : _rotateSelected,
        ),
        IconButton(
          tooltip: tr('Löschen', 'Delete'),
          icon: const Icon(Icons.delete_outline),
          onPressed: _deleteSelected,
        ),
        PopupMenuButton<String>(
          tooltip: tr('Weitere Aktionen', 'More actions'),
          onSelected: (action) => switch (action) {
            'all' => _selectAll(),
            'start' => _moveSelectedTo(0),
            'end' => _moveSelectedTo(_pages.length),
            'duplicate' => _duplicateSelected(),
            _ => null,
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'all',
              child: Text(_selected.length == _pages.length
                  ? tr('Keine auswählen', 'Select none')
                  : tr('Alle auswählen', 'Select all')),
            ),
            PopupMenuItem(value: 'start', child: Text(tr('An den Anfang', 'Move to start'))),
            PopupMenuItem(value: 'end', child: Text(tr('Ans Ende', 'Move to end'))),
            PopupMenuItem(value: 'duplicate', child: Text(tr('Duplizieren', 'Duplicate'))),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(),
      body: _pages.isEmpty
          ? Center(
              child: Text(
                tr('Keine Seiten mehr - füge mindestens eine hinzu.', 'No pages left - add at least one.'),
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _pages.length,
              onReorderItem: _onReorder,
              itemBuilder: (context, i) {
                final page = _pages[i];
                final selected = _selected.contains(page.key);
                final scheme = Theme.of(context).colorScheme;
                return Card(
                  key: ValueKey(page.key),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: selected ? scheme.secondaryContainer : null,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    // Tap selects while selecting; long-press starts it.
                    onTap: _selecting ? () => _toggle(page) : null,
                    onLongPress: () => _toggle(page),
                    child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: (_) => _toggle(page),
                        ),
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
                        Expanded(child: Text(tr('Seite ${i + 1}', 'Page ${i + 1}'))),
                        IconButton(
                          tooltip: tr('Drehen', 'Rotate'),
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
                          tooltip: tr('Löschen', 'Delete'),
                          onPressed: () => _delete(i),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        const SizedBox(width: 24), // room for the drag handle
                      ],
                    ),
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
                  label: Text(tr('Seite hinzufügen', 'Add page')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _changed && _pages.isNotEmpty && _rotating.isEmpty ? _save : null,
                  icon: const Icon(Icons.save),
                  label: Text(tr('Speichern', 'Save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
