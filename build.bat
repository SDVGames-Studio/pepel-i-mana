@echo off
chcp 65001 >nul
rem === Сборка «Пепел и Мана» → build\ПепелИМана.exe ===
setlocal
set "GODOT=F:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "PROJECT=%~dp0"

if not exist "%GODOT%" (
    echo ОШИБКА: Godot не найден: %GODOT%
    pause
    exit /b 1
)

echo [1/3] Импорт ресурсов...
"%GODOT%" --headless --path "%PROJECT%" --import
if errorlevel 1 goto fail

echo [2/3] Автотесты...
"%GODOT%" --headless --path "%PROJECT%" --script "res://tests/run_all.gd"
if errorlevel 1 goto fail

echo [3/3] Экспорт exe...
if not exist "%PROJECT%build" mkdir "%PROJECT%build"
"%GODOT%" --headless --path "%PROJECT%" --export-release "Windows Desktop" "build/ПепелИМана.exe"
if errorlevel 1 goto fail

if not exist "%PROJECT%build\ПепелИМана.exe" goto fail

echo.
echo СБОРКА УСПЕШНА: build\ПепелИМана.exe
pause
exit /b 0

:fail
echo.
echo ОШИБКА СБОРКИ (см. сообщения выше)
pause
exit /b 1
