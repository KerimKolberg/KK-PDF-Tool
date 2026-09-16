import 'package:flutter/material.dart';

import 'tools/images_to_pdf_screen.dart';
import 'tools/merge_pdf_screen.dart';
import 'tools/pdf_to_images_screen.dart';
import 'tools/split_pdf_screen.dart';

class _ToolEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
  const _ToolEntry(this.title, this.subtitle, this.icon, this.builder);
}

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  static final _tools = <_ToolEntry>[
    _ToolEntry(
      'Bilder → PDF',
      'Mehrere Bilder zu einer PDF zusammenfassen',
      Icons.image_outlined,
      (_) => const ImagesToPdfScreen(),
    ),
    _ToolEntry(
      'PDF → Bilder',
      'Jede Seite einer PDF als Bild exportieren',
      Icons.photo_library_outlined,
      (_) => const PdfToImagesScreen(),
    ),
    _ToolEntry(
      'PDFs zusammenführen',
      'Mehrere PDFs in einer Reihenfolge verbinden',
      Icons.merge_type,
      (_) => const MergePdfScreen(),
    ),
    _ToolEntry(
      'PDF aufteilen',
      'Nach Seitenbereich in mehrere PDFs aufteilen',
      Icons.content_cut,
      (_) => const SplitPdfScreen(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Werkzeuge')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _tools.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final tool = _tools[i];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onPrimaryContainer,
                child: Icon(tool.icon),
              ),
              title: Text(tool.title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(tool.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: tool.builder),
              ),
            ),
          );
        },
      ),
    );
  }
}
