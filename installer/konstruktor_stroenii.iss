; ============================================================================
;  Конструктор Строений — Inno Setup script (v68.11)
;  Собирает установочный .exe для Windows из готового
;  build/windows/x64/runner/Release/.
;
;  Использование:
;    1) Соберите Flutter-приложение:
;          flutter build windows --release
;    2) Установите Inno Setup 6+ (https://jrsoftware.org/isdl.php).
;    3) Запустите ISCC.exe на этом скрипте:
;          "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\konstruktor_stroenii.iss
;       или откройте файл двойным щелчком и нажмите F9 (Build).
;    4) Готовый установщик появится в:
;          installer\Output\KonstruktorStroenii-Setup-1.0.0.exe
; ============================================================================

#define MyAppName "Конструктор Строений"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Конструктор Строений"
#define MyAppURL "https://konstruktor-stroenii.ru/"
#define MyAppExeName "konstruktor_stroenii.exe"
; Корневая папка собранного бинарника, относительно этого .iss.
#define BuildRoot "..\build\windows\x64\runner\Release"

[Setup]
AppId={{B7F2C5A9-4D3E-4F2A-9C8B-7E1D6F4A0B12}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputBaseFilename=KonstruktorStroenii-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
MinVersion=10.0.17763
; Поддерживаем Windows 10 1809+ / Windows 11 (требование Flutter Windows
; embedder).

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1

[Files]
; Исполняемый файл и runtime-DLL Flutter, plus все плагины.
Source: "{#BuildRoot}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildRoot}\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
; data/ и плагины — рекурсивно.
Source: "{#BuildRoot}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
; Любые plugin DLL, сгенерированные flutter build (path_provider_windows и т.д.).
Source: "{#BuildRoot}\*.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
