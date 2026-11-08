@echo off
rem Oyunu editor acmadan dogrudan calistirir.
setlocal
set GODOT_EXE=%~dp0godot\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT_EXE%" (
  call "%~dp0kurulum.bat"
  exit /b
)
start "" "%GODOT_EXE%" --path "%~dp0.."
endlocal
