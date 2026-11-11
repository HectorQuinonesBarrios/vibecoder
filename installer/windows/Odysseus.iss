#ifndef AppVersion
  #define AppVersion "1.0.3"
#endif
#ifndef AppSourceDir
  #define AppSourceDir "..\..\dist\windows\Odysseus"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist\windows"
#endif
#ifndef InstallerSuffix
  #define InstallerSuffix "unsigned"
#endif

[Setup]
AppId={{BB40A2B5-7ED8-4FBB-8CF1-431FB92DA28C}
AppName=Odysseus
AppVersion={#AppVersion}
AppPublisher=Odysseus
DefaultDirName={localappdata}\Programs\Odysseus
DefaultGroupName=Odysseus
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=Odysseus-Setup-{#InstallerSuffix}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\Odysseus.exe
ArchitecturesInstallIn64BitMode=x64
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#AppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\scripts\update-coding-model.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

[Icons]
Name: "{group}\Odysseus"; Filename: "{app}\Odysseus.exe"
Name: "{autodesktop}\Odysseus"; Filename: "{app}\Odysseus.exe"; Tasks: desktopicon
Name: "{group}\Update coding model"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\update-coding-model.ps1"""
Name: "{group}\Enable weekly model refresh"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\update-coding-model.ps1"" -ScheduleWeekly"
Name: "{group}\Disable weekly model refresh"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\update-coding-model.ps1"" -RemoveSchedule"

[Run]
Filename: "{app}\Odysseus.exe"; Description: "Launch Odysseus"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\update-coding-model.ps1"" -RemoveSchedule"; Flags: runhidden waituntilterminated

[UninstallDelete]
Type: filesandordirs; Name: "{app}\_internal"