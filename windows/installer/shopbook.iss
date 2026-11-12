; Installateur Windows de ShopBook (Inno Setup 6).
; Compilé par GitHub Actions : iscc /DAppVersion=x.y.z windows\installer\shopbook.iss

#ifndef AppVersion
  #define AppVersion "3.0.0"
#endif

[Setup]
AppId={{6C1E6A57-2B7A-4C61-9E4B-5B0F3B7C9D21}
AppName=ShopBook
AppVersion={#AppVersion}
AppVerName=ShopBook {#AppVersion}
AppPublisher=ShopBook
DefaultDirName={autopf}\ShopBook
DefaultGroupName=ShopBook
DisableProgramGroupPage=yes
; Pas besoin d'être administrateur : installation pour l'utilisateur courant
; (l'utilisateur peut choisir « pour tous » s'il a les droits).
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\build\installer
OutputBaseFilename=ShopBook-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\ShopBook.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\ShopBook"; Filename: "{app}\ShopBook.exe"
Name: "{group}\Désinstaller ShopBook"; Filename: "{uninstallexe}"
Name: "{autodesktop}\ShopBook"; Filename: "{app}\ShopBook.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ShopBook.exe"; Description: "Lancer ShopBook"; Flags: nowait postinstall skipifsilent

; Les données (base, sauvegardes) sont dans %APPDATA%\ShopBook :
; elles ne sont PAS supprimées à la désinstallation.
