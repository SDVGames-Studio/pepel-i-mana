# -*- coding: utf-8 -*-
## v2.2 патч 3: хелперы духа благодати в базе (видны всей цепочке).
import io, shutil, sys

p = r"F:\Z2\.zcode\workspace\default\pepel-i-mana\scripts\city_sim_base.gd"
src = io.open(p, encoding="utf-8").read()
if "spirit_summon" in src:
    print("ALREADY PATCHED")
    sys.exit(0)

tail = '''

## ==================== ДУХ БЛАГОДАТИ (v2.2 п.2) ====================
## Призывается готовым алтарём благодати: не-житель на рабочем слоте —
## назначается на стройку или добычу, не ест/не спит/не уходит, гибнет
## от волн (алтарь перезывает через N дней).

## Эффективность духа: f(мастерство контролирующего аколита), 50–120%.
func spirit_eff() -> float:
	var gcfg: Dictionary = cfg.get("grace_altar", {})
	var k: float = clampf(acolyte_skill / maxf(1.0, float(gcfg.get("skill_max", 20.0))), 0.0, 1.0)
	return float(gcfg.get("eff_min", 0.5)) + k * float(gcfg.get("eff_span", 0.7))


## Призвать духа к алтарю (после постройки или повторно через N дней).
func spirit_summon(b: Dictionary) -> void:
	var ts := float(map.ts) if map != null else 48.0
	spirits.append({
		"id": _spirit_id, "bld": int(b["id"]), "mode": "idle",
		"pos": Vector2(b["tile"]) * ts + Vector2(ts * float(bld_w(b)) * 0.5, ts * 0.5),
		"hp": 45.0, "hp_max": 45.0, "eff": spirit_eff(),
		"skill": 0.0, "rank": 0, "fatigue": 0.0, "state": "work", "ail": "",
	})
	_spirit_id += 1
	b["spirit_respawn_day"] = -1
	events.append({"type": "spirit_summoned"})


## Дух этого алтаря ({} если нет живого).
func spirit_of(b: Dictionary) -> Dictionary:
	for s in spirits:
		if int(s["bld"]) == int(b["id"]):
			return s
	return {}
'''

src = src.rstrip("\n") + "\n" + tail
shutil.copy(p, p + ".bak")
io.open(p, "w", encoding="utf-8", newline="\n").write(src)
print("OK city_sim_base.gd (spirit helpers)")
