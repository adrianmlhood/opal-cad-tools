@echo off
setlocal
rem Opal CAD Tools installer -- copies the plugin bundle into AutoCAD's
rem per-user add-in folder. No admin rights required.

set "DEST=%APPDATA%\Autodesk\ApplicationPlugins\OpalTools.bundle"
set "SRC=%~dp0OpalTools.bundle"
if not exist "%SRC%" set "SRC=%~dp0bundle\OpalTools.bundle"

if not exist "%SRC%" (
  echo Could not find OpalTools.bundle next to this script.
  echo Keep Install.bat in the same folder as the OpalTools.bundle folder.
  pause
  exit /b 1
)

echo Installing Opal CAD Tools...
if exist "%DEST%" rmdir /s /q "%DEST%"
robocopy "%SRC%" "%DEST%" /e /njh /njs /ndl /nfl /nc /ns >nul
if errorlevel 8 (
  echo Install failed while copying files.
  pause
  exit /b 1
)

echo.
echo Opal CAD Tools installed.
echo Restart AutoCAD, then type O for the toolbox.
pause
