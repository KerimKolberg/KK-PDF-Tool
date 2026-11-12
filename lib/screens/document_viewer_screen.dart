import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/scan_document.dart';
import '../services/document_builder.dart';
import '../services/document_store.dart';
import '../services/google_drive_convert_service.dart';
import '../services/ocr_service.dart';
import '../widgets/folder_picker.dart';
import '../widgets/share_sheet.dart';
import 'annotate_pages_screen.dart';
import 'edit_pages_screen.dart';
import 'text_result_screen.dart';
import '../l10n.dart';
import '../utils/layout.dart';

class DocumentViewerScreen extends StatefulWidget {
  final DocumentStore store;
  final ScanDocument document;

  const DocumentViewerScreen({
    super.key,
    required this.store,
    required this.document,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  late ScanDocument _doc;
  List<File> _pages = [];
  String? _pdfPath;
  bool _loading = true;
  String? _busyMessage;

  @override
  void initState() {
    super.initState();
    _doc = widget.document;
    _load();
  }

  Future<void> _load() async {
    final pages = await widget.store.pageFiles(_doc.id, _doc.pageCount);
    final pdf = await widget.store.pdfPath(_doc.id);
    if (!mounted) return;
    setState(() {
      _pages = pages;
      _pdfPath = pdf;
      _loading = false;
    });
  }

  Future<void> _openPdf() async {
    final path = _pdfPath;
    if (path == null) return;
    final uri = Uri.file(path);
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('PDF konnte nicht geöffnet werden.', 'Could not open PDF.'))),
      );
    }
  }

  Future<void> _share() => showShareSheet(context, widget.store, _doc);

  Future<void> _rename() async {
    final controller = TextEditingController(text: _doc.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Umbenennen', 'Rename')),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Abbrechen', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(tr('Speichern', 'Save')),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty) return;
    await widget.store.rename(_doc.id, newTitle);
    if (!mounted) return;
    setState(() => _doc = _doc.copyWith(title: newTitle));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Dokument löschen?', 'Delete document?')),
        content: Text(tr('"${_doc.title}" wird unwiderruflich gelöscht.', '"${_doc.title}" will be deleted permanently.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Abbrechen', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Löschen', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.delete(_doc.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// Runs [action] while showing [message] as a progress banner; shows an
  /// error snackbar and returns null if it throws.
  Future<T?> _withBusy<T>(String message, Future<T> Function() action) async {
    setState(() => _busyMessage = message);
    try {
      return await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Fehlgeschlagen: $e', 'Failed: $e'))),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _busyMessage = null);
    }
  }

  void _progress(String label, int done, int total) {
    if (mounted) setState(() => _busyMessage = '$label ${done + 1 > total ? total : done + 1}/$total…');
  }

  Future<void> _editPages() async {
    final pages = await _withBusy(
      tr('Seiten werden geladen…', 'Loading pages…'),
      () => DocumentBuilder.loadEditablePages(widget.store, _doc),
    );
    if (pages == null || !mounted) return;
    final edited = await Navigator.of(context).push<List<Uint8List>>(
      MaterialPageRoute(builder: (_) => EditPagesScreen(pages: pages)),
    );
    if (edited == null || !mounted) return;
    await _replacePages(edited);
  }

  Future<void> _annotate(AnnotateMode mode) async {
    final pages = await _withBusy(
      tr('Seiten werden geladen…', 'Loading pages…'),
      () => DocumentBuilder.loadEditablePages(widget.store, _doc),
    );
    if (pages == null || !mounted) return;
    final edited = await Navigator.of(context).push<List<Uint8List>>(
      MaterialPageRoute(builder: (_) => AnnotatePagesScreen(pages: pages, initialMode: mode)),
    );
    if (edited == null || !mounted) return;
    await _replacePages(edited);
  }

  Future<void> _replacePages(List<Uint8List> pages) async {
    final updated = await _withBusy(tr('Speichere…', 'Saving…'), () async {
      final built = await DocumentBuilder.build(
        pages,
        onProgress: (done, total) => _progress(tr('Texterkennung', 'Text recognition'), done, total),
      );
      final previousText = built.text == null ? await widget.store.readText(_doc.id) : null;
      return widget.store.replaceContent(
        _doc.id,
        pageJpegBytes: built.pages,
        pdfBytes: built.pdfBytes,
        text: built.text ?? previousText,
        ocr: built.ocr,
      );
    });
    if (updated == null || !mounted) return;
    // Page files keep their names, so drop cached decodes of the old pages.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    setState(() {
      _doc = updated;
      _loading = true;
    });
    await _load();
  }

  Future<void> _recognizeText() async {
    var text = await widget.store.readText(_doc.id);
    if (text == null) {
      text = await _withBusy(tr('Texterkennung…', 'Text recognition…'), () async {
        String? result;
        if (OcrService.isOfflineAvailable) {
          final pages = await DocumentBuilder.loadEditablePages(widget.store, _doc);
          result = await DocumentBuilder.recognizeText(
            pages,
            onProgress: (done, total) => _progress(tr('Texterkennung', 'Text recognition'), done, total),
          );
        } else {
          final pdf = await File(_pdfPath!).readAsBytes();
          result = await GoogleDriveConvertService().pdfToText(pdf, '${_doc.title}.pdf');
        }
        await widget.store.writeText(_doc.id, result);
        return result ?? '';
      });
      if (text == null) return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TextResultScreen(title: _doc.title, text: text!)),
    );
  }

  Future<void> _moveToFolder() async {
    final choice = await pickFolder(context, widget.store, current: _doc.folder);
    if (choice == null) return;
    await widget.store.moveToFolder(_doc.id, choice.folder);
    if (!mounted) return;
    setState(() => _doc = _doc.copyWith(folder: choice.folder));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(choice.folder == null
            ? tr('Aus dem Ordner entfernt', 'Removed from folder')
            : tr('Verschoben nach "${choice.folder}"', 'Moved to "${choice.folder}"')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busyMessage != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_doc.title),
        actions: [
          PopupMenuButton<VoidCallback>(
            enabled: !busy && !_loading,
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _editPages,
                child: ListTile(
                  leading: Icon(Icons.view_agenda_outlined),
                  title: Text(tr('Seiten bearbeiten', 'Edit pages')),
                ),
              ),
              PopupMenuItem(
                value: () => _annotate(AnnotateMode.fill),
                child: ListTile(
                  leading: Icon(Icons.edit_note),
                  title: Text(tr('Ausfüllen & unterschreiben', 'Fill in & sign')),
                ),
              ),
              PopupMenuItem(
                value: () => _annotate(AnnotateMode.draw),
                child: ListTile(
                  leading: Icon(Icons.brush_outlined),
                  title: Text(tr('Zeichnen & markieren', 'Draw & highlight')),
                ),
              ),
              PopupMenuItem(
                value: _recognizeText,
                child: ListTile(
                  leading: Icon(Icons.text_snippet_outlined),
                  title: Text(tr('Text erkennen', 'Recognize text')),
                ),
              ),
              PopupMenuItem(
                value: _moveToFolder,
                child: ListTile(
                  leading: Icon(Icons.drive_file_move_outlined),
                  title: Text(tr('In Ordner verschieben', 'Move to folder')),
                ),
              ),
              PopupMenuItem(
                value: _rename,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text(tr('Umbenennen', 'Rename')),
                ),
              ),
              PopupMenuItem(
                value: _delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text(tr('Löschen', 'Delete')),
                ),
              ),
            ],
          ),
        ],
        bottom: busy
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Column(
                  children: [
                    Text(_busyMessage!, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    const LinearProgressIndicator(),
                  ],
                ),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final side = centeredPadding(constraints.maxWidth, maxWidth: 1100).left;
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(side, 4, side, 12),
                      sliver: SliverToBoxAdapter(child: _buildHeader(busy)),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(side, 0, side, 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _PageThumbnail(
                            file: _pages[i],
                            number: i + 1,
                            onTap: () => _openFullPage(i),
                          ),
                          childCount: _pages.length,
                        ),
                      ),
                    ),
                  ],
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
                  onPressed: _loading || busy ? null : _share,
                  icon: const Icon(Icons.ios_share),
                  label: Text(tr('Teilen', 'Share')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading || busy ? null : _openPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(tr('PDF öffnen', 'Open PDF')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Page count and folder, plus the most used actions as buttons so they
  /// don't hide in the menu.
  Widget _buildHeader(bool busy) {
    final theme = Theme.of(context);
    final info = [
      tr('${_pages.length} ${_pages.length == 1 ? 'Seite' : 'Seiten'}',
          '${_pages.length} ${_pages.length == 1 ? 'page' : 'pages'}'),
      ?_doc.folder,
    ].join(' · ');
    Widget action(IconData icon, String label, VoidCallback onPressed) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            onPressed: busy ? null : onPressed,
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(info, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              action(Icons.view_agenda_outlined, tr('Seiten bearbeiten', 'Edit pages'), _editPages),
              action(Icons.edit_note, tr('Ausfüllen & unterschreiben', 'Fill in & sign'), () => _annotate(AnnotateMode.fill)),
              action(Icons.brush_outlined, tr('Zeichnen', 'Draw'), () => _annotate(AnnotateMode.draw)),
              action(Icons.text_snippet_outlined, tr('Text erkennen', 'Recognize text'), _recognizeText),
              action(Icons.drive_file_move_outlined, tr('Verschieben', 'Move'), _moveToFolder),
            ],
          ),
        ),
      ],
    );
  }

  void _openFullPage(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullPageViewer(pages: _pages, initialIndex: index),
      ),
    );
  }
}

class _PageThumbnail extends StatelessWidget {
  final File file;
  final int number;
  final VoidCallback onTap;

  const _PageThumbnail({required this.file, required this.number, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(file, fit: BoxFit.cover, alignment: Alignment.topCenter, cacheWidth: 480),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.inverseSurface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$number',
                  style: TextStyle(color: scheme.onInverseSurface, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullPageViewer extends StatefulWidget {
  final List<File> pages;
  final int initialIndex;

  const _FullPageViewer({required this.pages, required this.initialIndex});

  @override
  State<_FullPageViewer> createState() => _FullPageViewerState();
}

class _FullPageViewerState extends State<_FullPageViewer> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.pages.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          tr('Seite ${_index + 1} von $total', 'Page ${_index + 1} of $total'),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: total,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(child: Image.file(widget.pages[i])),
        ),
      ),
    );
  }
}
