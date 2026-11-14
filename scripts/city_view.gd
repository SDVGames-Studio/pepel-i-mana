# Часть: отрисовка города — здания с подписями и дверями, рейдеры, жители
# со спич-баблами, герой, призраки стройки/переноса, превью зон.
# Корень цепочки: city.gd создаёт отрисовку через этот файл.
extends "res://scripts/city_view_props.gd"

func _draw_building(b: Dictionary) -> void:
	var ts := float(map.ts)
	var bw: int = sim.bld_w(b)
	var rect := Rect2(Vector2(b["tile"]) * ts, Vector2(ts * float(bw), ts * float(bw)))
	# v1.36.1: здание на плато приподнято вместе с плоскостью плато —
	# вся коробка (заливка, дверь, метки, надпись) на высоте уровня
	rect.position.y -= _bld_lift(b)
	# v1.52 (FPS): здание за экраном не рисуем (двери/метки/подписи —
	# десятки команд на дом; при карте ×4 их сотни)
	if not _vis.grow(float(ts) * 2.0).intersects(rect):
		return
	var type_id := String(b["type"])
	var col: Color = _bld_fill.get(type_id, Color(0.91, 0.85, 0.62))
	var anchor: Vector2 = Vector2(rect.get_center().x, rect.end.y - 2.0)
	if not b["done"]:
		# стройплощадка: призрачная заливка, каркас и полоса прогресса
		draw_rect(rect.grow(-3), Color(col.r, col.g, col.b, 0.22))
		draw_rect(rect.grow(-3), col.darkened(0.2), false, 2.0)
		var work: float = _build_work(type_id)
		var frac := clampf(float(b["progress"]) / work, 0.0, 1.0) if work > 0.0 else 0.0
		draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 9),
				Vector2((rect.size.x - 8) * frac, 5)), Color("#ffe082"))
		_draw_bld_label(b, rect)
	elif bool(b.get("razed", false)):
		# руины (этап 2, аспект 5): тёмные обломки цвета категории, трещины
		# и метка «разрушено» — чинится героем за 40% стоимости (E)
		var ruin := col.darkened(0.62)
		draw_rect(rect, ruin)
		draw_rect(rect.grow(-2), col.darkened(0.78), false, 2.0)
		draw_line(rect.position + Vector2(ts * 0.25, ts * 0.2),
				rect.position + Vector2(ts * 0.45, ts * 0.55), Color(0.05, 0.04, 0.03), 2.0)
		draw_line(rect.position + Vector2(ts * 0.7, ts * 0.15),
				rect.position + Vector2(ts * 0.5, ts * 0.6), Color(0.05, 0.04, 0.03), 2.0)
		_draw_bld_label(b, rect)
		var font := ThemeDB.fallback_font
		var tag := Loc.t("city.razed_tag")
		var tag_pos := rect.position + Vector2(
				(rect.size.x - font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x) * 0.5, -3.0)
		draw_string_outline(font, tag_pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3,
				Color(0.2, 0.03, 0.03, 0.9))
		draw_string(font, tag_pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(1.0, 0.45, 0.4, 0.95))
	else:
		# v1.49: здание рисуется ТЕКСТУРОЙ (раскладка ассетов заказчика готова:
		# Celianna-дома + craftpix «дом жителей/склад»); стены/ворота остаются
		# схематичными сегментами (тайлятся), у прочих спрайт заменяет коробку
		var ref := _bld_sprite_ref(type_id, b)
		var tex: Texture2D = Assets.sprite(ref) if ref != "" else null
		var drew_tex := false
		if tex != null and not type_id in ["wall", "gate"]:
			var dw: float = rect.size.x * 1.5
			var dh: float = dw * float(tex.get_height()) / float(tex.get_width())
			# якорь — низ-footprint (по нему идёт Y-сортировка), спрайт над ним
			Assets.draw_ref(self, ref, anchor - Vector2(0, dh * 0.5), dh)
			drew_tex = true
		if not drew_tex:
			# схематичное здание: заливка категории, тёмная кайма по контуру
			draw_rect(rect, col)
			draw_rect(rect.grow(-2), col.darkened(0.3), false, 2.0)
			_draw_bld_door(b, rect)
		if type_id == "tent":
			_draw_tent_awning(rect)   # полосатый навес — торговая читаемость (этап 2)
		# точка-работник: занятое здание подсвечено
		if int(b["worker"]) > 0:
			draw_circle(rect.position + Vector2(rect.size.x - 6.0, 6.0), 2.5, Color(1, 1, 1, 0.95))
		# яблоневый сад (M10): растёт — полоска стадии, зелёная при спелости
		if type_id == "orchard":
			var stages := float(sim.cfg.get("orchard", {}).get("stages", 3))
			var stage := clampf(float(b.get("apple_stage", 0)) / maxf(1.0, stages), 0.0, 1.0)
			draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 8),
					Vector2((rect.size.x - 8) * stage, 4)),
					Color("#8bc34a") if stage >= 1.0 else Color("#ffe082"))
		_draw_bld_label(b, rect)
	# окно: кто-то спит/лежит внутри — тёплый свет у входа (ночью особенно видно)
	if sim._active(b) and _inside_homes.has(int(b["id"])):
		var door: Vector2 = _bld_door_pos(b, rect)
		var glow := 0.5 + 0.2 * sin(Time.get_ticks_msec() / 350.0)
		draw_circle(door + Vector2(0, -ts * 0.2), ts * 0.28, Color(1.0, 0.85, 0.45, 0.55 + 0.25 * glow))
		draw_circle(door + Vector2(0, -ts * 0.2), ts * 0.12, Color(1.0, 0.93, 0.7, 0.9))
	# кладбище темнеет (M11): тьма ползёт с кладбища, пока некромант работает
	if String(b["type"]) == "cemetery" and bool(b["done"]):
		_draw_graves(anchor - Vector2(0, 0))
		var dark := clampf(float(sim.necro_dark), 0.0, 1.0)
		if dark > 0.02:
			var rings := 4
			for i in rings:
				var rr: float = ts * (0.8 + dark * 2.2) * (float(i + 1) / float(rings))
				draw_circle(anchor - Vector2(0, 4), rr,
						Color(0.08, 0.05, 0.14, 0.05 + 0.1 * dark))
			if sim.necro_known:
				var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 500.0)
				draw_arc(anchor - Vector2(0, 4), ts * (0.9 + dark * 2.0),
						0.0, TAU, 24, Color(0.5, 0.3, 0.7, 0.12 + 0.1 * pulse), 2.0)
		# ночные призывы (M11): скелеты видны у кладбища только ночью
		if sim.is_night() and int(sim.necro_army) > 0:
			var shown: int = mini(3, sim.necro_ghosts.size())
			for g in shown:
				var gpx: Vector2 = sim.necro_ghosts[g]
				var bob := absf(sin(Time.get_ticks_msec() / 320.0 + float(g) * 2.1)) * 2.0
				Assets.draw_ref(self, "k:121", gpx + Vector2(0, -bob),
						ts * 1.1, false, Color(0.75, 0.7, 0.9))
	# зачарование: рамка цветом эффекта (M3)
	if String(b.get("enchant", "")) != "":
		var ecol: Color = enchant_colors.get(String(b["enchant"]), Color(0.8, 0.8, 1.0))
		draw_rect(rect.grow(-1), ecol, false, 2.0)
		draw_circle(rect.position + Vector2(5, 5), 3.0, ecol)
	# дикая вспышка: здание оглушено
	if float(b.get("stun_left", 0.0)) > 0.0:
		draw_rect(rect, Color(0.1, 0.05, 0.15, 0.55))
		var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
		draw_arc(rect.get_center(), ts * 0.4, 0.0, TAU, 20,
				Color(0.9, 0.4, 1.0, 0.4 + 0.4 * flash), 2.0)
	# прочность (M5): повреждённое здание показывает полоску (руины — без неё)
	if sim._active(b) and float(b.get("hp", 999.0)) < float(_bld_max_hp(String(b["type"]))):
		var frac2 := clampf(float(b["hp"]) / float(_bld_max_hp(String(b["type"]))), 0.0, 1.0)
		draw_rect(Rect2(rect.position + Vector2(4, -7), Vector2(ts - 8, 4)), Color(0.15, 0.1, 0.1))
		draw_rect(Rect2(rect.position + Vector2(4, -7), Vector2((ts - 8) * frac2, 4)), Color("#8bc34a"))


## Подпись схематичного здания (этап 2, аспект 1): краткое название
## поверх заливки, обводка для читаемости на любом цвете. Стена —
## сплошное кольцо, её тайлы подписями не метятся (шум); ворота подписаны.
const BLD_NO_LABEL := {"wall": true}


## Полосатый навес палатки (этап 2, аспект 4): жёлто-светлые полосы
## поверх заливки категории — «торговое место» читается с одного взгляда.
func _draw_tent_awning(rect: Rect2) -> void:
	var stripe := rect.size.y * 0.28
	var h := rect.size.y * 0.16
	for i in 2:
		var col := Color("#ffd54f") if i % 2 == 0 else Color("#fff3c4")
		draw_rect(Rect2(rect.position.x + 2.0, rect.position.y + stripe * float(i),
				rect.size.x - 4.0, h), col)


## Ссылка на спрайт здания из конфига (кэш по типу). Дома жителей — три
## варианта craftpix (ур1..3) по номеру дома, чтобы застройка не была клоном.
var _bld_ref_cache: Dictionary = {}

func _bld_sprite_ref(type_id: String, b: Dictionary) -> String:
	if type_id == "house":
		# v1.68: уровень дома растёт с городом (ассеты заказчика L1-3):
		# деревня до 12 жителей — L1, посёлок до 24 — L2, город — L3
		var pop: int = sim.residents.size()
		var tier := 3 if pop >= 24 else (2 if pop >= 12 else 1)
		return "b:дом_жителей_ур%d" % tier
	if type_id == "statue":
		# v1.63: статуя — вариации из пака (по хэшу id здания)
		return STATUE_REFS[_hash(int(b["id"]), 7, STATUE_REFS.size())]
	if _bld_ref_cache.has(type_id):
		return _bld_ref_cache[type_id]
	var ref := ""
	for d in sim.cfg.get("buildings", []):
		if String(d.get("id", "")) == type_id:
			ref = String(d.get("sprite", ""))
			break
	_bld_ref_cache[type_id] = ref
	return ref


func _draw_bld_label(b: Dictionary, rect: Rect2) -> void:
	var type_id := String(b["type"])
	if bool(BLD_NO_LABEL.get(type_id, false)):
		return
	var key: String = _bld_short.get(type_id, "")
	if key == "":
		return
	# v1.21.4: текст и ширина кэшируются по типу — замер шрифта на каждое
	# здание каждый кадр стоил дороже всей остальной отрисовки подписи
	if not _label_cache.has(type_id):
		var text := Loc.t(key)
		if text == key:
			# краткой подписи нет — падаем на полное название, затем на id
			var full_key: String = _bld_loc.get(type_id, "")
			var full := Loc.t(full_key) if full_key != "" else ""
			text = full if full != full_key and full != "" else type_id
		var font := ThemeDB.fallback_font
		_label_cache[type_id] = [text, font.get_string_size(text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x]
	var cached: Array = _label_cache[type_id]
	var pos := rect.get_center() - Vector2(float(cached[1]) * 0.5, -3.0)
	draw_string_outline(ThemeDB.fallback_font, pos, cached[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color(0.12, 0.09, 0.05, 0.9))
	draw_string(ThemeDB.fallback_font, pos, cached[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 0.96, 0.97))


## Дверной проём (этап 2, аспект 2): тёмная метка на кайме со стороны входа.
func _draw_bld_door(b: Dictionary, rect: Rect2) -> void:
	var door := _bld_door_pos(b, rect)
	var w := rect.size.x * 0.16
	var h := rect.size.y * 0.12
	var horizontal: bool = absf(door.x - rect.get_center().x) > rect.size.x * 0.25
	var r := Rect2(door - Vector2(w if horizontal else h * 0.5, h if horizontal else w * 0.5),
			Vector2(h if horizontal else w, w if horizontal else h))
	draw_rect(r, Color(0.18, 0.13, 0.09, 0.85))


## Точка входа: середина общего ребра между входной клеткой и прямоугольником.
func _bld_door_pos(b: Dictionary, rect: Rect2) -> Vector2:
	var ts := float(map.ts)
	var e: Vector2i = sim.bld_entrance(b)
	if e == Vector2i(-1, -1):
		return Vector2(rect.get_center().x, rect.end.y)
	var t := Vector2i(b["tile"])
	var bw: int = sim.bld_w(b)
	var cx := clampi(e.x, t.x, t.x + bw - 1)
	var cy := clampi(e.y, t.y, t.y + bw - 1)
	var cell_center := Vector2(t) * ts + (Vector2(cx, cy) + Vector2(0.5, 0.5)) * ts
	var e_center := Vector2(e) * ts + Vector2(ts, ts) * 0.5
	return (cell_center + e_center) * 0.5


## Дома с обитателями внутри (спят/лежат/прячутся): id здания → true.
## Собирается один раз за кадр в _draw_world_sorted.


## Атакующие (M5 мутанты; M11 духи леса, Древень, скелеты некроманта).
func _draw_raider(r: Dictionary) -> void:
	var refs := {"mutant": "e:mutant", "brute": "e:brute", "spitter": "e:spitter",
			"forest_spirit": "e:spirit", "forest_boss": "e:treant", "skeleton": "k:121"}
	var pos: Vector2 = r["pos"]
	var rad := float(r["p"]["radius"])
	var kind := String(r["type"])
	var ref: String = refs.get(kind, "e:mutant")
	var size := rad * 2.8
	var lift := 0.0
	var hl := _entity_lift("raid%d" % int(r["id"]), pos)   # v1.36.1: высота плато
	var tint := Color.WHITE
	if kind == "forest_spirit" or kind == "forest_boss":
		# духи парят: синус повыше и медленнее, свечение бирюзой
		lift = 4.0 + 2.5 * sin(Time.get_ticks_msec() / 260.0 + float(r["id"]))
		tint = Color(0.8, 1.05, 1.0) if kind == "forest_spirit" else Color(0.9, 1.1, 0.85)
	var phase := pos.x * 0.9 + Time.get_ticks_msec() / 100.0
	var vx := 0.0
	var pth: PackedVector2Array = r.get("path", PackedVector2Array())
	if not pth.is_empty():
		vx = (pth[0] - pos).x
	Assets.draw_ref(self, ref, pos + Vector2(0, -absf(sin(phase)) * 1.5 - lift - hl), size, vx < -1.0, tint)
	if int(r["hp"]) < int(r["max_hp"]):
		var frac := clampf(float(r["hp"]) / float(r["max_hp"]), 0.0, 1.0)
		draw_rect(Rect2(pos + Vector2(-12, -rad - 8 - hl), Vector2(24, 4)), Color(0.15, 0.1, 0.1))
		draw_rect(Rect2(pos + Vector2(-12, -rad - 8 - hl), Vector2(24.0 * frac, 4)), Color(0.9, 0.25, 0.25))
	# осадный мутант и босс леса выделены — видно, кто главный
	# (кольцо — метка тайла, остаётся на «земле» без лифта)
	if kind == "brute" or kind == "forest_boss":
		var ring := Color(0.9, 0.3, 0.2, 0.6) if kind == "brute" else Color(0.5, 0.9, 0.4, 0.7)
		draw_arc(pos, rad + 3.0, 0.0, TAU, 20, ring, 2.0)


func _bld_max_hp(type_id: String) -> float:
	if _hp_max_cache.has(type_id):
		return float(_hp_max_cache[type_id])
	var hp_cfg: Dictionary = sim.cfg.get("threat", {}).get("bld_hp", {})
	var hp := float(hp_cfg.get("default", 20))
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			hp = float(hp_cfg.get(String(d.get("effect", "default")), hp))
			break
	_hp_max_cache[type_id] = hp
	return hp


## Кэш кружков жителей (v1.21.5): тело жителя — тень+кайма+заливка+центр —
## рисовалось пятью командами на каждого; теперь печётся в маленькую
## текстуру по цвету и размеру и рисуется одной командой.
var _res_sprites: Dictionary = {}


func _res_sprite(col: Color, radius: float) -> ImageTexture:
	var key := "%s|%.0f" % [col.to_html(false), radius]
	if _res_sprites.has(key):
		return _res_sprites[key]
	var size := int(ceil(radius * 2.0)) + 6
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size / 2.0, size / 2.0)
	var shadow_c := c + Vector2(0.0, 2.5)
	var border := col.darkened(0.55)
	var dot := col.darkened(0.5)
	for py in size:
		for px in size:
			var p := Vector2(px + 0.5, py + 0.5)
			var px_col := Color(0, 0, 0, 0)
			if p.distance_to(shadow_c) <= radius:
				px_col = Color(0, 0, 0, 0.25)
			var d := p.distance_to(c)
			if d <= radius:
				px_col = border
			if d <= radius - 1.5:
				px_col = col
			if d <= radius * 0.42:
				px_col = dot
			img.set_pixel(px, py, px_col)
	var tex := ImageTexture.create_from_image(img)
	_res_sprites[key] = tex
	return tex


## Житель (M12: per-object для общего сортированного слоя). Айдл без «марша на
## месте»: движение читается из состояния и пути — раньше флаг moving,
## выставленный в дороге, не сбрасывался у стоящих, и они «маршировали».
## Житель — кружок (правки v1.20): убрали графику, цвет кружка = основная
## специальность; голем-староста — белый; дети — маленькие серо-бежевые.
func _draw_resident(r: Dictionary) -> void:
	# тайный некромант на кладбище (v1.24): ночная тьма прячет его —
	# пока герой не подойдёт на hidden_radius (4) клеток, его не видно
	if city != null and city.hero != null \
			and sim.necro_hidden_from(r, city.hero.global_position):
		return
	var pos: Vector2 = r["pos"]
	var prof := String(r["prof"])
	var child := prof == ""
	var col: Color = sim.resident_color(r)
	var sleeping: bool = r["state"] == "sleep" or r["state"] == "rest"
	# лёгкое покачивание при движении — кружок «живой»
	var pth: PackedVector2Array = r.get("path", PackedVector2Array())
	var moving: bool = not sleeping and not pth.is_empty() \
			and pos.distance_to(pth[pth.size() - 1]) > 2.0
	var phase := float(r["id"]) * 1.7 + _anim_time * (7.0 if moving else 1.5)
	var bob := absf(sin(phase)) * (1.6 if moving else 0.4)
	var radius := 7.0 if child else 9.0
	# v1.36.1: стоя на плато, житель выше равнины (подъём анимируется
	# на лестнице) — высота ощущается, а не плоская текстура
	var lift := _entity_lift("res%d" % int(r["id"]), pos)
	var ail := String(r.get("ail", ""))
	if ail == "sick":
		col = col.lerp(Color(0.7, 0.95, 0.6), 0.5)
	elif ail == "wounded":
		col = col.lerp(Color(1.0, 0.45, 0.45), 0.5)
	if sleeping:
		col = col.darkened(0.4)
	var center := pos + Vector2(0, -3.0 - bob - lift)
	# v1.64: кружки-фолбэки (дети/стражи/старосты рас) тоже несут палитру расы
	if String(r.get("race", "human")) != "human":
		var rc := Color(String(sim._race_def(r).get("tint", "#ffffff")))
		col = col.lerp(rc, 0.3)
		radius *= float(sim._race_def(r).get("scale", 1.0))
	# v1.49.1: взрослые с профессией из пака Minifolks рисуются спрайтом
	# (idle/ходьба/работа); якорь — НОГИ на позиции жителя (y-сортировка),
	# видимый рост ~23px против 32 у рыцаря. Дети, стражи, староста и
	# профессии без листа — прежний кружок; оттенок цвета профессии не
	# применяем (портит арт), кроме болезней/ран
	var working_states := ["work", "build", "harvest", "fill", "hunt", "chop", "mine", "farm"]
	# v1.64 (п.3, ответ №108 «силуэт + палитра»): раса жителя — палитра
	# поверх спрайта профессии и рост (дворф/гном/гоблин ниже); болезнь/рана
	# перекрашивают сильнее; ангелу — тонкий нимб
	var race_def: Dictionary = sim._race_def(r)
	var race_tint := Color.WHITE
	if not race_def.is_empty():
		race_tint = Color.WHITE.lerp(Color(String(race_def.get("tint", "#ffffff"))), 0.55)
	var race_scale := float(race_def.get("scale", 1.0))
	if ail == "sick":
		race_tint = race_tint.lerp(Color(0.7, 0.95, 0.6), 0.5)
	elif ail == "wounded":
		race_tint = race_tint.lerp(Color(1.0, 0.45, 0.45), 0.5)
	var drawn_villager := false
	if not child and not sleeping and not _is_elder_golem(r):
		var vx: float = 0.0
		if not pth.is_empty():
			vx = (pth[0] - pos).x
		var working: bool = working_states.has(String(r.get("state", "")))
		var vtint := col if ail in ["sick", "wounded"] else race_tint
		drawn_villager = Assets.draw_villager(self, prof,
				"left" if vx < -1.0 else "right", moving, working,
				pos + Vector2(0, -lift - bob * 0.6),
				_anim_time + float(int(r["id"]) % 7) * 0.13, vtint, race_scale)
		if drawn_villager and bool(race_def.get("halo", false)):
			# ангел: тонкий нимб над головой
			var h := 30.0 * race_scale
			draw_arc(pos + Vector2(0, -lift - h), 5.0, PI * 0.15, PI * 0.85, 10,
					Color(1.0, 0.95, 0.6, 0.85), 2.0)
	if not drawn_villager:
		# тело — готовая текстурка (v1.21.5): одна команда вместо пяти
		var body := _res_sprite(col, radius)
		var half := float(body.get_width()) * 0.5
		draw_texture_rect(body, Rect2(center - Vector2(half, half),
				Vector2(float(body.get_width()), float(body.get_width()))), false)
	# голем-староста: белое «лицо» камня поверх кружка (он один на город)
	if _is_elder_golem(r):
		draw_circle(center, radius - 3.0, Color(1.0, 1.0, 1.0, 0.95))
		draw_circle(center + Vector2(-2.0, -1.5), 1.1, Color("#3a3f4a"))
		draw_circle(center + Vector2(2.0, -1.5), 1.1, Color("#3a3f4a"))
	# спарринг стражей (v1.23): перекрёстные клинки над парой
	if String(r.get("state", "")) == "spar":
		var top := center + Vector2(0, -radius - 7.0)
		var clash := 1.0 + 0.3 * sin(_anim_time * 10.0)
		draw_line(top + Vector2(-4.0 * clash, -3.0), top + Vector2(4.0 * clash, 3.0), Color("#e0e0e0"), 1.5)
		draw_line(top + Vector2(-4.0 * clash, 3.0), top + Vector2(4.0 * clash, -3.0), Color("#e0e0e0"), 1.5)
	# груз носильщика (M6): узел цвета ресурса; бревно/сырой камень (v1.21) —
	# покрупнее: видно, что тащит лесоруб и шахтёр (несёт на теле — с лифтом)
	if float(r.get("carry", 0.0)) > 0.0:
		var bag: Color = _pile_colors.get(String(r.get("carry_res", "")), Color(0.8, 0.7, 0.5))
		draw_circle(center + Vector2(radius + 2.0, -1.0), 3.4, bag.darkened(0.1))
		draw_circle(center + Vector2(radius + 1.2, -1.8), 1.6, bag.lightened(0.15))
	if int(r.get("log_size", 0)) > 0:
		var log_col := Color("#8d6e63") if int(r["log_size"]) < 3 else Color("#6d4c33")
		draw_circle(center + Vector2(radius + 3.0, -1.0), 4.2, log_col.darkened(0.2))
		draw_circle(center + Vector2(radius + 1.8, -2.2), 1.8, log_col.lightened(0.2))
	elif float(r.get("raw", 0.0)) > 0.0 or float(r.get("carry_iron", 0.0)) > 0.0 \
			or float(r.get("carry_stone", 0.0)) > 0.0:
		draw_circle(center + Vector2(radius + 3.0, -1.0), 4.2, Color("#9e9e9e").darkened(0.15))
		draw_circle(center + Vector2(radius + 1.8, -2.2), 1.8, Color("#bdbdbd"))
	# разговор-облачко (M12): реплика над головой болтающих
	var chat_key := String(r.get("chat_key", ""))
	if chat_key != "" and String(r["state"]) == "chat":
		_draw_speech_bubble(center, Loc.t(chat_key))
	# v1.56: обоснованные слухи/диалоги — событие дня выводится облачком
	if String(r.get("say", "")) != "" and float(r.get("say_until", 0.0)) > float(sim.time):
		_draw_speech_bubble(pos, Loc.t(String(r["say"])))

func _is_elder_golem(r: Dictionary) -> bool:
	return String(r.get("prof", "")) == "elder"


## Облачко реплики (M12, имитация жизни): плашка с текстом и хвостиком.
func _draw_speech_bubble(pos: Vector2, text: String) -> void:
	var font := ThemeDB.fallback_font
	var fsize := 10
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x + 10.0
	var top := pos + Vector2(-width * 0.5, -58.0)
	var rect := Rect2(top, Vector2(width, 16.0))
	draw_rect(rect, Color(1, 1, 0.96, 0.92))
	draw_rect(rect, Color(0.35, 0.3, 0.25, 0.8), false, 1.0)
	# v1.67.2: локальные точки с трансформом — точность триангуляции
	draw_set_transform(pos, 0.0, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3, -42), Vector2(3, -42), Vector2(0, -36)]),
		Color(1, 1, 0.96, 0.92))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_string(font, top + Vector2(5, 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize,
			Color(0.2, 0.16, 0.12))


## Герой в общем сортированном слое (M12): тело и меч рисует сам герой
## в переданный canvas, спрайт-нода в городе скрыта.
## v1.36.1: на плато герой стоит выше равнины (подъём анимируется на
## лестнице) — высота ощущается, а не выглядит плоской текстурой.
func _draw_hero(hero) -> void:
	var lift := _entity_lift("hero", hero.global_position)
	hero.draw_body(self, hero.global_position + Vector2(0, -lift))


func _draw_ghost() -> void:
	if dragging and zone_mode != "":
		_draw_zone_preview()
		return
	if road_mode:
		# режим дороги: подсветка тайла под мышью и уже проложенных дорог
		var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
		if map.in_bounds(tile):
			var ok: bool = sim._zone_cell_ok(tile) and int(sim.res.get("stone", 0)) >= int(sim.cfg.get("roads", {}).get("cost_stone", 1))
			draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts)),
					Color(0.5, 1.0, 0.5, 0.35) if ok else Color(1.0, 0.3, 0.3, 0.35))
		return
	if plant_mode:
		# посадка леса (M11): саженец под курсором, годность по траве и семенам
		var ptile: Vector2i = map.tile_of_px(get_global_mouse_position())
		if map.in_bounds(ptile):
			var ok2: bool = sim.can_plant_at(ptile)
			draw_rect(Rect2(Vector2(ptile) * map.ts, Vector2(map.ts, map.ts)),
					Color(0.5, 1.0, 0.5, 0.35) if ok2 else Color(1.0, 0.3, 0.3, 0.35))
			var bottom: Vector2 = Vector2(ptile) * map.ts + Vector2(map.ts / 2.0, map.ts * 0.92)
			Assets.draw_ref(self, "e:sap2", bottom, map.ts * 0.9, false,
					Color(1, 1, 1, 0.6))
		return
	if enchant_mode != "":
		# режим зачарования: подсветка тайла под мышью
		var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
		if not map.in_bounds(tile):
			return
		var col := Color(0.7, 0.5, 1.0, 0.45)
		if city != null and not city.enchant_target_valid(tile):
			col = Color(1.0, 0.3, 0.3, 0.4)
		draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts)), col)
		return
	if move_mode:
		_draw_move_ghost()
		return
	if plaza_mode:
		_draw_plaza_ghost()
		return
	if build_mode == "":
		return
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not map.in_bounds(tile):
		return
	var ok: bool = sim.is_buildable_rect(build_mode, tile) and sim.can_afford(_cost_of(build_mode))
	var col := Color(0.5, 1.0, 0.5, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	# призрак всего прямоугольника здания (2×2; стены/ворота/мост — 1×1)
	var w := float(sim.bld_w_of_type(build_mode))
	draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts * w, map.ts * w)), col)
	draw_rect(Rect2(Vector2(tile) * map.ts, Vector2(map.ts * w, map.ts * w)).grow(-2),
			Color(col.r, col.g, col.b, 0.9), false, 2.0)


## Призрак переноса (этап 2, аспект 5): пока здание не выбрано — подсветка
## здания под курсором (зелёная — годное); после выбора — рамка снимка
## и прямоугольник под мышью (зелёный/красный по правилам места).
func _draw_move_ghost() -> void:
	var ts := float(map.ts)
	var tile: Vector2i = map.tile_of_px(get_global_mouse_position())
	if not map.in_bounds(tile):
		return
	if move_bld_id < 0:
		var b: Dictionary = sim.building_at(tile)
		var ok_b: bool = sim._active(b)
		var hb := Rect2(Vector2(b["tile"]) * ts,
				Vector2(ts * float(sim.bld_w(b)), ts * float(sim.bld_w(b)))) if ok_b \
				else Rect2(Vector2(tile) * ts, Vector2(ts, ts))
		draw_rect(hb.grow(-1), Color(0.5, 1.0, 0.5, 0.8) if ok_b else Color(1.0, 0.3, 0.3, 0.5),
				false, 2.0)
		return
	var picked: Dictionary = {}
	for b2 in sim.buildings:
		if int(b2["id"]) == move_bld_id:
			picked = b2
			break
	if picked.is_empty():
		return
	# рамка выбранного здания пульсирует
	var pw := float(sim.bld_w(picked))
	var pr := Rect2(Vector2(picked["tile"]) * ts, Vector2(ts * pw, ts * pw))
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 220.0)
	draw_rect(pr.grow(-1), Color(1.0, 0.85, 0.3, pulse), false, 2.5)
	# прямоугольник под курсором — годен ли (собственные клетки не мешают)
	var w := float(sim.bld_w_of_type(String(picked["type"])))
	var ok: bool = sim.move_spot_ok(picked, tile)
	var col := Color(0.5, 1.0, 0.5, 0.4) if ok else Color(1.0, 0.3, 0.3, 0.4)
	draw_rect(Rect2(Vector2(tile) * ts, Vector2(ts * w, ts * w)), col)
	draw_rect(Rect2(Vector2(tile) * ts, Vector2(ts * w, ts * w)).grow(-2),
			Color(col.r, col.g, col.b, 0.9), false, 2.0)


## Выделение зоны (M6): прямоугольник от первой точки до курсора,
## негодные клетки — красным.
func _draw_zone_preview() -> void:
	var col: Color = _zone_colors.get(zone_mode, Color(0.7, 0.7, 0.4))
	var x0 := mini(drag_from.x, drag_to.x)
	var x1 := maxi(drag_from.x, drag_to.x)
	var y0 := mini(drag_from.y, drag_to.y)
	var y1 := maxi(drag_from.y, drag_to.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var tile := Vector2i(x, y)
			if not map.in_bounds(tile):
				continue
			var rect := Rect2(Vector2(tile) * map.ts, Vector2(map.ts, map.ts))
			var ok: bool = sim._zone_cell_ok(tile)
			if ok:
				draw_rect(rect, Color(col.r, col.g, col.b, 0.35))
			else:
				draw_rect(rect, Color(1.0, 0.3, 0.3, 0.3))


func _center(x: int, y: int) -> Vector2:
	return Vector2(x * map.ts + map.ts / 2.0, y * map.ts + map.ts / 2.0)


func _build_work(type_id: String) -> float:
	if _work_cache.has(type_id):
		return float(_work_cache[type_id])
	var work := 1.0
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			work = float(d["build_work"])
			break
	_work_cache[type_id] = work
	return work


func _cost_of(type_id: String) -> Dictionary:
	for d in sim.cfg["buildings"]:
		if String(d["id"]) == type_id:
			return d["cost"]
	return {}
