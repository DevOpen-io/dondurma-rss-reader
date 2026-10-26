; Inno Setup script for the GitHub release installer.
; Built by .github/workflows/github-apk-release.yml:
;   iscc /DAppVersion=1.2.3 /DOutputName=Dondurma-...-setup windows\installer\dondurma.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef OutputName
  #define OutputName "Dondurma-setup"
#endif

[Setup]
AppId={{BBA6E887-4DF3-4503-8B1F-9D027CC6E14B}
AppName=Dondurma RSS Reader
AppVersion={#AppVersion}
AppPublisher=DevOpen
DefaultDirName={autopf}\Dondurma RSS Reader
DefaultGroupName=Dondurma RSS Reader
DisableProgramGroupPage=yes
; Per-user install: no UAC prompt for an unsigned installer.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\dondurma.exe
OutputDir=..\..\dist
OutputBaseFilename={#OutputName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Dondurma RSS Reader"; Filename: "{app}\dondurma.exe"
Name: "{autodesktop}\Dondurma RSS Reader"; Filename: "{app}\dondurma.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\dondurma.exe"; Description: "{cm:LaunchProgram,Dondurma RSS Reader}"; Flags: nowait postinstall skipifsilent
