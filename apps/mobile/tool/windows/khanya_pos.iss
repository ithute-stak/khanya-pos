#define MyAppName "Khanya POS"
#ifndef MyAppVersion
  #define MyAppVersion "0.4.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\windows\installer"
#endif

[Setup]
AppId={{4D90A0A7-CCF0-4AE6-B74F-F27DEBB8312A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Ithute
DefaultDirName={localappdata}\Programs\Khanya POS
DefaultGroupName=Khanya POS
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=KhanyaPOS-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
WizardStyle=modern
UninstallDisplayName=Khanya POS
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Khanya POS"; Filename: "{app}\khanya_pos.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Khanya POS"; Filename: "{app}\khanya_pos.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\khanya_pos.exe"; Description: "Launch Khanya POS"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
