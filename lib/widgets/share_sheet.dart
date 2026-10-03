import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scan_document.dart';
import '../services/document_share_service.dart';
import '../services/document_store.dart';
import '../utils/formatting.dart';

/// Asks how to share [doc] (original PDF, smaller PDF or JPG images),
/// prepares the files with a progress indicator and opens the system share
/// sheet.
Future<void> showShareSheet(
  BuildContext context,
  DocumentStore store,
  ScanDocument doc,
) async {
  final pdfFile = File(await store.pdfPath(doc.id));
  final size = await pdfFile.exists() ? await pdfFile.length() : 0;
  if (!context.mounted) return;

  final format = await showModalBottomSheet<ShareFormat>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('"${doc.title}" teilen als …', style: Theme.of(sheetContext).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF (Original)'),
            subtitle: Text(formatFileSize(size)),
            onTap: () => Navigator.pop(sheetContext, ShareFormat.originalPdf),
          ),
          ListTile(
            leading: const Icon(Icons.compress),
            title: const Text('PDF verkleinert'),
            subtitle: const Text('Ideal für E-Mail und WhatsApp'),
            onTap: () => Navigator.pop(sheetContext, ShareFormat.smallPdf),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Bilder (JPG)'),
            subtitle: Text(doc.pageCount == 1 ? '1 Bild' : '${doc.pageCount} Bilder, eins pro Seite'),
            onTap: () => Navigator.pop(sheetContext, ShareFormat.images),
          ),
        ],
      ),
    ),
  );
  if (format == null || !context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: 16),
            Text('Wird vorbereitet…'),
          ],
        ),
      ),
    ),
  );
  PreparedShare? prepared;
  Object? error;
  try {
    prepared = await DocumentShareService(store).prepare(doc, format);
  } catch (e) {
    error = e;
  } finally {
    navigator.pop();
  }
  if (!context.mounted) return;
  if (prepared == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Teilen fehlgeschlagen: $error')),
    );
    return;
  }
  if (prepared.note != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(prepared.note!)));
  }
  await SharePlus.instance.share(ShareParams(files: prepared.files, subject: doc.title));
}
