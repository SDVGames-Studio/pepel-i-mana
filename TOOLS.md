> Инструменты этапа M0 (зафиксировано 2026-10-13)

| Инструмент | Путь | Версия |
|---|---|---|
| Godot | `F:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` | 4.7.2.stable.steam (ed1daf0bf) |
| Экспорт-шаблоны | `...\Godot Engine\editor_data\export_templates\4.7.2.stable\` | 4.7.2.stable |
| Git | `C:\Program Files\Git\cmd\git.exe` (установлен через winget) | см. `git --version` |

- Godot — Steam-версия в self-contained режиме (файл `._sc_`), данные редактора лежат рядом с exe.
- Запуск тестов: `godot --headless --path . --script res://tests/run_all.gd` (или `test.bat`).
- Сборка exe: `build.bat` → `build\ПепелИМана.exe`.
