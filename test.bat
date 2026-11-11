@echo off
chcp 65001 >nul
rem === Запуск автотестов headless ===
setlocal
rem Путь к Godot: env GODOT_EXE -> F:\Z2\tools\godot.exe -> Steam-версия
set "GODOT=%GODOT_EXE%"
if not defined GODOT set "GODOT=F:\Z2\tools\godot.exe"
if not exist "%GODOT%" set "GODOT=F:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "PROJECT=%~dp0"
if "%PROJECT:~-1%"=="\" set "PROJECT=%PROJECT:~0,-1%"

if not exist "%GODOT%" (
    echo ОШИБКА: Godot не найден: задай GODOT_EXE или положи godot.exe в F:\Z2\tools
    pause
    exit /b 1
)

"%GODOT%" --headless --path "%PROJECT%" --script "res://tests/run_all.gd"
if errorlevel 1 (
    echo.
    echo ТЕСТЫ ПРОВАЛЕНЫ
    pause
    exit /b 1
)
echo.
echo ТЕСТЫ ПРОЙДЕНЫ
