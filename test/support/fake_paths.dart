import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Points path_provider at a fresh temporary folder, so services that store
/// files can run in tests.
class FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final Directory root = Directory.systemTemp.createTempSync('kk_pdf_tool_test');

  static FakePaths install() {
    final paths = FakePaths();
    PathProviderPlatform.instance = paths;
    return paths;
  }

  String _dir(String name) => (Directory('${root.path}/$name')..createSync(recursive: true)).path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');
  @override
  Future<String?> getTemporaryPath() async => _dir('temp');
  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');
  @override
  Future<String?> getDownloadsPath() async => _dir('downloads');
}
