import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';

import '../models/ocr_result.dart';
import 'image_processing.dart';

/// Offline text recognition via ML Kit (Android only, see MainActivity.kt).
/// Windows has no comparable offline engine, so callers fall back to the
/// Google Drive OCR in [GoogleDriveConvertService] there.
class OcrService {
  static const _channel = MethodChannel('docscanner/ocr');

  static bool get isOfflineAvailable => Platform.isAndroid;

  /// [imageBytes] should already be upright (see [normalizeOrientation]):
  /// the native side decodes raw pixels and ignores EXIF rotation.
  static Future<OcrResult> recognize(Uint8List imageBytes) async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'recognize',
      {'bytes': imageBytes},
    );
    if (map == null) throw const FormatException('Keine Antwort von der Texterkennung');
    return OcrResult.fromMap(map);
  }

  /// Bakes a JPEG's EXIF rotation into its pixels, so OCR coordinates, the
  /// stored page image and the PDF all agree on which way is up.
  static Future<Uint8List> normalizeOrientation(Uint8List bytes) async {
    final isJpeg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (!isJpeg) return bytes;
    try {
      if (PdfJpegInfo(bytes).orientation == PdfImageOrientation.topLeft) {
        return bytes;
      }
    } catch (_) {
      return bytes;
    }
    return compute(bakeOrientationJpegIsolate, bytes);
  }
}
