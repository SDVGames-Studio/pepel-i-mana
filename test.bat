@echo off
chcp 65001 >nul
rem === Запуск автотестов headless ===
setlocal
set "GODOT=F:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "PROJECT=%~dp0"

"%GODOT%" --headless --path "%PROJECT%" --script "res://tests/run_all.gd"
if errorlevel 1 (
    echo ТЕСТЫ ПРОВАЛЕНЫ
    exit /b 1
)
echo ТЕСТЫ ПРОЙДЕНЫ
