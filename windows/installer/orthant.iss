; Orthant's Windows installer, compiled by Inno Setup 6 (ISCC.exe) from a
; release build's bundle. tool/windows/make_installer.ps1 compiles it and
; passes every value below; nothing here is read from a build.
;
;   ISCC.exe /DAppVersion=1.1.0 /DAppBuild=8 /DReleaseName=1.1.0-beta.1
;            /DSourceDir=<bundle> /O<output dir> windows\installer\orthant.iss
;
; Per user, never per machine: the updater runs a downloaded installer as the
; user, and one that needed administrator rights would ask for them at every
; update. It installs into the user's own programs folder, the same folder at
; every update (Inno keeps a previous install's folder by AppId), so the path
; a startup entry names stays this copy's.

#ifndef AppVersion
  #error AppVersion is required: the release's three-integer version
#endif
#ifndef AppBuild
  #error AppBuild is required: the build number
#endif
#ifndef ReleaseName
  #error ReleaseName is required: the tag's own name
#endif
#ifndef SourceDir
  #error SourceDir is required: the release build's bundle
#endif

[Setup]
; Permanent once shipped: Windows and Inno know an installed copy by it, and
; a new one would install a second Orthant beside the first.
AppId={{2CB97B64-A74B-4CDD-8EB5-5C67F7689DDD}
AppName=Orthant
AppVersion={#ReleaseName}
AppVerName=Orthant {#ReleaseName}
; The Add or Remove Programs publisher, which a winget manifest matches. The
; project's name, as the version resource's CompanyName is.
AppPublisher=Orthant
AppPublisherURL=https://orthant.app
AppSupportURL=https://github.com/orthant-app/orthant/issues
VersionInfoVersion={#AppVersion}.{#AppBuild}
VersionInfoProductVersion={#AppVersion}
VersionInfoProductTextVersion={#ReleaseName}
PrivilegesRequired=lowest
DefaultDirName={autopf}\Orthant
DisableDirPage=yes
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputBaseFilename=Orthant-{#ReleaseName}-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Orthant.exe
UninstallDisplayName=Orthant
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; Setup closes a running Orthant itself (CloseOrthant, below), never through
; the Restart Manager: on Windows on ARM that also lists the x64 emulator's
; translation cache (XtaCache), which a per-user Setup may not close, and then
; closes nothing, and a silent install aborts on the file in use (measured).
; Off, it also asks nobody on an interactive Setup to close that service.
CloseApplications=no
RestartApplications=no
#ifdef SignTool
SignTool={#SignTool}
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Orthant"; Filename: "{app}\Orthant.exe"

[Run]
; Run by hand: a box on the last page, unless Orthant comes back on its own.
; Silent, from winget: not launched, unless it was running.
Filename: "{app}\Orthant.exe"; Description: "Launch Orthant"; Flags: nowait postinstall skipifsilent; Check: not ShouldRelaunch
; Orthant comes back if it was running when Setup began (Setup closed it) or
; the updater asked (/RELAUNCH=1): installing over a running copy, by the
; updater, by winget or by hand, leaves it running.
Filename: "{app}\Orthant.exe"; Flags: nowait; Check: ShouldRelaunch

[Registry]
; Created by the app, never here; removed with it. Orthant writes only the Run
; value; Windows writes the StartupApproved record when the user turns the
; entry off or on in Task Manager or Settings. Software\Orthant holds the
; settings window's frame and the updater's settings.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Orthant"; Flags: uninsdeletevalue dontcreatekey
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"; ValueType: none; ValueName: "Orthant"; Flags: uninsdeletevalue dontcreatekey
Root: HKCU; Subkey: "Software\Orthant"; ValueType: none; Flags: uninsdeletekey dontcreatekey

[Code]
var
  WasRunning: Boolean;
  // Whether Setup reached its end, and the installed copy's files as they were
  // before Setup touched them (only when Orthant is to come back).
  Installed: Boolean;
  Before: TStringList;
  BeforeWhole: Boolean;

const
  ERROR_NO_MORE_FILES = 18;

function GetLastError: Cardinal;
  external 'GetLastError@kernel32.dll stdcall';

function RelaunchRequested: Boolean;
begin
  Result := ExpandConstant('{param:RELAUNCH|0}') = '1';
end;

function ShouldRelaunch: Boolean;
begin
  Result := WasRunning or RelaunchRequested;
end;

// Orthant keeps a hidden panel on every monitor for as long as it runs.
function OrthantRunning: Boolean;
begin
  Result := FindWindowByClassName('ORTHANT_OVERLAY_PANEL') <> 0;
end;

// Asks a running Orthant to quit as its tray's Quit does (the runner's
// OrthantQuitRequest, broadcast), and waits up to ten seconds; ends it if it
// is still there (a hung process). True if one was running.
function CloseOrthant: Boolean;
var
  I, Code: Integer;
begin
  Result := OrthantRunning;
  if not Result then
    exit;
  PostBroadcastMessage(RegisterWindowMessage('OrthantQuitRequest'), 0, 0);
  for I := 1 to 100 do
  begin
    if not OrthantRunning then
      exit;
    Sleep(100);
  end;
  Log('Orthant did not quit within 10 seconds of the request: ending it');
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM Orthant.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
  for I := 1 to 50 do
  begin
    if not OrthantRunning then
      exit;
    Sleep(100);
  end;
end;

// winget's switch: nobody is there to read a message box, and winget reports
// Setup's failure itself.
function VerySilent: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/VERYSILENT') = 0 then
      Result := True;
end;

// Every file of the installed copy under Dir, as its path below {app} and its
// SHA-256. The uninstaller's own files are left out: Setup rewrites them
// first, and Orthant does not need them to run. False if the list is not
// whole: a directory that could not be listed, or listed only in part, or a
// file that could not be read. FindNext stops at an error as at the end, so
// only ERROR_NO_MORE_FILES after it is the end.
function ListFiles(const Dir, Rel: String; List: TStringList): Boolean;
var
  F: TFindRec;
begin
  Result := FindFirst(Dir + '\*', F);
  if not Result then
  begin
    Log('Not listed: ' + Dir);
    exit;
  end;
  try
    repeat
      if (F.Name <> '.') and (F.Name <> '..') then
      begin
        if (F.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
        begin
          if not ListFiles(Dir + '\' + F.Name, Rel + F.Name + '\', List) then
            Result := False;
        end
        else if (Rel <> '') or (Pos('unins', Lowercase(F.Name)) <> 1) then
        begin
          try
            List.Add(Rel + F.Name + ' ' + GetSHA256OfFile(Dir + '\' + F.Name));
          except
            Log('Not read: ' + Dir + '\' + F.Name);
            Result := False;
          end;
        end;
      end;
    until not FindNext(F);
    if GetLastError <> ERROR_NO_MORE_FILES then
    begin
      Log('Not listed in full: ' + Dir);
      Result := False;
    end;
  finally
    FindClose(F);
  end;
end;

// The installed copy's files, sorted; Whole says whether every one of them
// was listed and read.
function InstalledFiles(var Whole: Boolean): TStringList;
begin
  Result := TStringList.Create;
  Whole := ListFiles(ExpandConstant('{app}'), '', Result);
  Result.Sort;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  WasRunning := CloseOrthant;
  if OrthantRunning then
    Result := 'Orthant is still running. Quit it from its icon in the notification area, then run Setup again.'
  else
  begin
    Result := '';
    // Recorded before anything changes, so that a Setup which stops part way
    // can tell whether it left Orthant as it was (DeinitializeSetup).
    if ShouldRelaunch and FileExists(ExpandConstant('{app}\Orthant.exe')) then
      Before := InstalledFiles(BeforeWhole);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    Installed := True;
end;

// Setup was to bring Orthant back (it closed it, or the updater asked) and
// stopped before finishing: cancelled, or a file it could not write, after
// which it rolls back what it can. Orthant is started again only when both
// lists, before and after, are whole and the same. Partly replaced, or not
// known to be whole, it may not run, so it is left closed and the person is
// told what to do.
procedure DeinitializeSetup;
var
  After: TStringList;
  AfterWhole: Boolean;
  Code: Integer;
begin
  if (Before = nil) or Installed then
    exit;
  After := InstalledFiles(AfterWhole);
  try
    if BeforeWhole and AfterWhole and (After.Text = Before.Text) then
    begin
      Log('Setup stopped before finishing, with Orthant as it was: starting it again');
      Exec(ExpandConstant('{app}\Orthant.exe'), '', ExpandConstant('{app}'), SW_SHOWNORMAL, ewNoWait, Code);
    end
    else if BeforeWhole and AfterWhole then
    begin
      Log('Setup stopped part way, with some of Orthant''s files replaced: not starting it');
      if not VerySilent then
        MsgBox('Orthant could not be updated, and some of its files were already replaced, so it was not started again. Run the installer again to finish installing it, or download Orthant from orthant.app.', mbCriticalError, MB_OK);
    end
    else
    begin
      Log('Setup stopped before finishing, and not all of Orthant''s files could be read: not starting it');
      if not VerySilent then
        MsgBox('Orthant could not be updated, and whether its files are still whole could not be verified, so it was not started again. Run the installer again to finish installing it, or download Orthant from orthant.app.', mbCriticalError, MB_OK);
    end;
  finally
    After.Free;
    Before.Free;
  end;
end;

// After the uninstaller's "Are you sure" (a No leaves Orthant running), before
// it removes anything; one that cannot be closed stops it with nothing removed.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    CloseOrthant;
    if OrthantRunning then
    begin
      SuppressibleMsgBox('Orthant is still running. Quit it from its icon in the notification area, then uninstall it again.', mbCriticalError, MB_OK, IDOK);
      Abort;
    end;
  end;
end;
