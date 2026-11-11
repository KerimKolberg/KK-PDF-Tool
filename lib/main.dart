import 'package:flutter/material.dart';

import 'l10n.dart';
import 'screens/home_shell.dart';
import 'services/settings_service.dart';
import 'services/windows_desktop_service.dart';
import 'theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPrefs.init();
  await L10n.init();
  await SettingsService.loadThemeMode();
  await WindowsDesktopService.instance.init(args);
  runApp(const DocScannerApp());
}

class DocScannerApp extends StatelessWidget {
  const DocScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([SettingsService.themeMode, L10n.language]),
      builder: (context, _) => MaterialApp(
        // A new key rebuilds every screen, so all texts switch language.
        key: ValueKey(L10n.language.value),
        title: 'KK-PDF-Tool',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: SettingsService.themeMode.value,
        home: const HomeShell(),
      ),
    );
  }
}
