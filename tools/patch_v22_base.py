# -*- coding: utf-8 -*-
## v2.2 патч 1: состояние сима — следы, духи, тайные лагеря, отряд охотников.
import io, shutil, sys

p = r"F:\Z2\.zcode\workspace\default\pepel-i-mana\scripts\city_sim_base.gd"
src = io.open(p, encoding="utf-8").read()
if "city_tracks" in src:
    print("ALREADY PATCHED")
    sys.exit(0)

anchor1 = "var _last_wanderer_day := -99\n"
assert anchor1 in src, "anchor1 (wanderer vars) missing"
add1 = anchor1 + (
    "# v2.2 «Следы, алтарь благодати, тайные лагеря» ==========================\n"
    "var city_tracks: Array = []    # следы всех ходячих {pos, t, who, dir} — CityTracks\n"
    "var _track_last := {}          # ключ id|who -> pos последнего следа (троттлинг шага)\n"
    "var _track_accum := 0.0        # накопитель сэмплера следов (раз в ~0.9 сек)\n"
    "var _seeker_day := -99         # день последней отправки ищейки улья\n"
    "var track_chain: Array = []    # подсвеченная цепочка («идти по следу», E у героя)\n"
    "var track_hint_until := 0.0    # время, до которого цепочка подсвечена\n"
    "var spirits: Array = []        # духи благодати {id, bld, mode, pos, hp, hp_max, eff}\n"
    "var _spirit_id := 1\n"
    "var secret_camps: Array = []   # тайные лагеря {id, tile, kind, found, suspicion, visits, spies}\n"
    "var _camp_id := 1\n"
    "var _last_camp_day := -99\n"
    "var spy_known := {}            # имя путника -> {visits} (жители считают частые визиты)\n"
    "var hunter_squad: Dictionary = {}  # странствующие охотники {state, eta_day, edge, power, left, razed}\n"
    "var _last_squad_day := -99\n"
    "var acolyte_skill := 0.0       # мастерство аколита-контролёра (растёт со службой, 0..20)\n")
src = src.replace(anchor1, add1, 1)

anchor2 = "\twanderers = []\n\t_wanderer_id = 1\n\t_last_wanderer_day = -99\n"
assert anchor2 in src, "anchor2 (reset wanderers) missing"
add2 = anchor2 + (
    "\tcity_tracks = []\n"
    "\t_track_last = {}\n"
    "\t_track_accum = 0.0\n"
    "\t_seeker_day = -99\n"
    "\ttrack_chain = []\n"
    "\ttrack_hint_until = 0.0\n"
    "\tspirits = []\n"
    "\t_spirit_id = 1\n"
    "\tsecret_camps = []\n"
    "\t_camp_id = 1\n"
    "\t_last_camp_day = -99\n"
    "\tspy_known = {}\n"
    "\thunter_squad = {}\n"
    "\t_last_squad_day = -99\n"
    "\tacolyte_skill = 0.0\n")
src = src.replace(anchor2, add2, 1)

shutil.copy(p, p + ".bak")
io.open(p, "w", encoding="utf-8", newline="\n").write(src)
print("OK city_sim_base.gd")
