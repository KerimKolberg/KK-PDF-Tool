import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../services/document_store.dart';
import '../services/incoming_file_service.dart';
import '../utils/layout.dart';
import '../widgets/drop_visuals.dart';
import '../widgets/file_actions.dart';
import '../widgets/tool_drop_zone.dart';
import 'import_shared_file_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'tools_screen.dart';
import '../l10n.dart';

/// Top-level navigation shell: Library and Tools (plus Settings in the
/// desktop layout's side navigation). Files dropped on the window or
/// opened with the app get a choice: add to the library or open a tool. Also watches for files the OS hands to the app
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
    _handleFiles([file]);
  }

  /// Windows: files dragged from Explorer onto the window.
  Future<void> _onDrop(DropDoneDetails details) async {
    final files = [
      for (final f in details.files)
        if (isSupportedFile(f.name)) IncomingFile(path: f.path, name: f.name),
    ];
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Dieser Dateityp wird nicht unterstützt', 'This file type is not supported')),
      ));
      return;
    }
    await _handleFiles(files);
  }

  /// Asks what to do with dropped or shared files - add them to the library
  /// or open a tool that takes them - and does it.
  Future<void> _handleFiles(List<IncomingFile> files) async {
    final action = await chooseFileAction(context, [for (final f in files) f.name]);
    if (action == null || !mounted) return;
    final tool = action.tool;
    if (tool != null) {
      ToolDropZone.openWithFiles([for (final f in files) f.path]);
      await Navigator.of(context).push(MaterialPageRoute(builder: tool.builder));
      return;
    }
    for (final file in files) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ImportSharedFileScreen(file: file, store: _store)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= wideLayoutBreakpoint;
    // In the desktop layout Settings is a section of the side navigation;
    // on phones it is opened from the gear button in each tab's app bar.
    final index = wide ? _index : _index.clamp(0, 1);
    Widget content = IndexedStack(
      index: index,
      children: [
        const LibraryScreen(),
        const ToolsScreen(),
        if (wide) const SettingsScreen(),
      ],
    );
    if (wide) {
      content = Row(
        children: [
          _SideNavigation(
            selectedIndex: index,
            extended: width >= 1100,
            onSelected: (i) => setState(() => _index = i),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: content),
        ],
      );
    }
    if (AppPlatform.isWindows) {
      content = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (d) {
          setState(() => _dragging = false);
          _onDrop(d);
        },
        child: Stack(
          children: [
            content,
            if (_dragging)
              Positioned.fill(
                child: DropOverlay(
                  message: tr('Dateien hier ablegen', 'Drop files here'),
                ),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: content,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.folder_outlined),
                  selectedIcon: const Icon(Icons.folder),
                  label: tr('Bibliothek', 'Library'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.handyman_outlined),
                  selectedIcon: const Icon(Icons.handyman),
                  label: tr('Werkzeuge', 'Tools'),
                ),
              ],
            ),
    );
  }
}

/// Desktop layout: app name and sections in a sidebar on the left.
class _SideNavigation extends StatelessWidget {
  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelected;

  const _SideNavigation({
    required this.selectedIndex,
    required this.extended,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 232,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      leading: Padding(
        padding: EdgeInsets.fromLTRB(extended ? 16 : 0, 12, extended ? 16 : 0, 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/icon/app_icon.png', width: 36, height: 36, cacheWidth: 96),
            ),
            if (extended) ...[
              const SizedBox(width: 12),
              Text(
                'KK-PDF-Tool',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.folder_outlined),
          selectedIcon: const Icon(Icons.folder),
          label: Text(tr('Bibliothek', 'Library')),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.handyman_outlined),
          selectedIcon: const Icon(Icons.handyman),
          label: Text(tr('Werkzeuge', 'Tools')),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: Text(tr('Einstellungen', 'Settings')),
        ),
      ],
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
    // The desktop layout has Settings in the side navigation instead.
    if (isWideLayout(context)) return const SizedBox.shrink();
    return IconButton(
      tooltip: tr('Einstellungen', 'Settings'),
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );
  }
}
