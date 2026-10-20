; SodaM Windows installer script (Inno Setup 6).
; Build (from repo root):
;   ISCC.exe /DMyAppVersion=<version> packaging/windows/sodam.iss
; Output: release/sodam-<version>-windows-x64-setup.exe
; Per-user install (no admin required), default dir {localappdata}\Programs\SodaM.
; NOTE: keep this file ASCII-only; Inno reads non-BOM files in the ANSI codepage.

#define MyAppName "SodaM"
#ifndef MyAppVersion
#define MyAppVersion "0.1.1"
#endif

[Setup]
AppId={{A1AAB6BA-EDE3-461D-9961-DA3CAAC0CFEC}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=sodahub-org
AppPublisherURL=https://github.com/sodahub-org/sodam
AppSupportURL=https://github.com/sodahub-org/sodam/issues
DefaultDirName={localappdata}\Programs\SodaM
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\release
OutputBaseFilename=sodam-{#MyAppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\sodam.exe
CloseApplications=force
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\target\release\sodam.exe"; DestDir: "{app}"; Flags: ignoreversion; BeforeInstall: SodamBeforeInstall

[Icons]
Name: "{autoprograms}\SodaM"; Filename: "{app}\sodam.exe"
Name: "{autodesktop}\SodaM"; Filename: "{app}\sodam.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sodam.exe"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Messages]
DontCloseApplications=&Cancel installation

[Code]
const
  GENERIC_WRITE = $40000000;
  OPEN_EXISTING = 3;
  ERROR_SHARING_VIOLATION = 32;
  INVALID_HANDLE_VALUE = -1;
  StillRunningMsg = 'Unable to close SodaM. Quit it from the tray menu (or end sodam.exe in Task Manager), then run Setup again.';
  CancelledMsg = 'Installation cancelled. SodaM was not closed.';

var
  SodamPromptShown: Boolean;

function CreateFileW(lpFileName: String; dwDesiredAccess: Cardinal;
  dwShareMode: Cardinal; lpSecurityAttributes: Cardinal;
  dwCreationDisposition: Cardinal; dwFlagsAndAttributes: Cardinal;
  hTemplateFile: Cardinal): Integer;
  external 'CreateFileW@kernel32.dll stdcall delayload';

function CloseHandle(hObject: Integer): Boolean;
  external 'CloseHandle@kernel32.dll stdcall delayload';

function SodamExeRunning: Boolean;
var
  H: Integer;
  ExePath: String;
begin
  Result := False;
  ExePath := ExpandConstant('{app}\sodam.exe');
  if not FileExists(ExePath) then
    Exit;

  H := CreateFileW(ExePath, GENERIC_WRITE, 0, 0, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then
    Result := (DLLGetLastError = ERROR_SHARING_VIOLATION)
  else
  begin
    CloseHandle(H);
    Result := False;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if WizardSilent and SodamExeRunning then
    Result := StillRunningMsg;
end;

procedure StopSodamProcess;
var
  ScriptPath: String;
  Script: String;
  ResultCode: Integer;
begin
  ScriptPath := ExpandConstant('{tmp}\sodam-close.ps1');
  Script :=
    '$target = $args[0]' + #13#10 +
    'Get-CimInstance Win32_Process -Filter "Name=''sodam.exe''" | ' +
    'Where-Object { $_.ExecutablePath -eq $target } | ' +
    'ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }';
  if SaveStringToFile(ScriptPath, Script, False) then
    Exec('powershell.exe',
      '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '" "' +
      ExpandConstant('{app}\sodam.exe') + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = wpPreparing) and WizardForm.PreparingYesRadio.Checked then
  begin
    StopSodamProcess;
    if SodamExeRunning then
    begin
      MsgBox(StillRunningMsg, mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpPreparing then
    SodamPromptShown := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssInstall) and SodamPromptShown and
     (not WizardForm.PreparingYesRadio.Checked) and SodamExeRunning then
  begin
    MsgBox(CancelledMsg, mbError, MB_OK);
    Abort;
  end;
end;

procedure SodamBeforeInstall;
begin
  if SodamExeRunning then
  begin
    MsgBox(StillRunningMsg, mbError, MB_OK);
    Abort;
  end;
end;
