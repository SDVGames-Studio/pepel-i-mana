# -*- coding: utf-8 -*-
## v2.2 патч 2: сэмплер следов всех ходячих в тике города.
import io, shutil, sys

p = r"F:\Z2\.zcode\workspace\default\pepel-i-mana\scripts\city_sim_tick.gd"
src = io.open(p, encoding="utf-8").read()
if "_update_tracks" in src:
    print("ALREADY PATCHED")
    sys.exit(0)

anchor1 = "\t_update_wanderers(dt)\n"
assert anchor1 in src, "anchor1 (_update_wanderers call) missing"
src = src.replace(anchor1, anchor1 + "\t_update_tracks(dt, day_len)\n", 1)

tail = '''

## ==================== СЛЕДЫ ВСЕХ ХОДЯЧИХ (v2.2 п.3) ====================
## Сэмплер: раз в ~0.9 сек записывает позицию каждого идущего (жители на
## ногах, звери, путники/лазутчики, мутанты/ищейки) в city_tracks. Следы
## тают по конфигу (дождь ускоряет — CityTracks.RAIN_MULT). Следы героя
## живут отдельно (hero_tracks) — скауты улья читают их как раньше.
const TRACKS := preload("res://scripts/city_tracks.gd")

var _tracks_prune_day := 0


func _update_tracks(dt: float, day_len: float) -> void:
	_track_accum += dt
	if _track_accum < 0.9:
		return
	_track_accum = 0.0
	var tcfg: Dictionary = cfg.get("tracks", {})
	# суточная чистка: дождь сокращает жизнь следов, цепочка-подсказка гаснет
	if day != _tracks_prune_day:
		_tracks_prune_day = day
		var life := float(tcfg.get("life_days", 1.2)) * day_len
		if weather == "rain":
			life *= TRACKS.RAIN_MULT
		TRACKS.prune(city_tracks, time, life)
		track_chain = []
	var movers: Array = []
	for r in residents:
		if int(r.get("inside", 0)) > 0:
			continue
		movers.append([r, "res"])
	for a in animals:
		movers.append([a, "animal"])
	for w in wanderers:
		if bool(w.get("spy", false)):
			movers.append([w, "spy"])
		else:
			movers.append([w, "wanderer"])
	for r in raiders:
		movers.append([r, "raider"])
	for e in movers:
		var u: Dictionary = e[0]
		var pos := Vector2(u.get("pos", Vector2.INF))
		if pos == Vector2.INF:
			continue
		var who: String = e[1]
		var key := String(u.get("id", -1)) + "|" + who
		var last: Vector2 = _track_last.get(key, pos)
		if last.distance_to(pos) < 2.0:
			continue   # стоит на месте — след не топчется
		var dir := pos - last
		city_tracks = TRACKS.push(city_tracks, pos, time, who, dir,
				float(tcfg.get("min_step", 24.0)),
				int(tcfg.get("cap", 1200)))
		_track_last[key] = pos
'''
src = src.rstrip("\n") + "\n" + tail

shutil.copy(p, p + ".bak")
io.open(p, "w", encoding="utf-8", newline="\n").write(src)
print("OK city_sim_tick.gd")
