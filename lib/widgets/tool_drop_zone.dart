import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/file_picker_service.dart';
import '../l10n.dart';

/// Windows: lets files be dragged from Explorer onto a tool. The dropped
/// files are handed to [FilePickers], then the tool's own pick method runs
/// ([onDrop]) and receives them instead of opening the file dialog — so
/// every tool keeps a single code path for "file chosen".
class ToolDropZone extends StatefulWidget {
  final Future<void> Function() onDrop;
  final Widget child;

  const ToolDropZone({super.key, required this.onDrop, required this.child});

  @override
  State<ToolDropZone> createState() => _ToolDropZoneState();
}

class _ToolDropZoneState extends State<ToolDropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return widget.child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        FilePickers.setDropped([for (final f in details.files) XFile(f.path)]);
        final messenger = ScaffoldMessenger.of(context);
        await widget.onDrop();
        if (FilePickers.clearDropped()) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                tr('Dateityp wird von diesem Werkzeug nicht unterstützt', 'This tool does not support this file type'),
              ),
            ),
          );
        }
      },
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.12),
                  child: Center(
                    child: Text(
                      tr('Datei hier ablegen', 'Drop file here'),
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
