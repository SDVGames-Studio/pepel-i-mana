# -*- coding: utf-8 -*-
## v2.0 «Проводка задела» патч: item_tex для лута, пул деревьев B,
## текстурные пни/брёвна с фолбэком, варианты мельницы B/C, кадры фауны B.
import io, json, sys

ROOT = r"F:\Z2\.zcode\workspace\default\pepel-i-mana"

# --- assets.gd: иконка предмета из нарезанного лута ---
pa = ROOT + r"\scripts\assets.gd"
a = io.open(pa, encoding="utf-8").read()
if "item_tex" not in a:
    anchor = "static func sprite(ref: String) -> Texture2D:"
    assert anchor in a, "assets: sprite anchor missing"
    add = '''## Иконка предмета из нарезанного лута (v2.0 ЛУТ-1): mapping в
## wave1123/loot_items/manifest.json ("item" -> файл). Нет mapping — null.
const LOOT_MANIFEST_PATH := "res://assets/sprites/wave1123/loot_items/manifest.json"
static var _loot_map: Dictionary = {}
static var _loot_map_ready := false


static func item_tex(item_id: String) -> Texture2D:
	if not _loot_map_ready:
		_loot_map_ready = true
		var f: FileAccess = FileAccess.open(LOOT_MANIFEST_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				for e in ((parsed as Dictionary).get("items", []) as Array):
					if e is Dictionary and String(e.get("item", "")) != "":
						_loot_map[String(e["item"])] = \\
								"res://assets/sprites/wave1123/loot_items/" + String(e["file"])
	var path: String = _loot_map.get(item_id, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	return tex(path)


'''
    a = a.replace(anchor, add + anchor, 1)
    io.open(pa, "w", encoding="utf-8", newline="\n").write(a)
    print("assets: item_tex")

# --- pickup.gd: лут-иконка предпочтительнее Kenney ---
pp = ROOT + r"\scripts\pickup.gd"
p = io.open(pp, encoding="utf-8").read()
if "item_tex" not in p:
    a2 = '''	if sprite_ref != "":
		var tex: Texture2D = Assets.sprite(sprite_ref)
		if tex != null:'''
    assert a2 in p, "pickup: sprite anchor missing"
    r2 = '''	# v2.0 ЛУТ-1: у нарезанных предметов своя иконка, Kenney — запасной путь
	var tex: Texture2D = Assets.item_tex(item_id)
	if tex == null and sprite_ref != "":
		tex = Assets.sprite(sprite_ref)
	if tex != null:'''
    p = p.replace(a2, r2, 1)
    io.open(pp, "w", encoding="utf-8", newline="\n").write(p)
    print("pickup: loot icon")

# --- city_view_base: пул деревьев B ---
pv = ROOT + r"\scripts\city_view_base.gd"
v = io.open(pv, encoding="utf-8").read()
if "WAVE24_TREES" not in v:
    a3 = '''const WAVE23_TREES := ["e:tree2_spruce", "e:tree2_birch2", "e:tree2_oak_old",
		"e:tree2_snag"]'''
    assert a3 in v, "view_base: wave23 trees anchor missing"
    r3 = a3 + '''

## v2.0: пакет деревьев B (wave1123/trees_logs_b, 16 стволов: ель/берёза/
## дуб/сухостой/ива/цвет/клён/сакура + снежные и осенние варианты)
const WAVE24_TREES := ["e:tree3_spruce", "e:tree3_birch", "e:tree3_oak",
		"e:tree3_snag", "e:tree3_willow", "e:tree3_apple_bloom",
		"e:tree3_maple_orange", "e:tree3_dead", "e:tree3_spruce_snow",
		"e:tree3_birch_autumn", "e:tree3_oak_dark", "e:tree3_snag_knotty",
		"e:tree3_willow_autumn", "e:tree3_sakura", "e:tree3_maple_red",
		"e:tree3_dead_snow"]'''
    v = v.replace(a3, r3, 1)
    b1 = "			return SUMMER_TREE_REFS + WAVE23_TREES\n"
    b2 = "	return TREE_REFS + WAVE23_TREES\n"
    assert b1 in v and b2 in v, "view_base: pools anchors missing"
    v = v.replace(b1, "			return SUMMER_TREE_REFS + WAVE23_TREES + WAVE24_TREES\n", 1)
    v = v.replace(b2, "	return TREE_REFS + WAVE23_TREES + WAVE24_TREES\n", 1)
    io.open(pv, "w", encoding="utf-8", newline="\n").write(v)
    print("view_base: tree pool B")

# --- city_view_nature: текстурные пни и брёвна (процедура — запасной путь) ---
pn = ROOT + r"\scripts\city_view_nature.gd"
n = io.open(pn, encoding="utf-8").read()
if "stump3_" not in n:
    a4 = '''func _draw_stump(bottom: Vector2, ts: float, variant: int) -> void:
	var pal: Dictionary = STUMP_PALS[variant % STUMP_PALS.size()]'''
    assert a4 in n, "nature: stump anchor missing"
    r4 = '''func _draw_stump(bottom: Vector2, ts: float, variant: int) -> void:
	# v2.0: пакет пней B (8 текстур) — процедура остаётся запасным путём
	var sref := "e:stump3_%d" % (variant % 8 + 1)
	if Assets.sprite(sref) != null:
		_draw_shadow(bottom, ts * 0.3)
		Assets.draw_ref(self, sref, bottom + Vector2(0, -2.0), ts * 0.62)
		return
	var pal: Dictionary = STUMP_PALS[variant % STUMP_PALS.size()]'''
    n = n.replace(a4, r4, 1)
    a5 = '''	var size: int = int((map.logs[tile] as Dictionary).get("size", 1))
	var w := ts * 0.55 + ts * 0.18 * float(size)
	var col := Color("#8d6e63") if size < 3 else Color("#6d4c33")'''
    assert a5 in n, "nature: log anchor missing"
    r5 = '''	var size: int = int((map.logs[tile] as Dictionary).get("size", 1))
	# v2.0: пакет брёвен B (8 текстур) — по хэшу тайла, процедура в запасе
	var lref := "e:log3_%d" % (absi(tile.x * 31 + tile.y * 17) % 8 + 1)
	if Assets.sprite(lref) != null:
		var lc: Vector2 = map.tile_center_px(tile) + Vector2(0, ts * 0.2)
		lc.y -= _static_lift(tile)
		_draw_shadow(lc + Vector2(0, 5), ts * 0.42)
		Assets.draw_ref(self, lref, lc, ts * (0.5 + 0.08 * float(size)))
		return
	var w := ts * 0.55 + ts * 0.18 * float(size)
	var col := Color("#8d6e63") if size < 3 else Color("#6d4c33")'''
    n = n.replace(a5, r5, 1)
    io.open(pn, "w", encoding="utf-8", newline="\n").write(n)
    print("view_nature: stump/log textures B")

# --- city_view.gd: мельница B/C — вариант по хэшу здания (как статуя) ---
pw = ROOT + r"\scripts\city_view.gd"
w = io.open(pw, encoding="utf-8").read()
if "MILL_REFS" not in w:
    a6 = '''	if type_id == "grace_altar":'''
    assert a6 in w, "view: grace anchor missing"
    r6 = '''	if type_id == "mill":
		# v2.0: мельница A/B/C — вариант по хэшу id здания (пакет 2026-11)
		return MILL_REFS[_hash(int(b["id"]), 11, MILL_REFS.size())]
	if type_id == "grace_altar":'''
    w = w.replace(a6, r6, 1)
    a7 = 'const GRACE_ALTAR_REFS := ['
    assert a7 in w, "view: refs anchor missing"
    w = w.replace(a7, '''const MILL_REFS := [
	"b:мельница", "img:env/mill_b", "img:env/mill_c",
]


''' + a7, 1)
    io.open(pw, "w", encoding="utf-8", newline="\n").write(w)
    print("view: mill A/B/C")

# --- fauna.json: варианты B в пулы кадров ---
pf = ROOT + r"\data\fauna.json"
f = json.load(io.open(pf, encoding="utf-8"))
bmap = {"wolf": "an_wolf_b", "fox": "an_fox_b", "hare": "an_hare_b",
        "bird": "an_bird_b", "fish": "an_fish_b", "toad": "an_toad_b"}
changed = 0
for s in f.get("species", []):
    sid = str(s.get("id", ""))
    if sid not in bmap:
        continue
    art = s.get("art", {})
    frames = art.get("frames", [])
    base = bmap[sid]
    new = ["e:%s_%d" % (base, i + 1) for i in range(6)]
    add = [r for r in new if r not in frames]
    if add:
        art["frames"] = frames + add
        s["art"] = art
        changed += 1
if changed:
    json.dump(f, io.open(pf, "w", encoding="utf-8", newline="\n"),
              ensure_ascii=False, indent="\t")
    print("fauna.json: +%d species got B frames" % changed)
else:
    print("fauna.json: already wired")

