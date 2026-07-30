#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\src\NTranslate.App\bin\Release\net10.0-windows10.0.19041.0\win-x64\publish"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\artifacts"
#endif

[Setup]
AppId={{3EA8BB3D-ED91-44A5-9A06-BED0A13059C0}
AppName=NTranslate
AppVersion={#AppVersion}
AppPublisher=Ninh Nguyen
DefaultDirName={localappdata}\Programs\NTranslate
DefaultGroupName=NTranslate
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=yes
OutputDir={#OutputDir}
OutputBaseFilename=NTranslate-{#AppVersion}-win-x64-setup
Compression=lzma
SolidCompression=yes
UninstallDisplayIcon={app}\NTranslate.App.exe

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\NTranslate"; Filename: "{app}\NTranslate.App.exe"

[Code]
function IsLegacyMsixInstalled: Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec('powershell.exe',
    '-NoProfile -NonInteractive -Command "if (Get-AppxPackage -Name NinhNguyen375.NTranslate) { exit 1 } else { exit 0 }"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 1);
end;

function InitializeSetup(): Boolean;
begin
  if IsLegacyMsixInstalled then
  begin
    MsgBox('NTranslate is currently installed as an MSIX package. Please manually uninstall it from Windows Settings > Apps before running this installer.', mbError, MB_OK);
    Result := False;
  end
  else
    Result := True;
end;
