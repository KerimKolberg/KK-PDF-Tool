import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';

import 'package:flutter/material.dart';

import '../services/document_store.dart';
import '../services/incoming_file_service.dart';
import 'import_shared_file_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'tools_screen.dart';

/// Top-level navigation shell: Library and Tools tabs, with Settings
/// reachable from either. Also watches for files the OS hands to the app
/// via "Open with" / the share sheet and offers to import them.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _dragging = false;
  final _store = DocumentStore();
  final _incomingFiles = IncomingFileService();
  StreamSubscription<IncomingFile>? _incomingSub;

  static const _tabs = [
    LibraryScreen(),
    ToolsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _incomingFiles.takeInitialFile().then(_offerImport);
    _incomingSub = _incomingFiles.onFileReceived.listen(_offerImport);
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }

  void _offerImport(IncomingFile? file) {
    if (file == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImportSharedFileScreen(file: file, store: _store),
      ),
    );
  }

  static const _droppableExtensions = {'.pdf', '.jpg', '.jpeg', '.png'};

  /// Windows: files dragged from Explorer onto the window go through the
  /// same import flow as "Open with" on Android, one after another.
  Future<void> _onDrop(DropDoneDetails details) async {
    for (final f in details.files) {
      final lower = f.path.toLowerCase();
      if (!_droppableExtensions.any(lower.endsWith)) continue;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImportSharedFileScreen(
            file: IncomingFile(path: f.path, name: f.name),
            store: _store,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = IndexedStack(index: _index, children: _tabs);
    return Scaffold(
      body: Platform.isWindows
          ? DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (d) {
                setState(() => _dragging = false);
                _onDrop(d);
              },
              child: Stack(
                children: [
                  tabs,
                  if (_dragging)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          child: const Center(
                            child: Text(
                              'PDF oder Bild hier ablegen',
                              style: TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          : tabs,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Bibliothek',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: 'Werkzeuge',
          ),
        ],
      ),
    );
  }
}

/// Small helper so screens embedded in the shell can still offer a way to
/// reach Settings without every tab needing its own AppBar action wired up
/// individually.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Einstellungen',
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );
  }
}
