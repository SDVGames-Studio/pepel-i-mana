# -*- coding: utf-8 -*-
"""sfx.gd: сезонное перекрытие трека города (v3.0.4).
Запуск: python -I tools/patch_sfx_season.py
"""
import io
import os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "scripts", "sfx.gd")
s = io.open(P, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in s else "\n"

old = ("\treturn String((states.get(best, {}) as Dictionary)"
       '.get("music", "mus_city_day"))' + nl)
new = (
    "\tvar out := String((states.get(best, {}) as Dictionary)"
    '.get("music", "mus_city_day"))' + nl +
    "\t# v3.0.4: сезонные треки города — states.<ключ>.seasons.<сезон>" + nl +
    '\tif best == "city_day" or best == "city_night":' + nl +
    '\t\tvar seasons: Dictionary = (states.get(best, {}) as Dictionary)'
    '.get("seasons", {})' + nl +
    '\t\tvar ssn := String(state.get("season", ""))' + nl +
    "\t\tif (seasons as Dictionary).has(ssn):" + nl +
    "\t\t\tout = String((seasons as Dictionary)[ssn])" + nl +
    "\treturn out" + nl)
assert s.count(old) == 1, "count=%d" % s.count(old)
io.open(P, "w", encoding="utf-8", newline="").write(s.replace(old, new))
print("ok: sfx.gd track_for seasons")
