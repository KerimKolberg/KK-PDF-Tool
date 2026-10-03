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
        const SnackBar(content: Text('PDF konnte nicht geöffnet werden.')),
      );
    }
  }

  Future<void> _share() => showShareSheet(context, widget.store, _doc);

  Future<void> _rename() async {
    final controller = TextEditingController(text: _doc.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Umbenennen'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Speichern'),
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
        title: const Text('Dokument löschen?'),
        content: Text('"${_doc.title}" wird unwiderruflich gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
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
          SnackBar(content: Text('Fehlgeschlagen: $e')),
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
      'Seiten werden geladen…',
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
      'Seiten werden geladen…',
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
    final updated = await _withBusy('Speichere…', () async {
      final built = await DocumentBuilder.build(
        pages,
        onProgress: (done, total) => _progress('Texterkennung', done, total),
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
      text = await _withBusy('Texterkennung…', () async {
        String? result;
        if (OcrService.isOfflineAvailable) {
          final pages = await DocumentBuilder.loadEditablePages(widget.store, _doc);
          result = await DocumentBuilder.recognizeText(
            pages,
            onProgress: (done, total) => _progress('Texterkennung', done, total),
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
            ? 'Aus dem Ordner entfernt'
            : 'Verschoben nach "${choice.folder}"'),
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
                child: const ListTile(
                  leading: Icon(Icons.view_agenda_outlined),
                  title: Text('Seiten bearbeiten'),
                ),
              ),
              PopupMenuItem(
                value: () => _annotate(AnnotateMode.fill),
                child: const ListTile(
                  leading: Icon(Icons.edit_note),
                  title: Text('Ausfüllen & unterschreiben'),
                ),
              ),
              PopupMenuItem(
                value: () => _annotate(AnnotateMode.draw),
                child: const ListTile(
                  leading: Icon(Icons.brush_outlined),
                  title: Text('Zeichnen & markieren'),
                ),
              ),
              PopupMenuItem(
                value: _recognizeText,
                child: const ListTile(
                  leading: Icon(Icons.text_snippet_outlined),
                  title: Text('Text erkennen'),
                ),
              ),
              PopupMenuItem(
                value: _moveToFolder,
                child: const ListTile(
                  leading: Icon(Icons.drive_file_move_outlined),
                  title: Text('In Ordner verschieben'),
                ),
              ),
              PopupMenuItem(
                value: _rename,
                child: const ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Umbenennen'),
                ),
              ),
              PopupMenuItem(
                value: _delete,
                child: const ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Löschen'),
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
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.72,
              ),
              itemCount: _pages.length,
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => _openFullPage(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_pages[i], fit: BoxFit.cover),
                ),
              ),
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
                  label: const Text('Teilen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading || busy ? null : _openPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF öffnen'),
                ),
              ),
            ],
          ),
        ),
      ),
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

class _FullPageViewer extends StatelessWidget {
  final List<File> pages;
  final int initialIndex;

  const _FullPageViewer({required this.pages, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: pages.length,
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(child: Image.file(pages[i])),
        ),
      ),
    );
  }
}
