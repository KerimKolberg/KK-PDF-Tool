import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/scan_document.dart';
import '../services/document_store.dart';

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

  Future<void> _sharePdf() async {
    final path = _pdfPath;
    if (path == null) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: _doc.title),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_doc.title),
        actions: [
          IconButton(
            onPressed: _rename,
            icon: const Icon(Icons.edit),
            tooltip: 'Umbenennen',
          ),
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Löschen',
          ),
        ],
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
                  onPressed: _loading ? null : _sharePdf,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Teilen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _openPdf,
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
