import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/scan_document.dart';
import '../services/document_store.dart';
import '../widgets/folder_picker.dart';
import 'document_viewer_screen.dart';
import 'home_shell.dart';
import 'id_scan_screen.dart';
import 'scan_flow_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _store = DocumentStore();
  final _searchController = TextEditingController();
  List<ScanDocument> _docs = [];
  List<String> _folders = [];
  Map<String, String> _texts = {};
  bool _loading = true;
  bool _searching = false;
  String _query = '';

  /// Currently opened folder; null shows all documents.
  String? _folder;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final docs = await _store.loadAll();
    final folders = await _store.loadFolders();
    final texts = <String, String>{};
    for (final d in docs) {
      final text = await _store.readText(d.id);
      if (text != null) texts[d.id] = text;
    }
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _folders = folders;
      _texts = texts;
      if (_folder != null && !folders.contains(_folder)) _folder = null;
      _loading = false;
    });
  }

  Future<void> _newScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanFlowScreen(store: _store, folder: _folder)),
    );
    _reload();
  }

  Future<void> _newIdScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IdScanScreen(store: _store, folder: _folder)),
    );
    _reload();
  }

  Future<void> _showScanOptions() async {
    final choice = await showModalBottomSheet<VoidCallback>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_a_photo_outlined),
              title: const Text('Neuer Scan'),
              subtitle: const Text('Ein oder mehrere Seiten'),
              onTap: () => Navigator.pop(context, _newScan),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Ausweis scannen'),
              subtitle: const Text('Vorder- und Rückseite auf einer Seite'),
              onTap: () => Navigator.pop(context, _newIdScan),
            ),
          ],
        ),
      ),
    );
    choice?.call();
  }

  Future<void> _openDocument(ScanDocument doc) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentViewerScreen(store: _store, document: doc),
      ),
    );
    _reload();
  }

  Future<void> _moveDocument(ScanDocument doc) async {
    final choice = await pickFolder(context, _store, current: doc.folder);
    if (choice == null) return;
    await _store.moveToFolder(doc.id, choice.folder);
    _reload();
  }

  Future<void> _createFolder() async {
    final name = await promptFolderName(context);
    if (name == null) return;
    await _store.addFolder(name);
    _folder = name;
    _reload();
  }

  Future<void> _folderOptions(String folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('"$folder" umbenennen'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_delete_outlined),
              title: Text('"$folder" löschen'),
              subtitle: const Text('Die Dokumente bleiben erhalten'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final name = await promptFolderName(context, title: 'Ordner umbenennen', initial: folder);
      if (name == null || name == folder) return;
      await _store.renameFolder(folder, name);
      if (_folder == folder) _folder = name;
    } else if (action == 'delete') {
      await _store.deleteFolder(folder);
      if (_folder == folder) _folder = null;
    } else {
      return;
    }
    _reload();
  }

  void _setSearching(bool searching) {
    setState(() {
      _searching = searching;
      if (!searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  /// Visible documents with an optional text snippet when the query only
  /// matched the recognised text (not the title).
  List<(ScanDocument, String?)> get _visible {
    final q = _query.trim().toLowerCase();
    return [
      for (final d in _docs)
        if (_folder == null || d.folder == _folder)
          if (q.isEmpty || d.title.toLowerCase().contains(q))
            (d, null)
          else if ((_texts[d.id] ?? '').toLowerCase().contains(q))
            (d, _snippet(_texts[d.id]!, q)),
    ];
  }

  String _snippet(String text, String query) {
    final i = text.toLowerCase().indexOf(query);
    final start = math.max(0, i - 25);
    final end = math.min(text.length, i + query.length + 35);
    final body = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
    return '${start > 0 ? '…' : ''}$body${end < text.length ? '…' : ''}';
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  PreferredSizeWidget _buildAppBar() {
    if (_searching) {
      return AppBar(
        leading: IconButton(
          tooltip: 'Suche schließen',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _setSearching(false),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Titel oder Text suchen…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Leeren',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _query = '';
                _searchController.clear();
              }),
            ),
        ],
      );
    }
    return AppBar(
      title: Text(_folder ?? 'Meine Scans'),
      actions: [
        IconButton(
          tooltip: 'Suchen',
          icon: const Icon(Icons.search),
          onPressed: () => _setSearching(true),
        ),
        const SettingsButton(),
      ],
    );
  }

  Widget _buildFolderBar() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Alle'),
              selected: _folder == null,
              onSelected: (_) => setState(() => _folder = null),
            ),
          ),
          for (final f in _folders)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onLongPress: () => _folderOptions(f),
                child: ChoiceChip(
                  avatar: const Icon(Icons.folder_outlined, size: 18),
                  label: Text(f),
                  selected: _folder == f,
                  onSelected: (_) => setState(() => _folder = f),
                ),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('Ordner'),
            onPressed: _createFolder,
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final visible = _visible;
    if (visible.isEmpty) {
      final noDocsAtAll = _docs.isEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _query.isNotEmpty ? Icons.search_off : Icons.document_scanner_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                _query.isNotEmpty
                    ? 'Keine Treffer für "$_query".'
                    : noDocsAtAll
                        ? 'Noch keine Scans vorhanden.\nTippe unten auf "Neuer Scan".'
                        : 'Dieser Ordner ist leer.\nNeue Scans landen automatisch hier.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final (doc, snippet) = visible[i];
          final meta = [
            _formatDate(doc.createdAt),
            '${doc.pageCount} Seite(n)',
            if (_folder == null && doc.folder != null) doc.folder!,
          ].join(' · ');
          return ListTile(
            leading: FutureBuilder<List<File>>(
              future: _store.pageFiles(doc.id, 1),
              builder: (context, snapshot) {
                final files = snapshot.data;
                if (files == null || files.isEmpty) {
                  return const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.description_outlined),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    files.first,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    cacheWidth: 144,
                  ),
                );
              },
            ),
            title: Text(doc.title),
            subtitle: Text(
              snippet == null ? meta : '$meta\n$snippet',
              maxLines: snippet == null ? 1 : 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: snippet != null,
            onTap: () => _openDocument(doc),
            onLongPress: () => _moveDocument(doc),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFolderBar(),
                Expanded(child: _buildList()),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showScanOptions,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Neuer Scan'),
      ),
    );
  }
}
