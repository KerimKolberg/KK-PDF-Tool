import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models/scan_document.dart';
import '../services/document_store.dart';
import '../services/settings_service.dart';
import '../utils/formatting.dart';
import '../utils/layout.dart';
import '../widgets/folder_picker.dart';
import '../widgets/share_sheet.dart';
import 'document_viewer_screen.dart';
import 'home_shell.dart';
import 'id_scan_screen.dart';
import 'scan_flow_screen.dart';

enum LibrarySort {
  newest('Neueste zuerst', 'Newest first'),
  oldest('Älteste zuerst', 'Oldest first'),
  name('Name (A-Z)', 'Name (A-Z)'),
  size('Größte zuerst', 'Largest first');

  final String _de;
  final String _en;
  const LibrarySort(this._de, this._en);

  String get label => tr(_de, _en);
}

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
  Map<String, int> _sizes = {};

  /// First page image of every document, resolved once per reload instead
  /// of on every rebuild of a list row.
  Map<String, File> _thumbnails = {};
  bool _loading = true;
  bool _searching = false;
  String _query = '';

  /// Currently opened folder (remembered between app starts); null = all.
  String? _folder = AppPrefs.getString('library.folder');
  LibrarySort _sort = AppPrefs.getEnum('library.sort', LibrarySort.values, LibrarySort.newest);
  bool _grid = AppPrefs.getBool('library.grid', false);

  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    DocumentStore.changes.addListener(_onLibraryChanged);
    _reload();
  }

  @override
  void dispose() {
    DocumentStore.changes.removeListener(_onLibraryChanged);
    _reloadDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// The library changed elsewhere (restore, import via "Open with", batch
  /// scan…): refresh once things settle.
  void _onLibraryChanged() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() async {
    final docs = await _store.loadAll();
    final folders = await _store.loadFolders(docs: docs);
    final texts = <String, String>{};
    final sizes = <String, int>{};
    final thumbnails = <String, File>{};
    await Future.wait([
      for (final d in docs)
        () async {
          final text = await _store.readText(d.id);
          if (text != null) texts[d.id] = text;
          final pdf = File(await _store.pdfPath(d.id));
          sizes[d.id] = await pdf.exists() ? await pdf.length() : 0;
          if (d.pageCount > 0) thumbnails[d.id] = (await _store.pageFiles(d.id, 1)).first;
        }(),
    ]);
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _folders = folders;
      _texts = texts;
      _sizes = sizes;
      _thumbnails = thumbnails;
      if (_folder != null && !folders.contains(_folder)) _openFolder(null);
      _loading = false;
    });
  }

  void _openFolder(String? folder) {
    _folder = folder;
    AppPrefs.setString('library.folder', folder);
  }

  Future<void> _newScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanFlowScreen(store: _store, folder: _folder)),
    );
    await _reload();
  }

  Future<void> _newIdScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IdScanScreen(store: _store, folder: _folder)),
    );
    await _reload();
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
              title: Text(tr('Neuer Scan', 'New scan')),
              subtitle: Text(tr('Ein oder mehrere Seiten, auch als Stapel', 'One or more pages, also as a batch')),
              onTap: () => Navigator.pop(context, _newScan),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(tr('Ausweis scannen', 'Scan ID card')),
              subtitle: Text(tr('Vorder- und Rückseite auf einer Seite', 'Front and back on one page')),
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
    await _reload();
  }

  Future<void> _documentActions(ScanDocument doc) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(doc.title, style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(tr('Teilen…', 'Share…')),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: Text(tr('In Ordner verschieben', 'Move to folder')),
              onTap: () => Navigator.pop(context, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr('Umbenennen', 'Rename')),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('Löschen', 'Delete')),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'share':
        await showShareSheet(context, _store, doc);
      case 'move':
        final choice = await pickFolder(context, _store, current: doc.folder);
        if (choice == null) return;
        await _store.moveToFolder(doc.id, choice.folder);
        await _reload();
      case 'rename':
        final controller = TextEditingController(text: doc.title);
        final name = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('Umbenennen', 'Rename')),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(tr('Speichern', 'Save')),
              ),
            ],
          ),
        );
        if (name == null || name.isEmpty) return;
        await _store.rename(doc.id, name);
        await _reload();
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('Dokument löschen?', 'Delete document?')),
            content: Text(tr('"${doc.title}" wird unwiderruflich gelöscht.', '"${doc.title}" will be deleted permanently.')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Löschen', 'Delete'))),
            ],
          ),
        );
        if (confirmed != true) return;
        await _store.delete(doc.id);
        await _reload();
    }
  }

  Future<void> _createFolder() async {
    final name = await promptFolderName(context);
    if (name == null) return;
    await _store.addFolder(name);
    _openFolder(name);
    await _reload();
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
              title: Text(tr('"$folder" umbenennen', 'Rename "$folder"')),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_delete_outlined),
              title: Text(tr('"$folder" löschen', 'Delete "$folder"')),
              subtitle: Text(tr('Die Dokumente bleiben erhalten', 'The documents are kept')),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final name = await promptFolderName(context, title: tr('Ordner umbenennen', 'Rename folder'), initial: folder);
      if (name == null || name == folder) return;
      await _store.renameFolder(folder, name);
      if (_folder == folder) _openFolder(name);
    } else if (action == 'delete') {
      await _store.deleteFolder(folder);
      if (_folder == folder) _openFolder(null);
    } else {
      return;
    }
    await _reload();
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

  /// Visible documents (folder + search filter, sorted) with an optional
  /// text snippet when the query only matched the recognised text.
  List<(ScanDocument, String?)> get _visible {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final d in _docs)
        if (_folder == null || d.folder == _folder)
          if (q.isEmpty || d.title.toLowerCase().contains(q))
            (d, null)
          else if ((_texts[d.id] ?? '').toLowerCase().contains(q))
            (d, _snippet(_texts[d.id]!, q)),
    ];
    int byDate((ScanDocument, String?) a, (ScanDocument, String?) b) =>
        b.$1.createdAt.compareTo(a.$1.createdAt);
    switch (_sort) {
      case LibrarySort.newest:
        list.sort(byDate);
      case LibrarySort.oldest:
        list.sort((a, b) => byDate(b, a));
      case LibrarySort.name:
        list.sort((a, b) => a.$1.title.toLowerCase().compareTo(b.$1.title.toLowerCase()));
      case LibrarySort.size:
        list.sort((a, b) => (_sizes[b.$1.id] ?? 0).compareTo(_sizes[a.$1.id] ?? 0));
    }
    return list;
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
    return tr('${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}', '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}');
  }

  String _meta(ScanDocument doc, {bool withFolder = true}) => [
        _formatDate(doc.createdAt),
        tr('${doc.pageCount} ${doc.pageCount == 1 ? 'Seite' : 'Seiten'}', '${doc.pageCount} ${doc.pageCount == 1 ? 'page' : 'pages'}'),
        if ((_sizes[doc.id] ?? 0) > 0) formatFileSize(_sizes[doc.id]!),
        if (withFolder && _folder == null && doc.folder != null) doc.folder!,
      ].join(' · ');

  PreferredSizeWidget _buildAppBar() {
    if (_searching) {
      return AppBar(
        leading: IconButton(
          tooltip: tr('Suche schließen', 'Close search'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _setSearching(false),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: tr('Titel oder Text suchen…', 'Search titles or text…'),
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: tr('Leeren', 'Clear'),
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
      title: Text(_folder ?? tr('Meine Scans', 'My scans')),
      actions: [
        IconButton(
          tooltip: tr('Suchen', 'Search'),
          icon: const Icon(Icons.search),
          onPressed: () => _setSearching(true),
        ),
        PopupMenuButton<LibrarySort>(
          tooltip: tr('Sortieren', 'Sort'),
          icon: const Icon(Icons.sort),
          initialValue: _sort,
          onSelected: (sort) {
            setState(() => _sort = sort);
            AppPrefs.setEnum('library.sort', sort);
          },
          itemBuilder: (context) => [
            for (final sort in LibrarySort.values)
              CheckedPopupMenuItem(value: sort, checked: sort == _sort, child: Text(sort.label)),
          ],
        ),
        IconButton(
          tooltip: _grid ? tr('Listenansicht', 'List view') : tr('Rasteransicht', 'Grid view'),
          icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
          onPressed: () {
            setState(() => _grid = !_grid);
            AppPrefs.setBool('library.grid', _grid);
          },
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
              label: Text(tr('Alle', 'All')),
              selected: _folder == null,
              onSelected: (_) => setState(() => _openFolder(null)),
            ),
          ),
          for (final f in _folders)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onLongPress: () => _folderOptions(f),
                onSecondaryTap: () => _folderOptions(f),
                child: ChoiceChip(
                  avatar: const Icon(Icons.folder_outlined, size: 18),
                  label: Text(f),
                  selected: _folder == f,
                  onSelected: (_) => setState(() => _openFolder(f)),
                ),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: Text(tr('Ordner', 'Folder')),
            onPressed: _createFolder,
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(ScanDocument doc, {required double size, int cacheWidth = 144}) {
    final placeholder = SizedBox(
      width: size,
      height: size,
      child: const Icon(Icons.description_outlined),
    );
    final file = _thumbnails[doc.id];
    if (file == null) return placeholder;
    return Image.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      cacheWidth: cacheWidth,
      errorBuilder: (_, _, _) => placeholder,
    );
  }

  Widget _buildEmpty() {
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
                  ? tr('Keine Treffer für "$_query".', 'No results for "$_query".')
                  : noDocsAtAll
                      ? (AppPlatform.isWindows
                          ? tr('Noch keine Scans vorhanden.\nStarte mit "Neuer Scan" oder ziehe PDFs und Bilder hierher.',
                              'No scans yet.\nStart with "New scan" or drag PDFs and images here.')
                          : tr('Noch keine Scans vorhanden.\nTippe unten auf "Neuer Scan".', 'No scans yet.\nTap "New scan" below.'))
                      : tr('Dieser Ordner ist leer.\nNeue Scans landen automatisch hier.', 'This folder is empty.\nNew scans land here automatically.'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<(ScanDocument, String?)> visible) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = isWideLayout(context);
    return ListView.builder(
      padding: wide
          ? centeredPadding(width, maxWidth: 1000, vertical: 0).copyWith(bottom: 88)
          : const EdgeInsets.only(bottom: 88),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final (doc, snippet) = visible[i];
        final meta = _meta(doc);
        final scheme = Theme.of(context).colorScheme;
        return GestureDetector(
          onSecondaryTap: () => _documentActions(doc),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            leading: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: _thumbnail(doc, size: 52),
              ),
            ),
            title: Text(
              doc.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              snippet == null ? meta : '$meta\n$snippet',
              maxLines: snippet == null ? 1 : 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: snippet != null,
            trailing: IconButton(
              tooltip: tr('Weitere Aktionen', 'More actions'),
              icon: const Icon(Icons.more_vert),
              onPressed: () => _documentActions(doc),
            ),
            onTap: () => _openDocument(doc),
            onLongPress: () => _documentActions(doc),
          ),
        );
      },
    );
  }

  Widget _buildGrid(List<(ScanDocument, String?)> visible) {
    final textTheme = Theme.of(context).textTheme;
    final outline = Theme.of(context).colorScheme.outline;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.68,
      ),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final (doc, snippet) = visible[i];
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => _openDocument(doc),
            onLongPress: () => _documentActions(doc),
            onSecondaryTap: () => _documentActions(doc),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => _thumbnail(
                      doc,
                      size: constraints.maxWidth,
                      cacheWidth: 480,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snippet ?? _meta(doc, withFolder: false),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(color: outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _loading ? const <(ScanDocument, String?)>[] : _visible;
    return Scaffold(
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFolderBar(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _reload,
                    child: visible.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) => SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: SizedBox(height: constraints.maxHeight, child: _buildEmpty()),
                            ),
                          )
                        : _grid
                            ? _buildGrid(visible)
                            : _buildList(visible),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showScanOptions,
        icon: const Icon(Icons.add_a_photo),
        label: Text(tr('Neuer Scan', 'New scan')),
      ),
    );
  }
}
