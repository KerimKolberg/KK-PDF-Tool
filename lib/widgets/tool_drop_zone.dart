import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/file_picker_service.dart';
import '../utils/layout.dart';
import 'drop_visuals.dart';

/// Windows: lets files be dragged from Explorer onto a tool (see also
/// [ToolDropZone.openWithFiles]). The dropped
/// files are handed to [FilePickers], then the tool's own pick method runs
/// ([onDrop]) and receives them instead of opening the file dialog — so
/// every tool keeps a single code path for "file chosen".
class ToolDropZone extends StatefulWidget {
  final Future<void> Function() onDrop;
  final Widget child;

  const ToolDropZone({super.key, required this.onDrop, required this.child});

  static List<XFile>? _pending;

  /// Makes the next tool that opens start with [paths] already chosen
  /// (used when a file was dropped on the main window or opened with the
  /// app, and the user then picked a tool for it).
  static void openWithFiles(List<String> paths) => _pending = [for (final p in paths) XFile(p)];

  @override
  State<ToolDropZone> createState() => _ToolDropZoneState();
}

class _ToolDropZoneState extends State<ToolDropZone> {
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    final files = ToolDropZone._pending;
    ToolDropZone._pending = null;
    if (files != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _deliver(files);
      });
    }
  }

  /// Hands [files] to the tool as if they had been picked.
  Future<void> _deliver(List<XFile> files) async {
    FilePickers.setDropped(files);
    final messenger = ScaffoldMessenger.of(context);
    await widget.onDrop();
    if (FilePickers.clearDropped()) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Dateityp wird von diesem Werkzeug nicht unterstützt',
              'This tool does not support this file type',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isWindows) return widget.child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        _deliver([for (final f in details.files) XFile(f.path)]);
      },
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: DropOverlay(message: tr('Datei hier ablegen', 'Drop file here')),
            ),
        ],
      ),
    );
  }
}
