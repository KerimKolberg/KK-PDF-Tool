; Inno Setup script for KK-PDF-Tool (built in CI, see .github/workflows/build.yml).
; Installs per user (no admin rights needed) into a fixed folder, adds Start
; menu and desktop shortcuts and a normal uninstaller. Running a newer setup
; updates the installed app in place; scans live in the user's Documents and
; are never touched.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{7C4E2B9A-3F1D-4C8E-9A6B-5D2F8E1C4A70}
AppName=KK-PDF-Tool
AppVersion={#AppVersion}
AppPublisher=Kerim Kolberg
DefaultDirName={localappdata}\Programs\KK-PDF-Tool
DefaultGroupName=KK-PDF-Tool
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=KK-PDF-Tool-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\KK-PDF-Tool.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\KK-PDF-Tool"; Filename: "{app}\KK-PDF-Tool.exe"
Name: "{autodesktop}\KK-PDF-Tool"; Filename: "{app}\KK-PDF-Tool.exe"; Tasks: desktopicon

[Registry]
; Remove the "start with Windows" entry the app may have created.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "KK-PDF-Tool"; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\KK-PDF-Tool.exe"; Description: "{cm:LaunchProgram,KK-PDF-Tool}"; Flags: nowait postinstall skipifsilent
