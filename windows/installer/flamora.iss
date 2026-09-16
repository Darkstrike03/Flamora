; Flamora Windows installer.
; Built by CI (.github/workflows/release.yml): `flutter build windows
; --release` runs first, then: iscc /DAppVersion=<x.y.z> flamora.iss
; Paths below are relative to this script's directory.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
; Stable identity so upgrades replace (not duplicate) the install.
AppId={{B6D0C18C-120F-40BA-B407-61429A9C0B73}
AppName=Flamora
AppVersion={#AppVersion}
AppVerName=Flamora {#AppVersion}
AppPublisher=Darkstrike03
DefaultDirName={autopf}\Flamora
DefaultGroupName=Flamora
OutputDir=output
OutputBaseFilename=Flamora-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Per-user install, no UAC prompt.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\flamora.exe
LicenseFile=..\..\LICENSE

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Flamora"; Filename: "{app}\flamora.exe"
Name: "{autodesktop}\Flamora"; Filename: "{app}\flamora.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\flamora.exe"; Description: "{cm:LaunchProgram,Flamora}"; Flags: nowait postinstall skipifsilent
