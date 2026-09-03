Unicode True
Name "Car Simulator"
OutFile "..\build\installer\CarSimulatorSetup.exe"
InstallDir "$PROGRAMFILES64\Car Simulator"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

!include "MUI2.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\orange-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\orange-uninstall.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Russian"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "..\build\windows\*.*"
  CreateShortCut "$DESKTOP\Car Simulator.lnk" "$INSTDIR\CarSimulator.exe"
  CreateDirectory "$SMPROGRAMS\Car Simulator"
  CreateShortCut "$SMPROGRAMS\Car Simulator\Car Simulator.lnk" "$INSTDIR\CarSimulator.exe"
  CreateShortCut "$SMPROGRAMS\Car Simulator\Uninstall.lnk" "$INSTDIR\Uninstall.exe"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\CarSimulator" "DisplayName" "Car Simulator"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\CarSimulator" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\CarSimulator" "DisplayVersion" "1.0.0"
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\Car Simulator.lnk"
  RMDir /r "$SMPROGRAMS\Car Simulator"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\CarSimulator"
SectionEnd
