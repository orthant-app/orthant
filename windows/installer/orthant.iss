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
; Setup picks its language by Windows' display language (English, Simplified or
; Traditional Chinese) and falls back to English silently. The default would
; show a "Select Language" dialog to everyone whose Windows is neither.
ShowLanguageDialog=no
; Its default, yes, reuses the language the previous install recorded under the
; AppId, even with the dialog suppressed and in a silent run: every existing
; install recorded english, so a friend updating on Chinese Windows would keep
; an English installer for good.
UsePreviousLanguage=no
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
; Inno Setup 6.7.1, the version on the release runner, has no official Chinese
; (7.1.0 adds it; make_installer.ps1 takes only Inno 6), so the two translations
; beside this script are vendored byte for byte from jrsoftware/issrc at tag
; is-6_7_1, Files/Languages/Unofficial/ (windows/installer/*.isl is -text in
; .gitattributes so git keeps them so). ChineseSimplified.isl targets Inno Setup
; 6.5.0+ and ChineseTraditional.isl 6.1.0+. Replace one only by vendoring the
; new file whole and recording its hash here. Source and SHA-256 of each:
;
; ChineseSimplified.isl
; https://raw.githubusercontent.com/jrsoftware/issrc/is-6_7_1/Files/Languages/Unofficial/ChineseSimplified.isl
; sha256 7d544b9bb1d142cfa11f2e5d3cc8abe2e55f8e066c5124e3772675aa236e1278
;
; ChineseTraditional.isl
; https://raw.githubusercontent.com/jrsoftware/issrc/is-6_7_1/Files/Languages/Unofficial/ChineseTraditional.isl
; sha256 ab22b0ebf82969d1c9a7208e0e9f60e5119c0c95b9dacc00eb8e5582c7d3c604
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"
Name: "chinesetraditional"; MessagesFile: "ChineseTraditional.isl"

[CustomMessages]
; Orthant's own installer text, one definition per language: a literal in the
; script would be English for everyone. The English is what the script said
; before it was translated. The Chinese names the tray as Windows 11 does on each
; Chinese Windows (系统托盘 on zh-CN, 系統匣 on zh-TW).
english.LaunchOrthant=Launch Orthant
chinesesimplified.LaunchOrthant=启动 Orthant
chinesetraditional.LaunchOrthant=啟動 Orthant
english.StillRunningSetup=Orthant is still running. Quit it from its icon in the notification area, then run Setup again.
chinesesimplified.StillRunningSetup=Orthant 仍在运行。请从系统托盘中的图标退出 Orthant，然后重新运行安装程序。
chinesetraditional.StillRunningSetup=Orthant 仍在執行。請從系統匣中的圖示結束 Orthant，然後重新執行安裝程式。
english.StillRunningUninstall=Orthant is still running. Quit it from its icon in the notification area, then uninstall it again.
chinesesimplified.StillRunningUninstall=Orthant 仍在运行。请从系统托盘中的图标退出 Orthant，然后重新卸载。
chinesetraditional.StillRunningUninstall=Orthant 仍在執行。請從系統匣中的圖示結束 Orthant，然後重新解除安裝。
english.UpdateStoppedPartWay=Orthant could not be updated, and some of its files were already replaced, so it was not started again. Run the installer again to finish installing it, or download Orthant from orthant.app.
chinesesimplified.UpdateStoppedPartWay=Orthant 未能更新，且部分文件已被替换，因此没有重新启动它。请重新运行安装程序以完成安装，或从 orthant.app 下载 Orthant。
chinesetraditional.UpdateStoppedPartWay=Orthant 無法更新，且部分檔案已被取代，因此沒有重新啟動。請重新執行安裝程式以完成安裝，或從 orthant.app 下載 Orthant。
english.UpdateStoppedUnverified=Orthant could not be updated, and whether its files are still whole could not be verified, so it was not started again. Run the installer again to finish installing it, or download Orthant from orthant.app.
chinesesimplified.UpdateStoppedUnverified=Orthant 未能更新，且无法确认其文件是否完整，因此没有重新启动它。请重新运行安装程序以完成安装，或从 orthant.app 下载 Orthant。
chinesetraditional.UpdateStoppedUnverified=Orthant 無法更新，也無法確認其檔案是否完整，因此沒有重新啟動。請重新執行安裝程式以完成安裝，或從 orthant.app 下載 Orthant。

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Orthant"; Filename: "{app}\Orthant.exe"

[Run]
; Run by hand: a box on the last page, unless Orthant comes back on its own.
; Silent, from winget: not launched, unless it was running.
Filename: "{app}\Orthant.exe"; Description: "{cm:LaunchOrthant}"; Flags: nowait postinstall skipifsilent; Check: not ShouldRelaunch
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
  // Whether the log already says a process from the install folder outlived
  // its panels (OrthantRunning), so that a run of Setup records it once.
  ProcessLogged: Boolean;

const
  ERROR_NO_MORE_FILES = 18;

function GetLastError: Cardinal;
  external 'GetLastError@kernel32.dll stdcall';

function GetTickCount64: Int64;
  external 'GetTickCount64@kernel32.dll stdcall';

function RelaunchRequested: Boolean;
begin
  Result := ExpandConstant('{param:RELAUNCH|0}') = '1';
end;

function ShouldRelaunch: Boolean;
begin
  Result := WasRunning or RelaunchRequested;
end;

// Whether a process runs Orthant.exe from the folder Setup writes, asked of
// WMI, which answers for one's own processes without elevation. Another
// person's Orthant is installed in their own profile, so not in this folder.
// Any failure answers False, as Setup decided before this test.
function OrthantProcessInFolder: Boolean;
var
  Locator, Service, Found: Variant;
  Path: String;
begin
  Result := False;
  // In a WQL string a backslash and a quote are each escaped with a
  // backslash: backslashes first, so that the quotes' escapes stay single.
  Path := ExpandConstant('{app}\Orthant.exe');
  StringChangeEx(Path, '\', '\\', True);
  StringChangeEx(Path, '''', '\''', True);
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\CIMV2');
    Found := Service.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE ExecutablePath = ''' + Path + '''');
    Result := Found.Count > 0;
  except
    Log('Could not ask Windows which processes run from ' + ExpandConstant('{app}') + ': ' + GetExceptionMessage);
  end;
end;

// Orthant keeps a hidden panel on every monitor for as long as it runs, and
// holds the mutex OrthantRunning for as long as its process exists, which can
// be seconds after the panels have gone. A copy built before the mutex (1.1.0
// and earlier) has only the panels, and that gap: its process is asked of WMI,
// and only when neither of the others answers (the script's or short-circuits).
function OrthantRunning: Boolean;
begin
  Result := (FindWindowByClassName('ORTHANT_OVERLAY_PANEL') <> 0) or CheckForMutexes('OrthantRunning');
  if not Result then
  begin
    Result := OrthantProcessInFolder;
    if Result and not ProcessLogged then
    begin
      Log('Orthant has no panel or mutex, but a process still runs from ' + ExpandConstant('{app}') + ': waiting for it');
      ProcessLogged := True;
    end;
  end;
end;

// Whether Orthant is gone within Ms milliseconds, asked every 100 ms. Timed by
// the clock, not by counting polls: one that asks WMI takes about twice as
// long, which stretched ten seconds to nineteen (measured).
function GoneWithin(Ms: Integer): Boolean;
var
  Deadline: Int64;
begin
  Deadline := GetTickCount64 + Ms;
  repeat
    Result := not OrthantRunning;
    if Result then
      exit;
    Sleep(100);
  until GetTickCount64 >= Deadline;
end;

// Asks a running Orthant to quit as its tray's Quit does (the runner's
// OrthantQuitRequest, broadcast), and waits up to ten seconds; ends it if it
// is still there (a hung process), and waits up to thirty more for it to be
// gone, which on a slow machine has taken up to twenty (measured). True if one
// was running.
function CloseOrthant: Boolean;
var
  Code: Integer;
begin
  Result := OrthantRunning;
  if not Result then
    exit;
  PostBroadcastMessage(RegisterWindowMessage('OrthantQuitRequest'), 0, 0);
  if GoneWithin(10000) then
    exit;
  Log('Orthant did not quit within 10 seconds of the request: ending it');
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM Orthant.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
  GoneWithin(30000);
end;

// Setup shows nothing at all: winget passes /VERYSILENT for `winget install
// --silent` (its default, like WinSparkle's update, is /SILENT, which shows
// progress to someone who may be watching). Nobody is there to read a message
// box, and the caller reports Setup's failure itself.
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
    Result := CustomMessage('StillRunningSetup')
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
        MsgBox(CustomMessage('UpdateStoppedPartWay'), mbCriticalError, MB_OK);
    end
    else
    begin
      Log('Setup stopped before finishing, and not all of Orthant''s files could be read: not starting it');
      if not VerySilent then
        MsgBox(CustomMessage('UpdateStoppedUnverified'), mbCriticalError, MB_OK);
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
      SuppressibleMsgBox(CustomMessage('StillRunningUninstall'), mbCriticalError, MB_OK, IDOK);
      Abort;
    end;
  end;
end;
