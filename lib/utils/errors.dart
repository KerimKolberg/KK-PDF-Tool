import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart' as rx;

import '../l10n.dart';

/// Turns an error into a sentence for the user, instead of technical text
/// like "PlatformException(save_failed, ...)" or "SocketException: Failed
/// host lookup". Errors the app raises itself already carry a readable
/// message and are passed through.
String describeError(Object error) {
  if (error is rx.PdfPasswordException) {
    return tr(
      'Die PDF ist passwortgeschützt. Bitte zuerst das Passwort entfernen.',
      'The PDF is password-protected. Please remove the password first.',
    );
  }
  if (error is rx.PdfException) {
    return tr(
      'Die Datei ist beschädigt oder keine gültige PDF.',
      'The file is damaged or not a valid PDF.',
    );
  }
  if (error is SocketException || error is http.ClientException || error is HandshakeException) {
    return tr(
      'Keine Verbindung zum Internet oder zum Server.',
      'No connection to the internet or the server.',
    );
  }
  if (error is TimeoutException) {
    return tr(
      'Keine Antwort - bitte die Internetverbindung prüfen und erneut versuchen.',
      'No response - please check the internet connection and try again.',
    );
  }
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    // 28 = ENOSPC (Android), 39/112 = disk full (Windows).
    if (code == 28 || code == 39 || code == 112) {
      return tr('Der Speicher ist voll.', 'The storage is full.');
    }
    // 13 = EACCES, 5 = access denied (Windows), 32 = file in use (Windows).
    if (code == 13 || code == 5 || code == 32) {
      return tr(
        'Kein Zugriff auf die Datei (vielleicht in einem anderen Programm geöffnet).',
        'No access to the file (maybe it is open in another program).',
      );
    }
    if (code == 2) return tr('Die Datei existiert nicht mehr.', 'The file no longer exists.');
    return tr('Dateifehler: ${error.message}', 'File error: ${error.message}');
  }
  if (error is PlatformException) return error.message ?? error.code;
  if (error is FormatException) return error.message;
  if (error is OutOfMemoryError) {
    return tr(
      'Nicht genug Arbeitsspeicher - bitte die Datei aufteilen oder kleinere Bilder verwenden.',
      'Not enough memory - please split the file or use smaller images.',
    );
  }
  return error.toString().replaceFirst(RegExp(r'^(Exception|Bad state|Error): '), '');
}
