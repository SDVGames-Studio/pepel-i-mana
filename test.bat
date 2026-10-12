@echo off
chcp 65001 >nul
rem === Запуск автотестов headless ===
setlocal
set "GODOT=F:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "PROJECT=%~dp0"
if "%PROJECT:~-1%"=="\" set "PROJECT=%PROJECT:~0,-1%"

"%GODOT%" --headless --path "%PROJECT%" --script "res://tests/run_all.gd"
if errorlevel 1 (
    echo.
    echo ТЕСТЫ ПРОВАЛЕНЫ
    pause
    exit /b 1
)
echo.
echo ТЕСТЫ ПРОЙДЕНЫ
