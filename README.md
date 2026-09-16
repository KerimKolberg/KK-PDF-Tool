# DocScanner

Eine einfache Dokumentenscanner-App (wie CamScanner) mit **einer** Flutter-Codebasis
für Android (APK) und Windows (EXE).

## Funktionen

- **Automatisch scannen (nur Android):** Google ML Kit erkennt das Dokument
  direkt in der Kamera-Vorschau und schneidet es automatisch zu, ganz wie bei
  CamScanner — läuft komplett offline auf dem Gerät.
- Foto aufnehmen (Kamera) oder vorhandenes Bild importieren
- Zuschnitt optional: Vier Ecken des Dokuments per Fingergeste/Maus anpassen →
  automatische Perspektivkorrektur, oder ganz überspringen (pro Scan
  umschaltbar, mit Standardwert in den Einstellungen)
- Drehen, Filter (Original, Farbe+, Graustufen, Schwarz/Weiß)
- Mehrere Seiten zu einem Dokument zusammenfassen
- Export als Mehrseiten-PDF, zusätzlich automatisch abgelegt unter
  `Downloads/DocScanner` (Android: über die MediaStore-API, Windows: im
  echten Downloads-Ordner)
- Bibliotheksansicht aller gespeicherten Scans, umbenennen, löschen, teilen
- **Werkzeuge-Tab:**
  - Bilder → PDF (mehrere Bilder zu einer PDF zusammenfassen)
  - PDF → Bilder (jede Seite als Bild exportieren)
  - PDFs zusammenführen (mehrere Dateien in gewählter Reihenfolge verbinden)
  - PDF aufteilen (nach einem oder mehreren Seitenbereichen)

Die PDF-Werkzeuge rendern Seiten neu (Rasterung), da es keine reine
Dart/Flutter-Bibliothek gibt, die Vektor-Seiten zwischen bestehenden PDFs
kopieren kann. Ergebnis sieht optisch identisch aus, ist aber nicht mehr
text-durchsuchbar.

## Fertige APK/EXE bauen — ohne eigene Installation (empfohlen)

Dieses Projekt enthält bereits eine GitHub-Actions-Pipeline
(`.github/workflows/build.yml`), die bei jedem Push automatisch **beide**
Artefakte baut:

1. Projekt in ein eigenes (privates oder öffentliches) GitHub-Repository pushen.
2. Im Reiter **Actions** den Workflow-Lauf abwarten (ca. 5–10 Minuten).
3. Unter dem abgeschlossenen Lauf im Bereich **Artifacts** zwei ZIP-Dateien
   herunterladen:
   - `doc-scanner-android-apk` → enthält `app-release.apk`
   - `doc-scanner-windows-exe` → enthält `doc-scanner-windows.zip`
     (die EXE plus alle nötigen DLLs/Daten — die ganze Zip auf dem PC entpacken,
     nicht nur die .exe herauskopieren)

## APK auf dem Tablet installieren

1. `app-release.apk` auf das Tablet übertragen (USB-Kabel, Google Drive, E-Mail …).
2. Auf dem Tablet die Datei antippen. Falls Android "Installation aus
   unbekannten Quellen blockiert" meldet: in den Einstellungen für die
   verwendete App (z. B. Dateien/Browser) einmalig erlauben.
3. Kamera-Berechtigung beim ersten Start zulassen.

## Lokal selbst bauen (alternativ)

Voraussetzung: [Flutter SDK](https://docs.flutter.dev/get-started/install)
installiert, `flutter doctor` läuft ohne rote Fehler.

```bash
flutter pub get

# Android-APK (auf dem Rechner ist Android SDK/Java nötig, siehe `flutter doctor`)
flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk

# Windows-EXE (muss auf einem echten Windows-Rechner mit Visual Studio
# "Desktop development with C++" gebaut werden – Cross-Build von Linux/Mac
# aus ist bei Flutter nicht möglich)
flutter config --enable-windows-desktop
flutter build windows --release
# -> build/windows/x64/runner/Release/  (ganzen Ordner kopieren, nicht nur die .exe)
```

## Projektstruktur

```
lib/
  main.dart                     Einstiegspunkt
  models/scan_document.dart     Datenmodell eines gespeicherten Scans
  services/
    document_store.dart         Speichern/Laden auf der Festplatte (JSON-Index)
    image_processing.dart       Perspektivkorrektur, Filter, JPEG-Encoding
    pdf_service.dart            PDF-Erzeugung aus den Seitenbildern
  screens/
    library_screen.dart         Startbildschirm: Liste aller Scans
    scan_flow_screen.dart       Mehrseitiger Scan-Vorgang
    capture_screen.dart         Kamera-Aufnahme / Datei-Import
    crop_screen.dart            Ecken anpassen, drehen, Filter wählen
    document_viewer_screen.dart Gespeichertes Dokument ansehen/teilen/löschen
  widgets/corner_crop_overlay.dart  Ziehbare Eck-Overlay-UI
```

## Bekannte Einschränkungen (v1)

- Die Eckenerkennung ist manuell (ziehen), es gibt keine automatische
  KI-Kantenerkennung wie bei CamScanner — das würde plattformspezifische
  Bibliotheken erfordern, die es für Windows nicht gibt, und hätte die
  "eine Codebasis für beides"-Anforderung gebrochen.
- Kein Login/Cloud-Sync, alles bleibt lokal auf dem Gerät.
