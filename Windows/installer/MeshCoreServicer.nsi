; Native, per-user Windows installer. Payload and ownership list are generated
; from a validated self-contained publication by build_installer.py.
Unicode true
RequestExecutionLevel user
ManifestSupportedOS Win10
ManifestDPIAware true
SetCompressor zlib
CRCCheck force
AllowSkipFiles off
!include MUI2.nsh
!include LogicLib.nsh
!include WinVer.nsh
!include x64.nsh
!include WordFunc.nsh
!include FileFunc.nsh
!include TextFunc.nsh
!include StrFunc.nsh
${UnStrStr}

!ifndef APP_EXE
!define APP_EXE "MeshCoreServicer.exe"
!endif
!define PRODUCT "MeshCore Servicer"
!define ARP "Software\Microsoft\Windows\CurrentVersion\Uninstall\MeshCoreServicer"
Name "${PRODUCT} ${APP_VERSION} (${ARCH})"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\MeshCore Servicer"
BrandingText "MeshCore Servicer · nezávislý nástroj pro MeshCore"
VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey /LANG=1029 "ProductName" "${PRODUCT}"
VIAddVersionKey /LANG=1029 "FileDescription" "Instalace MeshCore Servicer (${ARCH})"
VIAddVersionKey /LANG=1029 "FileVersion" "${APP_VERSION}.0"
VIAddVersionKey /LANG=1029 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1029 "LegalCopyright" "MeshCore Servicer contributors"
!define MUI_ICON "${APP_ICON}"
!define MUI_UNICON "${APP_ICON}"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Instalace MeshCore Servicer"
!define MUI_WELCOMEPAGE_TEXT "Nainstaluje se verze ${APP_VERSION} pro ${ARCH}, včetně .NET runtime, pouze pro váš účet.$\r$\n$\r$\nPřed aktualizací ukončete aplikaci také v oznamovací oblasti. Profily, zprávy a hesla se zachovají.$\r$\n$\r$\nInstalátor se nepřipojuje k Bluetooth a nemění žádné zařízení."
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchApplication
!define MUI_FINISHPAGE_RUN_TEXT "Spustit MeshCore Servicer"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!define MUI_UNCONFIRMPAGE_TEXT_TOP "Odstraní se aplikace a její zástupci pro tento účet. Profily a historie v místních datech aplikace i hesla ve Správci přihlašovacích údajů zůstanou zachované."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "Czech"
Var MaintenanceMutex
Var OwnedList

; Holding the app's existing instance mutex prevents the app (or another setup)
; starting in the middle of extraction or removal. No process is killed.
!macro LockApplication Prefix
Function ${Prefix}LockApplication
retry:
  System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\MeshCoreServicer.Windows") p.r0 ?e'
  Pop $1
  ${If} $0 == 0
    MessageBox MB_OK|MB_ICONSTOP "Nelze bezpečně ověřit, zda aplikace běží." /SD IDOK
    SetErrorLevel 1603
    Quit
  ${EndIf}
  ${If} $1 == 183
    System::Call 'kernel32::CloseHandle(p r0)'
    IfSilent busy
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "MeshCore Servicer nebo jiný instalátor právě běží. Ukončete aplikaci přes menu v oznamovací oblasti a zvolte Opakovat." IDRETRY retry
busy:
    SetErrorLevel 1618
    Quit
  ${EndIf}
  StrCpy $MaintenanceMutex $0
FunctionEnd
!macroend
!insertmacro LockApplication ""
!insertmacro LockApplication "un."

Function .onInit
  SetShellVarContext current
  SetRegView 64
  ; Intentionally fixed. /D cannot redirect an ownership-based uninstaller to
  ; a user's data folder or a shared system directory.
  StrCpy $INSTDIR "$LOCALAPPDATA\Programs\MeshCore Servicer"
  ${IfNot} ${AtLeastBuild} 19041
    MessageBox MB_OK|MB_ICONSTOP "Je vyžadován Windows 10 2004 (sestavení 19041) nebo novější." /SD IDOK
    SetErrorLevel 1633
    Quit
  ${EndIf}
!if "${ARCH}" == "x64"
  ${IfNot} ${IsNativeAMD64}
!else
  ${IfNot} ${IsNativeARM64}
!endif
    MessageBox MB_OK|MB_ICONSTOP "Tento instalátor je určen pro ${ARCH}. Použijte balíček odpovídající procesoru Windows." /SD IDOK
    SetErrorLevel 1633
    Quit
  ${EndIf}
  ReadRegStr $0 HKCU "${ARP}" "DisplayVersion"
  ${If} $0 != ""
    ${VersionCompare} "$0" "${APP_VERSION}" $1
    ${If} $1 == 1
      MessageBox MB_OK|MB_ICONSTOP "Už je nainstalovaná novější verze. Starší instalátor ji nepřepíše." /SD IDOK
      SetErrorLevel 1638
      Quit
    ${EndIf}
  ${EndIf}
  Call LockApplication
FunctionEnd

Section "Aplikace, runtime a nabídka Start" MainSection
  SectionIn RO
  SetOutPath "$INSTDIR"
  SetOverwrite on
  ; Add entries before extracting so even an interrupted installation leaves
  ; a list of its own files. This list is cumulative across upgrades.
  ClearErrors
  FileOpen $OwnedList "$INSTDIR\installed-files.lst" a
  IfErrors install_failed
!include "${OWNERSHIP_INCLUDE}"
  FileClose $OwnedList
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  IfErrors install_failed
  ; Register early: a partially failed install can still be uninstalled/repaired.
  WriteRegStr HKCU "${ARP}" "DisplayName" "${PRODUCT}"
  WriteRegStr HKCU "${ARP}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${ARP}" "Architecture" "${ARCH}"
  WriteRegStr HKCU "${ARP}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${ARP}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "${ARP}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "${ARP}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegDWORD HKCU "${ARP}" "NoModify" 1
  WriteRegDWORD HKCU "${ARP}" "NoRepair" 1
  WriteRegDWORD HKCU "${ARP}" "EstimatedSize" ${PAYLOAD_KIB}
  IfErrors install_failed
!include "${PAYLOAD_INCLUDE}"
  IfErrors install_failed
  SetOutPath "$INSTDIR"
  CreateDirectory "$SMPROGRAMS\MeshCore Servicer"
  CreateShortcut "$SMPROGRAMS\MeshCore Servicer\MeshCore Servicer.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortcut "$SMPROGRAMS\MeshCore Servicer\Odinstalovat.lnk" "$INSTDIR\Uninstall.exe"
  IfErrors install_failed
  Goto install_done
install_failed_open:
  FileClose $OwnedList
install_failed:
  MessageBox MB_OK|MB_ICONSTOP "Instalace nebyla dokončená. Zkontrolujte místo na disku a oprávnění a spusťte instalátor znovu. Osobní data zůstala zachovaná." /SD IDOK
  SetErrorLevel 1603
  Abort
install_done:
SectionEnd
Section /o "Zástupce na ploše" DesktopSection
  CreateShortcut "$DESKTOP\MeshCore Servicer.lnk" "$INSTDIR\${APP_EXE}"
SectionEnd
!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${MainSection} "Aplikace ${APP_VERSION} (${ARCH}), potřebný .NET runtime, odinstalátor a zástupci v nabídce Start. Instalace pouze pro váš účet."
  !insertmacro MUI_DESCRIPTION_TEXT ${DesktopSection} "Volitelně přidá zástupce na plochu."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function LaunchApplication
  System::Call 'kernel32::CloseHandle(p $MaintenanceMutex)'
  StrCpy $MaintenanceMutex 0
  SetOutPath "$INSTDIR"
  ExecShell "open" "$INSTDIR\${APP_EXE}"
FunctionEnd

Function un.onInit
  SetShellVarContext current
  SetRegView 64
  StrCpy $0 "$LOCALAPPDATA\Programs\MeshCore Servicer"
  ${If} $INSTDIR != $0
    MessageBox MB_OK|MB_ICONSTOP "Odinstalátor musí být spuštěný z původní instalační složky tohoto účtu." /SD IDOK
    SetErrorLevel 1603
    Quit
  ${EndIf}
  IfFileExists "$INSTDIR\installed-files.lst" +4
    MessageBox MB_OK|MB_ICONSTOP "Chybí seznam nainstalovaných souborů. Nejprve opravte instalaci opětovným spuštěním instalátoru." /SD IDOK
    SetErrorLevel 1603
    Quit
  Call un.LockApplication
FunctionEnd

Section "Uninstall"
  SetOutPath "$TEMP"
  ClearErrors
  FileOpen $OwnedList "$INSTDIR\installed-files.lst" r
  IfErrors uninstall_failed
next_file:
  ClearErrors
  FileReadUTF16LE $OwnedList $0
  IfErrors files_done
  ${TrimNewLines} "$0" $0
  StrCmp $0 "" next_file
  ; Fail closed for modified manifests: no absolute paths, traversal, ADS,
  ; wildcard deletion or lines pointing outside this fixed installation root.
  ${UnStrStr} $1 "$0" ".."
  StrCmp $1 "" +2
    Goto manifest_invalid
  ${UnStrStr} $1 "$0" ":"
  StrCmp $1 "" +2
    Goto manifest_invalid
  ${UnStrStr} $1 "$0" "*"
  StrCmp $1 "" +2
    Goto manifest_invalid
  ${UnStrStr} $1 "$0" "?"
  StrCmp $1 "" +2
    Goto manifest_invalid
  StrCpy $1 "$0" 1
  StrCmp $1 "\" manifest_invalid
  StrCmp $1 "/" manifest_invalid
  GetFullPathName $2 "$INSTDIR\$0"
  StrLen $3 "$INSTDIR\"
  StrCpy $4 "$2" $3
  StrCmp $4 "$INSTDIR\" +2
    Goto manifest_invalid
  IfFileExists "$2" 0 next_file
  ClearErrors
  Delete "$2"
  IfErrors uninstall_failed_open
  ; Only remove empty directories. Extra user files are never recursively removed.
  ${GetParent} "$2" $2
remove_empty:
  StrCmp $2 "$INSTDIR" next_file
  RMDir "$2"
  ${GetParent} "$2" $2
  Goto remove_empty
files_done:
  FileClose $OwnedList
  Delete "$DESKTOP\MeshCore Servicer.lnk"
  Delete "$SMPROGRAMS\MeshCore Servicer\MeshCore Servicer.lnk"
  Delete "$SMPROGRAMS\MeshCore Servicer\Odinstalovat.lnk"
  RMDir "$SMPROGRAMS\MeshCore Servicer"
  DeleteRegKey HKCU "${ARP}"
  Delete "$INSTDIR\installed-files.lst"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Goto uninstall_done
manifest_invalid:
  FileClose $OwnedList
  MessageBox MB_OK|MB_ICONSTOP "Seznam souborů instalace není platný. Odinstalace byla zastavena; žádné další soubory se neodstraní. Opravte instalaci nebo kontaktujte správce." /SD IDOK
  SetErrorLevel 1603
  Abort
uninstall_failed_open:
  FileClose $OwnedList
uninstall_failed:
  MessageBox MB_OK|MB_ICONSTOP "Některé soubory nelze odstranit. Ukončete aplikaci a zkuste odinstalaci znovu. Registrace a seznam souborů zůstaly zachované." /SD IDOK
  SetErrorLevel 1603
  Abort
uninstall_done:
SectionEnd
