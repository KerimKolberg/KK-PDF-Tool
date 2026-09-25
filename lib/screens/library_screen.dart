import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scan_document.dart';
import '../services/document_store.dart';
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
  List<ScanDocument> _docs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final docs = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _loading = false;
    });
  }

  Future<void> _newScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanFlowScreen(store: _store)),
    );
    _reload();
  }

  Future<void> _newIdScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IdScanScreen(store: _store)),
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

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Scans'),
        actions: const [SettingsButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _docs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.document_scanner_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text(
                          'Noch keine Scans vorhanden.\nTippe unten auf "Neuer Scan".',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    itemCount: _docs.length,
                    itemBuilder: (context, i) {
                      final doc = _docs[i];
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
                              ),
                            );
                          },
                        ),
                        title: Text(doc.title),
                        subtitle: Text(
                          '${_formatDate(doc.createdAt)} · ${doc.pageCount} Seite(n)',
                        ),
                        onTap: () => _openDocument(doc),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showScanOptions,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('Neuer Scan'),
      ),
    );
  }
}
