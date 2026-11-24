#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# v1.99.0 «Досуг и сытость»: праздник урожая, песни у костра, мягче старт
# волн, имена в номинативе, голоса дневника для остальных черт.
import io
import json
import sys


def patch(path, old, new):
    src = io.open(path, encoding='utf-8').read()
    if old not in src:
        print('!! НЕ НАЙДЕНО в %s: %r' % (path, old[:70]))
        sys.exit(1)
    io.open(path, 'w', encoding='utf-8', newline='').write(src.replace(old, new, 1))


# ---------- 1. баланс: мягче старт волн ----------
patch('data/city.json', '"raid_every_days": 10.0,', '"raid_every_days": 12.0,')
s = io.open('data/city.json', encoding='utf-8').read()
if '"start_day": 10.0' in s:
    s = s.replace('"start_day": 10.0', '"start_day": 14.0', 1)
    io.open('data/city.json', 'w', encoding='utf-8', newline='').write(s)
print('волны: каждая 12-я день, первая не раньше 14-го')

# ---------- 2. праздник урожая (осень, раз в год) ----------
patch('scripts/city_sim_life.gd',
      '''func _roll_goals() -> void:
	var v3 := _v3()
	var pool: Array = people.get("goals", [])
	if pool.is_empty():
		return''',
      '''func _roll_goals() -> void:
	var v3 := _v3()
	var pool: Array = people.get("goals", [])
	if pool.is_empty():
		return
	# v1.99: ПРАЗДНИК УРОЖАЯ — осенью, с полным погребом, раз в год:
	# весь город гуляет, настроение всем, мечты «пировать» сбываются
	if String(season()) == "autumn" and int(day) - int(_feast_last) >= 60:
		var need_food := float(_adults().size()) * 4.0
		if float(res.get("food", 0.0)) >= need_food:
			_feast_last = int(day)
			_chron("chron.harvest_feast")
			events.append({"type": "harvest_feast"})
			for r2 in residents:
				r2["mood"] = clampf(float(r2.get("mood", 50.0)) + float(people.get("feast_mood", 8.0)), 0.0, 100.0)
				if String(r2.get("goal", "")) == "feast_tavern":
					r2["goal"] = ""
					res_log(r2, "dlog.goal_done", ["feast_tavern"])
					_assign_goal(r2, pool)
				res_log(r2, "dlog.feast")''')
patch('scripts/city_sim_base.gd',
      'var mold_burned: Dictionary = {}  # v1.88: выжженные магией клетки (след)',
      'var mold_burned: Dictionary = {}  # v1.88: выжженные магией клетки (след)\n'
      'var _feast_last := -999          # v1.99: день последнего праздника урожая')

# ---------- 3. костёр с песнями: +настроение у огня ----------
patch('scripts/city_sim_residents.gd',
      '''		if bool(plan.get("tavern", false)):
			r["tavern_visited"] = true''',
      '''		if bool(plan.get("tavern", false)):
			r["tavern_visited"] = true
		else:
			# v1.99: гуляния у костра с песнями — +2 настроения
			r["mood"] = clampf(float(r.get("mood", 50.0)) + 2.0, 0.0, 100.0)
			res_log(r, "dlog.fire")''')

# ---------- 4. имена в номинативе (без склонений) ----------
p = 'loc/ru.json'
L = json.load(open(p, encoding='utf-8'))
N = {
    'diary.married.plain': 'Свадьба: я и %s — теперь одна семья.',
    'diary.married.grumpy': '%s — теперь моя семья. Кто бы сказал год назад.',
    'diary.married.cheerful': 'Я и %s повенчались! Гуляли до темноты!',
    'diary.married.lazy': 'Свадьба с %s. Красиво. Даже плясать пришлось.',
    'diary.married.dreamer': '%s и я — теперь одно. Кажется, сбылось.',
    'diary.married.stoic': 'Венчание: я и %s. Крепкая связь.',
    'diary.lost.plain': '%s больше нет с нами. Город осиротел.',
    'diary.lost.grumpy': '%s ушёл в землю... И снова город забирает своих.',
    'diary.lost.cheerful': '%s больше нет. Останется в памяти смех, а не слёзы.',
    'diary.lost.lazy': '%s ушёл. Даже горевать лень... хотя нет, не лень.',
    'diary.lost.dreamer': '%s стал частью ветра. Я буду говорить с ветром.',
    'diary.lost.stoic': '%s покинул этот мир. Горе ношу молча.',
    'diary.quarrel.plain': '%s и я поругались. Слова — что камни.',
    'diary.quarrel.grumpy': '%s сам виноват! Всегда он первый, а крайний — я.',
    'diary.quarrel.cheerful': 'Я и %s побранились... Помиримся — и снова мир!',
    'diary.quarrel.lazy': '%s и я поругались. Даже ругаться — утомительно.',
    'diary.quarrel.dreamer': 'Слова с %s рассыпались камнями. Зачем мы так?',
    'diary.quarrel.stoic': '%s и я в ссоре. Запомню — но отпущу.',
    'diary.gift.plain': 'Я и %s обменялись подарками — от сердца.',
    'diary.gift.grumpy': '%s вдруг дарит подарки. Что-то замышляет, верно?',
    'diary.gift.cheerful': 'Подарки с %s! Праздник души!',
    'diary.gift.lazy': 'Дарить — хлопоты. Но от %s было приятно.',
    'diary.gift.dreamer': 'Подарок от друга... В таких мелочах живёт тепло: %s.',
    'diary.gift.stoic': 'Я и %s обменялись подарками. Дружба крепчает.',
    'diary.friend.plain': '%s и я — теперь друзья.',
    'diary.friend.grumpy': 'Подружился с %s. Человек толковый — редкость тут.',
    'diary.friend.cheerful': 'Теперь у меня есть друг — %s! Громко заявляю всем!',
    'diary.friend.lazy': 'Друг %s — за меня даже работать будет. Шучу. Наверное.',
    'diary.friend.dreamer': '%s и я — друзья. Так бывает редко, и это ценно.',
    'diary.friend.stoic': 'Дружба с %s. Надёжно.',
}
for k, v in N.items():
    L[k] = v

# ---------- 5. голоса остальных черт (матрица для частых событий) ----------
V2 = {
    'coward': {
        'wounded': 'Ранен! Я же говорил — не лезть... почему меня послали?!',
        'sick': 'Хворь... я не умру, я не хочу умирать!',
        'lost': '%s исчез... следующий — я? Нет-нет-нет.',
        'quarrel': '%s на меня наорал. Я промолчал. Но запомню!',
        'winter': 'Зима. В темноте что-то ходит... я слышал!',
        'tavern': 'Сидел в углу таверны. На всякий случай у двери.'},
    'kind': {
        'wounded': 'Рана болит, но другие ранены сильнее — им бы помочь.',
        'sick': 'Хворь одолела... кто же теперь накормит сирот?',
        'lost': 'Горюю о %s тихо — теперь я за старшего у его дома.',
        'quarrel': 'Я и %s в ссоре... Первым подойду мириться.',
        'winter': 'Зима. Обхожу дворы — все ли с дровами.',
        'tavern': 'В таверне слушал больше, чем говорил. Улыбался всем.'},
    'strong': {
        'wounded': 'Царапина. Носить рану — не для моих плеч.',
        'sick': 'Хворь слабее меня. Завтра встану.',
        'lost': 'Не уберёчь %s... Сильные руки бесполезны против горя.',
        'quarrel': '%s и я не поделили слово. Пусть — я сильнее, я и уступлю.',
        'winter': 'Зима? Зиму я ношу, как полено — на одном плече.',
        'tavern': 'В таверне меня ставили на руку — выиграл всё пиво.'},
    'hardworking': {
        'wounded': 'Руки чешутся работать, а приходится отлёживать.',
        'sick': 'Кто же работу доделает, если я лежу?..',
        'lost': '%s трудился рядом... теперь его метлу некому взять.',
        'quarrel': 'Поругался с %s — а после ссоры и работать сподручнее.',
        'winter': 'Зима — не повод. Ледник рубится, полки строятся.',
        'tavern': 'В таверне не пью — слушаю заказы и планирую день.'},
    'glutton': {
        'wounded': 'Рана болит почти так же сильно, как хочет есть.',
        'sick': 'Хворь без аппетита — вот это по-настоящему страшно.',
        'lost': '%s ушёл... на поминках не ели. Так и просидел голодным.',
        'quarrel': '%s отнял у меня лучший кусок — вот и вся ссора!',
        'winter': 'Зима. Погреб — самое тёплое место в городе.',
        'tavern': 'Съел больше всех — за это и полюбили.'},
    'magiclover': {
        'wounded': 'Рана горит... если бы коснуться благодати, заживёт к утру.',
        'sick': 'Хворь? Свечу кристалл — он согревает лучше порошков.',
        'lost': '%s ушёл туда, где магия живёт. Я верю.',
        'quarrel': '%s назвал мою тягу к благодати пороком. Пусть.',
        'winter': 'Зима, а кристалл светит — благодать теплее дров.',
        'tavern': 'В таверне рассказывали о кристаллах — слушал как заворожённый.'},
}
cnt = 0
for v, d in V2.items():
    for k, t in d.items():
        L['diary.%s.%s' % (k, v)] = t
        cnt += 1
L['chron.harvest_feast'] = 'Город пировал урожаем: столы на площади, песни до утра.'
L['dlog.feast'] = 'Праздник урожая! Столы на площади — город гулял до утра.'
L['dlog.fire'] = 'Песни у костра. Хороший вечер.'
L['city.harvest_feast'] = 'Праздник урожая!'
io.open(p, 'w', encoding='utf-8', newline='\n').write(json.dumps(L, ensure_ascii=False, indent='\t'))
print('локали ок (новых абзацев:', cnt, ')')

# ---------- 6. res_voice: новые черты ----------
patch('scripts/city_sim_base.gd',
      '''func res_voice(r: Dictionary) -> String:
	for v in ["grumpy", "cheerful", "lazy", "dreamer", "stoic"]:
		if v in (r.get("traits", []) as Array):
			return v
	return "plain"''',
      '''func res_voice(r: Dictionary) -> String:
	for v in ["grumpy", "cheerful", "lazy", "dreamer", "stoic",
			"coward", "kind", "strong", "hardworking", "glutton", "magiclover"]:
		if v in (r.get("traits", []) as Array):
			return v
	return "plain"''')

# thoughts: расширить внутренний список теми же голосами
patch('scripts/city_sim_residents.gd',
      '''	for v in ["grumpy", "cheerful", "lazy", "hardworking", "glutton", "dreamer", "stoic"]:
		if v in (r.get("traits", []) as Array):
			voice = String(v)
			break''',
      '''	for v in ["grumpy", "cheerful", "lazy", "hardworking", "glutton", "dreamer", "stoic",
			"coward", "kind", "strong", "magiclover"]:
		if v in (r.get("traits", []) as Array):
			voice = String(v)
			break''')
print('голоса ок')
PYEOF
