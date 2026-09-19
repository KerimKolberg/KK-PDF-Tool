import 'dart:io';

import 'package:flutter/services.dart';

class IncomingFile {
  final String path;
  final String name;
  final String? mimeType;

  const IncomingFile({required this.path, required this.name, this.mimeType});

  bool get isPdf =>
      mimeType == 'application/pdf' || path.toLowerCase().endsWith('.pdf');

  static IncomingFile? fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return null;
    final path = map['path'] as String?;
    if (path == null) return null;
    return IncomingFile(
      path: path,
      name: (map['name'] as String?) ?? 'geteilte_datei',
      mimeType: map['mimeType'] as String?,
    );
  }
}

/// Receives files the OS hands to DocScanner because the user picked it
/// from "Open with" or the share sheet for a PDF/image (Android only - see
/// the intent-filters in AndroidManifest.xml and the native handling in
/// MainActivity.kt).
class IncomingFileService {
  static const _methods = MethodChannel('docscanner/shared_files/methods');
  static const _events = EventChannel('docscanner/shared_files/events');

  /// The file that launched the app cold (if any). Only meaningful once,
  /// right after startup - the native side clears it after this call.
  Future<IncomingFile?> takeInitialFile() async {
    if (!Platform.isAndroid) return null;
    try {
      final map = await _methods.invokeMethod<Map<dynamic, dynamic>>(
        'getInitialSharedFile',
      );
      return IncomingFile.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  /// Files shared into the app while it's already running.
  Stream<IncomingFile> get onFileReceived {
    if (!Platform.isAndroid) return const Stream.empty();
    return _events.receiveBroadcastStream().map(
          (event) => IncomingFile.fromMap(event as Map<dynamic, dynamic>?),
        )
        .where((f) => f != null)
        .cast<IncomingFile>();
  }
}
