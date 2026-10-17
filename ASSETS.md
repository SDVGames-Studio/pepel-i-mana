# АССЕТЫ ДЛЯ ПОЛИРОВКИ (M9) — инвентарь, составлен 2026-10-17

Разрешение заказчика: «можешь осмотреть папки с пиксель-артами и всяким таким,
можешь их использовать, даже сцены движения были». Что найдено и годно:

## 0. F:\kust\new-world-v-2 — ГЛАВНЫЙ СКЛАД (CraftPix-паки + готовые анимации!)
Старый Godot-проект заказчика, ~4000 файлов ассетов. Лицензия CraftPix
(license.txt в паках — ссылка на craftpix.net/file-licenses): свободные паки
разрешено использовать в своих играх (в т.ч. коммерческих), нельзя только
перепродавать сами ассеты отдельно. Разрешение заказчика на использование ЕСТЬ.

### Готовые АНИМАЦИИ персонажей («сцены движения» — это здесь!)
- `assets\human\` — ЧЕЛОВЕК-ГЕРОЙ: наборы Sword и Unarmed, полные анимации
  по 4 направлениям (front/back/side_left/side_right): **Idle, Walk,
  Walk_attack, Sword_Attack, Sword_Death** (+ Parts). Форматы: PNG
  (With_shadow / Without_shadow) + исходники Aseprite. Это готовый герой
  с idle/ходьбой/атакой/смертью — и образец стиля для жителей.
- `assets\ork goblin\` — Orc1/Orc2/Orc3, тот же состав анимаций
  (idle/walk/attack/death, 4 направления, PNG+Aseprite) — готовые враги.
- `assets\enimi\` — иконки монстров/нежити (Icon1..50, фоны/прозрачные).

### Тайлсеты и объекты
- `assets\dom\` — Tropical Medieval City 2D Tileset: **18 зданий** (PNG,
  building_1..N), decor, land, road (+ AI/EPS исходники) — город!
- `assets\plitka\` = craftpix Fields Tileset — поля/фермы (тайлы + отдельно).
- `assets\trava\` — кусты (времена года), `assets\derevo\` — деревья
  (Autumn_tree…, отдельно по видам).
- `assets\box eda\` — растения/еда.
- `assets\dang\` — данж-пак: пропсы, ловушки (fire_trap), объекты (гильотина,
  бомбы, пушки, колбы).
- `assets\podzemele\` — подземелье: ловушки и пропсы.

### CraftPix-паки по темам (каждый со своими PNG-наборами)
- `craftpix-net-654184-main-characters-home…` — дом героя top-down: экстерьер,
  интерьер, анимации птицы/кошки, детали травы.
- `craftpix-net-658475-free-archer-towers…` — **башни лучников со стадиями
  апгрейда и Idle-анимацией** (1 Upgrade/, 2 Idle/…) — наши вышки!
- `craftpix-net-805745-free-magic-and-traps…` — **шипы, баррикады, стрелы,
  магия top-down** — ловушки данжа и эффекты.
- `craftpix-net-934618-free-top-down-ruins…` — руины (Blue-gray/Brown-gray
  наборы) — биом руин и точки интереса.
- `craftpix-net-688754-free-minerals…` — иконки минералов/руд — ресурсы.
- `craftpix-net-986554-free-undead-loot…` — иконки лута нежити.
- `craftpix-net-789196-free-top-down-hunt-animals…` — дикие животные (тетерев,
  кабан…) с ПОЛНЫМИ анимациями Idle/Walk/Attack/Death/Flight/Hurt + тени.
- `craftpix-net-639143-free-rocky-area…` — скалы/камни.
- `craftpix-net-692491-free-glassblowers-workshop…` — мастерская top-down.
- `craftpix-net-665895-free-pixel-dungeon-props…` — пропсы данжа.
- `craftpix-net-814823-free-roguelike-shoot-em-up…` — набор roguelike.
- `craftpix-net-694865-free-top-down-seabed…` — морское дно (вода города).
- `assets\slavarium-main\` — референс-проект Godot (сцены characters/houses/
  objects/ui) — пример сборки, не копировать вслепую.

## 1. Kenney Tiny Dungeon 1.0 — дополнительный набор (CC0, без ограничений)
Путь: `F:\Z2\tools\kenney\` (архив рядом: kenney_tiny-dungeon.zip)
- **132 тайла 16×16** (сетка 12×11): `Tilemap\tilemap_packed.png` (атлас) и
  отдельные `Tiles\tile_0000.png … tile_0131.png`. Описание сетки — `Tilesheet.txt`.
- Подписанный атлас с именами: `atlas_labeled.png` (сделан скриптом make_atlas.ps1).
- Что внутри (см. Preview.png): полы/стены данжа (камень, булыжник, земля,
  песок), двери и решётки, сундуки, заборы/частокол, лавы-вкрапления;
  **персонажи** — рыцари/герои в шлемах, маги, скелеты, слаймы, крысы,
  призраки, демоны, пауки (по 1 кадру, 16×16); **предметы** — мечи, топоры,
  дубины, зелья, еда, амулеты, кристаллы.
- Лицензия: CC0 (License.txt) — вставляем как есть, упоминание Kenney
  добровольное (можно добавить в README релиза).
- Использование в игре: масштаб ×2 (16→32) под tile_size 32;Filter nearest
  уже включён проектом (default_texture_filter=0).
- Анимации idle/ходьба/атака: кадров в наборе НЕТ — делать дешёвыми
  приёмами Godot (бобинг по синусу, отражение по направлению, вспышка
  при атаке) или вторым кадром через Blender-конвейер (см. §2).

## 2. Свой пиксель-арт — готический воин 32×32
Путь: `F:\Z2\.zcode\workspace\default\pixel_art\`
- `knight_gothic_32x32.png` (спрайт героя) + `knight_gothic_preview.png`.
- Генератор: `make_knight.py` + `make_knight.bat` (Blender headless, пиксели
  из сетки символов → PNG через zlib). Тот же конвейер годится, чтобы
  дорисовать недостающие спрайты (жители, здания) одним стилем 32×32.

## 3. Blender-модели — для спрайтов зданий
Путь: `F:\Z2\3d_models\`
- `church_and_tower\church.blend` + `tower.blend` (и STL: «улучшеная церковь»,
  «доработать домик»). Можно отрендерить в изометрические спрайты зданий
  города (Blender headless, ортокамера) или использовать как референсы.

## 4. Ассеты проекта «Подземье» (переиспользуемо)
Путь: `F:\Z2\podzemie\assets\`
- `fonts\PressStart2P-Regular.ttf` — пиксельный шрифт (готов к вставке в HUD).
- `actors\hero.png` (16×16, из того же Kenney), `props\brazier_base.png`,
  `props\stairs_down.png`, `tiles\tilemap_packed.png` (дубль Kenney).
- Сцены движения персонажа (пример управления/анимации): `podzemie\scenes\player.tscn`
  и его скрипт — референс, не копировать вслепую.

## Что брать в M9 (приоритет, обновлено 2026-10-17)
1. **Герой** — `assets\human\` (Sword): готовые Idle/Walk/Attack/Death по 4
   направлениям — сразу SpriteFrames в Godot.
2. **Враги данжа** — `assets\ork goblin\` (орки 3 видов с анимациями) +
   персонажи Kenney (слаймы/скелеты/призраки) + иконки `enimi\` и лут нежити.
3. **Город** — здания из `assets\dom\` (18 шт), вышки из archer-towers
   (стадии апгрейда!), поля `plitka\`, деревья `derevo\`, кусты `trava\`.
4. **Животные охоты** — hunt-animals (Idle/Walk/Attack/Death + тени).
5. **Данж** — тайлы Kenney (4 биома с подкраской), пропсы/ловушки `dang\`,
   `podzemele\`, magic-and-traps (шипы/баррикады), руины 934618.
6. **Иконки HUD/ресурсов** — minerals, undead-loot, предметы Kenney.
7. Недостающее (жители-профессии) — раскраска человечка из human\ или
   Blender-конвейер 32×32 (make_knight.py).
8. Шрифт PressStart2P (podzemie) — БЕЗ кириллицы, для русского НЕ годится —
   оставить системный шрифт.
