@echo off
setlocal
rem Opal CAD Tools uninstaller -- removes the plugin bundle from AutoCAD's
rem per-user add-in folder.

set "DEST=%APPDATA%\Autodesk\ApplicationPlugins\OpalTools.bundle"

if not exist "%DEST%" (
  echo Opal CAD Tools is not installed.
  pause
  exit /b 0
)

echo Removing Opal CAD Tools...
rmdir /s /q "%DEST%"

echo.
echo Opal CAD Tools removed. Restart AutoCAD to complete.
pause
