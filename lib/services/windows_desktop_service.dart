import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'settings_service.dart';

/// Windows only: tray icon (click = open, right-click = menu), starting
/// hidden in the tray, and "start with Windows" via the per-user Run key
/// (set with the built-in reg.exe, no extra dependency or admin rights).
class WindowsDesktopService with TrayListener {
  WindowsDesktopService._();
  static final instance = WindowsDesktopService._();

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'KK-PDF-Tool';
  static const minimizedArg = '--minimized';

  static bool get supported => Platform.isWindows;

  /// Shows the window - or keeps it hidden in the tray when started by
  /// Windows with [minimizedArg].
  Future<void> init(List<String> args) async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    final startHidden = args.contains(minimizedArg);
    await windowManager.waitUntilReadyToShow(null, () async {
      if (startHidden) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
    await trayManager.setIcon('assets/icon/app_icon.ico');
    await trayManager.setToolTip('KK-PDF-Tool');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Öffnen'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Beenden'),
    ]));
    trayManager.addListener(this);
    // After an update/reinstall the exe may live elsewhere; refresh the
    // autostart entry so it never points at a missing file.
    if (await isAutostartEnabled()) {
      await setAutostart(true, minimized: startMinimized);
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      _showWindow();
    } else if (menuItem.key == 'quit') {
      trayManager.destroy();
      windowManager.destroy();
    }
  }

  Future<bool> isAutostartEnabled() async {
    final result = await Process.run('reg', ['query', _runKey, '/v', _valueName]);
    return result.exitCode == 0;
  }

  bool get startMinimized => AppPrefs.getBool('windows.startMinimized', true);

  /// Registers/unregisters the app to start with Windows; with
  /// [minimized] it starts hidden in the tray.
  Future<void> setAutostart(bool enabled, {required bool minimized}) async {
    AppPrefs.setBool('windows.startMinimized', minimized);
    if (enabled) {
      final command = '"${Platform.resolvedExecutable}"${minimized ? ' $minimizedArg' : ''}';
      await Process.run('reg', ['add', _runKey, '/v', _valueName, '/t', 'REG_SZ', '/d', command, '/f']);
    } else {
      await Process.run('reg', ['delete', _runKey, '/v', _valueName, '/f']);
    }
  }
}
