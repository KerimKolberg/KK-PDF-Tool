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
  - PDF → PowerPoint (offline: jede Seite als Bild-Folie, nicht text-editierbar)
  - PowerPoint → PDF (☁️ über das eigene Google-Konto, siehe unten)
  - PDF → Word (☁️ über das eigene Google-Konto, mit Texterkennung/OCR)

Die offline PDF-Werkzeuge rendern Seiten neu (Rasterung), da es keine reine
Dart/Flutter-Bibliothek gibt, die Vektor-Seiten zwischen bestehenden PDFs
kopieren kann. Ergebnis sieht optisch identisch aus, ist aber nicht mehr
text-durchsuchbar.

## Google-Verbindung einrichten (für PowerPoint→PDF und PDF→Word)

Diese beiden Werkzeuge laden die Datei kurz in *dein eigenes* Google Drive
hoch, lassen Google sie umwandeln, und laden das Ergebnis wieder herunter
(danach wird die Datei bei Google sofort wieder gelöscht). Das ist kostenlos,
braucht aber einmalige Einrichtung und Internetzugang beim Umwandeln.

### 1. Google-Cloud-Projekt anlegen

1. Öffne [console.cloud.google.com](https://console.cloud.google.com/), leg
   (falls noch nicht vorhanden) ein neues Projekt an.
2. **APIs & Services → Enabled APIs** → **"Google Drive API"** aktivieren.
3. **APIs & Services → OAuth consent screen**: Nutzertyp "External", App-Namen
   vergeben, deine eigene E-Mail als **Testnutzer** hinzufügen (reicht für
   persönliche Nutzung, muss nicht veröffentlicht/verifiziert werden).

### 2. Zwei OAuth-Client-IDs anlegen

Unter **APIs & Services → Credentials → Create Credentials → OAuth client ID**:

**a) Android-Client** (damit sich die App überhaupt anmelden darf):
- Application type: **Android**
- Package name: `com.kerimkolberg.doc_scanner`
- SHA-1: `89:77:6C:71:A4:DA:47:B3:3F:05:9C:3A:6B:B4:3E:5D:EF:98:2D:97`
  (fester Signierschlüssel dieser App, siehe Abschnitt "Signierschlüssel" unten)

**b) Web-Client** (dessen Client-ID trägst du in der App ein):
- Application type: **Web application**
- Name beliebig, sonst nichts weiter ausfüllen
- Nach dem Erstellen die **Client-ID** kopieren (endet auf `.apps.googleusercontent.com`)

### 3. Client-ID in der App eintragen

In der App: **Bibliothek → Zahnrad-Symbol (Einstellungen)** → Feld
"Google Web-Client-ID" → die kopierte Web-Client-ID einfügen → Speichern.

Das war's — keine neue APK nötig, die Einstellung wird direkt in der App
gespeichert.

## Signierschlüssel (wichtig für Google Sign-In)

Damit sich die App bei Google immer mit demselben SHA-1-Fingerabdruck
ausweist (sonst müsstest du bei jedem Build den Android-OAuth-Client neu
konfigurieren), signiert die GitHub-Actions-Pipeline die APK mit einem
festen, eigens für dieses Projekt erzeugten Schlüssel statt mit dem
zufälligen Standard-Debug-Key. Dafür müssen einmalig drei
**Repository-Secrets** hinterlegt werden (**Settings → Secrets and
variables → Actions → New repository secret**):

| Secret-Name | Wert |
|---|---|
| `DOCSCANNER_KEYSTORE_BASE64` | Inhalt der `docscanner-release.jks`-Datei, Base64-kodiert |
| `DOCSCANNER_KEYSTORE_PASSWORD` | Keystore-Passwort |
| `DOCSCANNER_KEY_ALIAS` | `docscanner` |
| `DOCSCANNER_KEY_PASSWORD` | (gleiches Passwort wie Keystore, PKCS12-Format) |

Die `.jks`-Datei und die Passwörter wurden dir separat zugeschickt — falls
du sie nicht mehr hast, frag noch mal danach, statt sie im Repo abzulegen
(es ist öffentlich!). Ohne diese Secrets baut die App trotzdem ganz normal
(nur eben mit wechselndem Debug-Schlüssel, wodurch Google Sign-In dann bei
jedem Neu-Build neu eingerichtet werden müsste).

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

## Bekannte Einschränkungen

- Automatische Kantenerkennung (ML Kit) gibt es nur auf Android, nicht unter
  Windows (dafür existiert keine vergleichbare Offline-Bibliothek).
- PDF → PowerPoint erzeugt Bild-Folien, keine text-editierbare Rekonstruktion
  (dafür gibt es keinen kostenlosen Dienst).
- PowerPoint → PDF und PDF → Word brauchen Internet und ein Google-Konto.
- Kein automatischer Cloud-Sync der Bibliothek, alles bleibt sonst lokal auf
  dem Gerät.
