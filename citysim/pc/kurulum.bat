@echo off
rem Sehir Sim - bilgisayar kurulumu (bir kez calistir).
rem Godot 4.7.2'yi (CI ile ayni surum) bu klasore indirir ve projeyi editorde acar.
setlocal
cd /d "%~dp0"
set GODOT_DIR=%~dp0godot
set GODOT_EXE=%GODOT_DIR%\Godot_v4.7.2-stable_win64.exe
set GODOT_URL=https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip

if exist "%GODOT_EXE%" (
  echo Godot 4.7.2 zaten kurulu.
  goto ac
)

echo Godot 4.7.2 indiriliyor (yaklasik 70 MB)...
if not exist "%GODOT_DIR%" mkdir "%GODOT_DIR%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%GODOT_URL%' -OutFile '%GODOT_DIR%\godot.zip'; Expand-Archive -Path '%GODOT_DIR%\godot.zip' -DestinationPath '%GODOT_DIR%' -Force; Remove-Item '%GODOT_DIR%\godot.zip'"
if not exist "%GODOT_EXE%" (
  echo.
  echo HATA: Godot indirilemedi. Internet baglantini kontrol edip tekrar dene.
  pause
  exit /b 1
)
echo Kurulum tamam.

:ac
echo Proje editorde aciliyor (ilk acilista dokular 1-2 dakika yuklenir)...
start "" "%GODOT_EXE%" --path "%~dp0.." -e
endlocal
