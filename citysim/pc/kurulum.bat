@echo off
rem Sehir Sim - bilgisayar kurulumu (bir kez calistir).
rem Godot 4.7.2'yi (CI ile ayni surum) bu klasore indirir ve projeyi editorde acar.
rem Indirme iki sunucudan denenir, yarim kalirsa kaldigi yerden surer.
rem Godot zip'ini elle indirip pc\godot klasorune birakirsan onu kullanir.
setlocal
cd /d "%~dp0"
set "GODOT_DIR=%~dp0godot"
set "GODOT_EXE=%GODOT_DIR%\Godot_v4.7.2-stable_win64.exe"
set "PART=%GODOT_DIR%\godot_indirme.part"
set "ZIP=%GODOT_DIR%\godot.zip"
set "URL1=https://downloads.godotengine.org/?version=4.7.2&flavor=stable&slug=win64.exe.zip&platform=windows.64"
set "URL2=https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip"

echo "%~dp0" | find /i "OneDrive" >nul
if not errorlevel 1 echo UYARI: Proje OneDrive icinde. Sorun cikarsa projeyi OneDrive disina (or. C:\Projeler) klonla.

if exist "%GODOT_EXE%" goto ac
if not exist "%GODOT_DIR%" mkdir "%GODOT_DIR%"

rem Elle indirilip buraya birakilmis bir zip varsa onu kullan.
for %%Z in ("%GODOT_DIR%\*.zip") do set "ZIP=%%~fZ"
if exist "%ZIP%" goto cikar

echo Godot 4.7.2 indiriliyor (yaklasik 86 MB). Yavas baglantida birkac dakika surebilir...
call :indir "%URL1%"
if exist "%ZIP%" goto cikar
echo.
echo Birinci sunucudan inmedi, ikinci sunucu (GitHub) deneniyor...
if exist "%PART%" del "%PART%" >nul 2>&1
call :indir "%URL2%"
if exist "%ZIP%" goto cikar
goto elle

:cikar
echo Zip aciliyor...
tar -xf "%ZIP%" -C "%GODOT_DIR%" >nul 2>&1
if not exist "%GODOT_EXE%" powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Expand-Archive -LiteralPath '%ZIP%' -DestinationPath '%GODOT_DIR%' -Force -ErrorAction Stop } catch { exit 1 }" >nul 2>&1
if exist "%GODOT_EXE%" goto cikar_tamam
echo.
echo Zip acilamadi (dosya yarim inmis ya da yanlis surum olabilir). Siliniyor.
del "%ZIP%" >nul 2>&1
goto elle

:cikar_tamam
del "%ZIP%" >nul 2>&1
echo Kurulum tamam.
goto ac

:indir
where curl.exe >nul 2>&1
if errorlevel 1 goto indir_ps
curl.exe -L --fail --retry 5 --retry-delay 3 --connect-timeout 30 -C - -o "%PART%" "%~1"
if errorlevel 1 exit /b 1
move /y "%PART%" "%ZIP%" >nul
exit /b 0

:indir_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest -Uri '%~1' -OutFile '%PART%' -ErrorAction Stop } catch { exit 1 }"
if errorlevel 1 exit /b 1
move /y "%PART%" "%ZIP%" >nul
exit /b 0

:elle
echo.
echo ============================================================
echo  Godot otomatik indirilemedi (baglanti zaman asimi olabilir).
echo  Elle yapmak icin:
echo   1. Acilan tarayici sayfasindan zip dosyasi inecek (86 MB).
echo      Inmezse: godotengine.org - Download - 4.7.2 - Windows 64 bit
echo   2. Inen zip dosyasini, acilan "godot" klasorune tasi.
echo   3. Bu dosyaya (kurulum.bat) tekrar cift tikla.
echo ============================================================
start "" "%URL1%"
explorer "%GODOT_DIR%"
pause
exit /b 1

:ac
echo Proje editorde aciliyor (ilk acilista dokular 1-2 dakika yuklenir)...
start "" "%GODOT_EXE%" --path "%~dp0.." -e
endlocal
