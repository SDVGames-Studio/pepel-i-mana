# Часть: события-истории про конкретных жителей (M4/M7).
# Структура v1.62.0: вынесены из city_sim_gov.gd — это один класс,
# поведение не меняется.
extends "res://scripts/city_sim_gov.gd"

## Дневной бросок: события-истории про конкретных жителей (пункт плана M4).
func _roll_stories() -> void:
	var scfg: Dictionary = people.get("stories", {})
	if scfg.is_empty():
		return
	if _event_rng.randf() >= float(scfg.get("chance_per_day", 0.5)):
		return
	match _weighted_pick(scfg.get("weights", {})):
		"quarrel":
			_story_quarrel(scfg)
		"friendship":
			_story_friendship(scfg)
		"discovery":
			_story_discovery(scfg)
		"betrayal":
			_story_betrayal(scfg)
		"mutation":
			_story_mutation(scfg)
		"festival":
			_story_festival(scfg)
		"prodigy":
			_story_prodigy(scfg)
		"brave_deed":
			_story_brave_deed(scfg)
		"meteor":
			_story_meteor(scfg)
		"herbs":
			_story_herbs(scfg)
		"night_terror":
			_story_night_terror(scfg)
		"wedding":
			_story_wedding(scfg)
		"artifact":
			_story_artifact(scfg)
		"good_harvest":
			_story_good_harvest(scfg)
		"stranger":
			_story_stranger(scfg)


## Ссора (ответ №29, отключается галочкой): ворчун портит настроение ещё кому-то.
func _story_quarrel(scfg: Dictionary) -> void:
	if not conflicts or residents.size() < 2:
		return
	# сухой закон (M14-H): ссор реже
	if has_law("prohibition") \
			and _event_rng.randf() < float(law_param("prohibition", "quarrel_chance_mult", 1.0)):
		return
	var instigators: Array = []
	for r in _adults():
		if _has_trait_flag(r, "instigator"):
			instigators.append(r)
	if instigators.is_empty():
		return
	var a: Dictionary = instigators[_event_rng.randi_range(0, instigators.size() - 1)]
	var others: Array = []
	for r in _adults():
		if r != a:
			others.append(r)
	if others.is_empty():
		return
	var b: Dictionary = others[_event_rng.randi_range(0, others.size() - 1)]
	var dm: float = float(scfg.get("quarrel_mood", -15.0))
	for side in [a, b]:
		side["mood"] = clampf(float(side["mood"]) + dm, 0.0, 100.0)
	_rel_change(a, b, float(_v3().get("quarrel_rel_hit", -18.0)))   # отношения v3
	_mem_push(a, "quarrel")
	_mem_push(b, "quarrel")
	_chron("chron.quarrel", String(a["name"]), String(b["name"]))
	events.append({"type": "quarrel", "a": String(a["name"]), "b": String(b["name"])})


## Дружба (ответ №34): пара работает вместе эффективнее и бодрее духом.
func _story_friendship(scfg: Dictionary) -> void:
	var cands: Array = []
	for r in _adults():
		if int(r.get("friend", -1)) < 0 and float(r["mood"]) >= 50.0:
			cands.append(r)
	if cands.size() < 2:
		return
	var a: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	var b: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	if a == b:
		return
	a["friend"] = int(b["id"])
	b["friend"] = int(a["id"])
	var dm: float = float(scfg.get("friendship_mood", 10.0))
	for side in [a, b]:
		side["mood"] = clampf(float(side["mood"]) + dm, 0.0, 100.0)
	_chron("chron.friendship", String(a["name"]), String(b["name"]))
	events.append({"type": "friendship", "a": String(a["name"]), "b": String(b["name"])})


## Находка (навык пригодился): излишек ресурса в общий пул.
func _story_discovery(scfg: Dictionary) -> void:
	var skilled: Array = []
	var expert_at: float = float(people.get("skill_expert_at", 3.0))
	for r in _adults():
		if float(r.get("skill", 0.0)) >= expert_at:
			skilled.append(r)
	if skilled.is_empty():
		return
	var r: Dictionary = skilled[_event_rng.randi_range(0, skilled.size() - 1)]
	var roll := _event_rng.randf()
	var key := "food"
	var amount: float = float(scfg.get("discovery_food", 12))
	if roll > 0.8:
		key = "crystal"
		amount = float(scfg.get("discovery_crystal", 1))
	elif roll > 0.4:
		key = "stone"
		amount = float(scfg.get("discovery_stone", 6))
	_add_resource_capped(key, amount)
	_chron("chron.discovery", String(r["name"]), key)
	events.append({"type": "discovery", "name": String(r["name"]), "res": key})


## Предательство (жадный в унынии крадёт еду; страж в городе — пойман).
func _story_betrayal(scfg: Dictionary) -> void:
	if not conflicts:
		return
	var thieves: Array = []
	for r in _adults():
		if _has_trait_flag(r, "can_steal") and float(r["mood"]) < 40.0:
			thieves.append(r)
	if thieves.is_empty():
		return
	var r: Dictionary = thieves[_event_rng.randi_range(0, thieves.size() - 1)]
	var guard_near := false
	for other in residents:
		if String(other["prof"]) == "guard":
			guard_near = true
			break
	if guard_near:
		r["mood"] = clampf(float(r["mood"]) - 15.0, 0.0, 100.0)
		_chron("chron.betrayal_caught", String(r["name"]))
		events.append({"type": "betrayal_caught", "name": String(r["name"])})
		return
	var amount: float = minf(float(scfg.get("betrayal_food", 10)), float(res["food"]))
	res["food"] = maxf(0.0, float(res["food"]) - amount)
	var dm: float = float(scfg.get("betrayal_mood", -5.0))
	for other in residents:
		other["mood"] = clampf(float(other["mood"]) + dm, 0.0, 100.0)
	_chron("chron.betrayal", String(r["name"]))
	events.append({"type": "betrayal", "name": String(r["name"])})


## Мутация (ответ №35): дикая магия меняет жителя — кому улучшение, кому болезнь.
func _story_mutation(scfg: Dictionary) -> void:
	if pollution < float(scfg.get("mutation_pollution", 30.0)):
		return
	var adults := _adults()
	if adults.is_empty():
		return
	var r: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
	if _event_rng.randf() < 0.5:
		r["work_bonus"] = float(r.get("work_bonus", 0.0)) + float(scfg.get("mutation_work_bonus", 0.1))
		_chron("chron.mutation_good", String(r["name"]))
		events.append({"type": "mutation_good", "name": String(r["name"])})
	else:
		_make_ail(r, "sick", "chron.mutation_bad")
		events.append({"type": "mutation_bad", "name": String(r["name"])})


## --- события-истории M7 (до 15) ---------------------------------------------

## Праздник в таверне: городу есть чем поживиться — все гуляют.
func _story_festival(scfg: Dictionary) -> void:
	if not tavern_active() or float(res["food"]) < float(scfg.get("festival_food", 15)):
		return
	res["food"] = maxf(0.0, float(res["food"]) - float(scfg.get("festival_food", 15)))
	var dm: float = float(scfg.get("festival_mood", 10.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	_chron("chron.festival")
	events.append({"type": "festival"})


## Одарённый ученик: умелый житель обучает товарища — навык растёт скачком.
func _story_prodigy(scfg: Dictionary) -> void:
	var expert_at: float = float(people.get("skill_expert_at", 3.0))
	var teacher: Dictionary = {}
	var student: Dictionary = {}
	for r in _adults():
		if float(r.get("skill", 0.0)) >= expert_at:
			teacher = r
			break
	for r in _adults():
		if not r.is_empty() and r != teacher and float(r.get("skill", 0.0)) < float(people.get("skill_max", 5.0)):
			student = r
			break
	if teacher.is_empty() or student.is_empty():
		return
	student["skill"] = minf(float(people.get("skill_max", 5.0)),
			float(student["skill"]) + float(scfg.get("prodigy_skill", 1.0)))
	_chron("chron.prodigy", String(teacher["name"]), String(student["name"]))
	events.append({"type": "prodigy", "a": String(teacher["name"]), "b": String(student["name"])})


## Храбрый поступок: храбрец спасает жителя — город гордится.
func _story_brave_deed(scfg: Dictionary) -> void:
	var heroes: Array = []
	for r in _adults():
		if _has_trait_flag(r, "fearless"):
			heroes.append(r)
	if heroes.is_empty():
		return
	var hero_r: Dictionary = heroes[_event_rng.randi_range(0, heroes.size() - 1)]
	var dm: float = float(scfg.get("brave_deed_mood", 8.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	_chron("chron.brave_deed", String(hero_r["name"]))
	events.append({"type": "brave_deed", "name": String(hero_r["name"])})


## Метеорит: упал камень с неба — добыча даром, но воздух дурит.
func _story_meteor(scfg: Dictionary) -> void:
	_add_resource_capped("stone", float(scfg.get("meteor_stone", 20)))
	add_pollution(float(scfg.get("meteor_pollution", 8.0)))
	_chron("chron.meteor")
	events.append({"type": "meteor"})


## Целебные травы: лекарь находит сбор — все больные выздоравливают разом.
func _story_herbs(scfg: Dictionary) -> void:
	if not _healer_ready():
		return
	var healed := 0
	for r in residents:
		if String(r.get("ail", "")) != "":
			r["ail"] = ""
			healed += 1
	if healed == 0:
		return
	_assign_jobs()
	_chron("chron.herbs", str(healed))
	events.append({"type": "herbs", "n": healed})


## Кошмары: наэлектризованный воздух не даёт спать — настроение чуть проседает.
func _story_night_terror(scfg: Dictionary) -> void:
	if pollution < float(scfg.get("terror_pollution", 20.0)):
		return
	var dm: float = float(scfg.get("terror_mood", -6.0))
	for r in residents:
		r["mood"] = clampf(float(r["mood"]) + dm, 0.0, 100.0)
	_chron("chron.night_terror")
	events.append({"type": "night_terror"})


## Свадьба: двое свободных жителей соединяются — им и городу веселей.
func _story_wedding(scfg: Dictionary) -> void:
	var cands: Array = []
	for r in _adults():
		if int(r.get("friend", -1)) < 0:
			cands.append(r)
	if cands.size() < 2:
		return
	var a: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	var b: Dictionary = cands[_event_rng.randi_range(0, cands.size() - 1)]
	if a == b:
		return
	a["friend"] = int(b["id"])
	b["friend"] = int(a["id"])
	var dm: float = float(scfg.get("wedding_mood", 12.0))
	for side in [a, b]:
		side["mood"] = clampf(float(side["mood"]) + dm, 0.0, 100.0)
	_chron("chron.wedding", String(a["name"]), String(b["name"]))
	events.append({"type": "wedding", "a": String(a["name"]), "b": String(b["name"])})


## Артефакт: житель выкапывает странную вещь — кристалл в пул, мастерство в голову.
func _story_artifact(scfg: Dictionary) -> void:
	var adults := _adults()
	if adults.is_empty():
		return
	var r: Dictionary = adults[_event_rng.randi_range(0, adults.size() - 1)]
	_add_resource_capped("crystal", float(scfg.get("artifact_crystal", 1)))
	r["skill"] = minf(float(people.get("skill_max", 5.0)),
			float(r["skill"]) + float(scfg.get("artifact_skill", 0.5)))
	_chron("chron.artifact", String(r["name"]))
	events.append({"type": "artifact", "name": String(r["name"])})


## Урожайный год: погода и руки сошлись — лишняя еда в амбар.
func _story_good_harvest(scfg: Dictionary) -> void:
	if _assigned_done_of_farm().is_empty():
		return
	_add_resource_capped("food", float(scfg.get("harvest_food", 18)))
	_chron("chron.good_harvest")
	events.append({"type": "good_harvest"})


## Странник: изгнанник делится припасами и слухами о данже.
func _story_stranger(scfg: Dictionary) -> void:
	_add_resource_capped("food", float(scfg.get("stranger_food", 10)))
	_add_resource_capped("crystal", float(scfg.get("stranger_crystal", 1)))
	_chron("chron.stranger")
	events.append({"type": "stranger"})


## Готовая ферма с работающим фермером — условие «Урожайного года».
func _assigned_done_of_farm() -> Dictionary:
	for b in buildings:
		if bool(b["done"]) and String(b["type"]) == "farm" and int(b["worker"]) > 0:
			return b
	return {}
