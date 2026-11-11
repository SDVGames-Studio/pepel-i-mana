> Инструменты этапа M0 (зафиксировано 2026-10-13)

| Инструмент | Путь | Версия |
|---|---|---|
| Godot | каскад в bat-файлах: env `GODOT_EXE` → `F:\Z2\tools\godot.exe` → Steam `F:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` | 4.7.2.stable (обе копии) |
| Экспорт-шаблоны | `...\Godot Engine\editor_data\export_templates\4.7.2.stable\` | 4.7.2.stable |
| Git | `C:\Program Files\Git\cmd\git.exe` (установлен через winget) | см. `git --version` |

- Godot — вторая копия в `F:\Z2\tools\godot.exe`; Steam-версия в
  self-contained режиме (файл `._sc_`), данные редактора лежат рядом с exe.
- Запуск тестов: `godot --headless --path . --script res://tests/run_all.gd` (или `test.bat`).
- Сборка exe: `build.bat` → `build\ПепелИМана.exe`.

- Снимки сцен для визуальной проверки (запуск С ГРАФИКОЙ):
  `godot --path . --script res://tools/shot_city.gd` (город),
  `res://tools/shot_world2.gd` (карта мира), `res://tools/shot_dungeon.gd`
  (данж; `SHOT_BIOME=<id>` фиксирует биом) → tools/shot_*.png.
- Диагностика данжа v2 (FPS, споты жаровень/луж/рун):
  `SHOT_BIOME=<id> godot --path . --script res://tools/diag_dungeon2.gd`.
- Генераторы ассетов: `make_bestiary.py`, `make_buildings.py`,
  `make_creatures.gd` (нечисть), `make_dungeon2.py`, `make_nature2.py`,
  `make_props.py`, `make_video_grass.py`, `make_video_trees.py`,
  `make_wishlist_sprites.py`, `prepare_atlas.py`; спрайт-карты атласа —
  `spritemap.py`/`spritemap.png`, `tilepick.py`/`tilepick.png`.
  Перегенерация = запустить скрипт (детерминированы).
