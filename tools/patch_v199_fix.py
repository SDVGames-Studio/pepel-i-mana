#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# v1.99: докатывающее — костёр, res_voice, thoughts, локали (идемпотентно).
import io
import json
import sys


def patch_once(path, old, new, marker):
    src = io.open(path, encoding='utf-8', newline='').read()
    if marker in src:
        print('уже:', marker[:40])
        return
    if old not in src:
        print('!! НЕ НАЙДЕНО в %s: %r' % (path, old[:70]))
        sys.exit(1)
    io.open(path, 'w', encoding='utf-8', newline='').write(src.replace(old, new, 1))


# 1) костёр с песнями
patch_once('scripts/city_sim_residents.gd',
           '\t\tif bool(plan.get("tavern", false)):\n'
           '\t\t\tr["tavern_visited"] = true',
           '\t\tif bool(plan.get("tavern", false)):\n'
           '\t\t\tr["tavern_visited"] = true\n'
           '\t\telse:\n'
           '\t\t\t# v1.99: гуляния у костра с песнями — +2 настроения\n'
           '\t\t\tr["mood"] = clampf(float(r.get("mood", 50.0)) + 2.0, 0.0, 100.0)\n'
           '\t\t\tres_log(r, "dlog.fire")',
           'гуляния у костра с песнями')

# 2) res_voice: 11 голосов
patch_once('scripts/city_sim_base.gd',
           '\tfor v in ["grumpy", "cheerful", "lazy", "dreamer", "stoic"]:\n'
           '\t\tif v in (r.get("traits", []) as Array):\n'
           '\t\t\treturn v\n'
           '\treturn "plain"',
           '\tfor v in ["grumpy", "cheerful", "lazy", "dreamer", "stoic",\n'
           '\t\t\t"coward", "kind", "strong", "hardworking", "glutton", "magiclover"]:\n'
           '\t\tif v in (r.get("traits", []) as Array):\n'
           '\t\t\treturn v\n'
           '\treturn "plain"',
           '"coward", "kind", "strong", "hardworking", "glutton", "magiclover"')

# 3) thoughts: 12 черт
patch_once('scripts/city_sim_residents.gd',
           '\tfor v in ["grumpy", "cheerful", "lazy", "hardworking", "glutton", "dreamer", "stoic"]:\n'
           '\t\tif v in (r.get("traits", []) as Array):\n'
           '\t\t\tvoice = String(v)\n'
           '\t\t\tbreak',
           '\tfor v in ["grumpy", "cheerful", "lazy", "hardworking", "glutton", "dreamer", "stoic",\n'
           '\t\t\t"coward", "kind", "strong", "magiclover"]:\n'
           '\t\tif v in (r.get("traits", []) as Array):\n'
           '\t\t\tvoice = String(v)\n'
           '\t\t\tbreak',
           '"coward", "kind", "strong", "magiclover"')

# 4) локали: номинатив + голоса + праздник
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
    'diary.lost.grumpy': '%с ушёл в землю... И снова город забирает своих.',
    'diary.lost.cheerful': '%s больше нет. Останется в памяти смех, а не слёзы.',
    'diary.lost.lazy': '%s ушёл. Даже горевать не хочется... нет, хочется.',
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
    'diary.gift.dreamer': 'Подарок от %s... В таких мелочах живёт тепло.',
    'diary.gift.stoic': 'Я и %s обменялись подарками. Дружба крепчает.',
    'diary.friend.plain': '%s и я — теперь друзья.',
    'diary.friend.grumpy': 'Подружился с %s. Человек толковый — редкость тут.',
    'diary.friend.cheerful': 'Теперь у меня есть друг — %s! Громко заявляю всем!',
    'diary.friend.lazy': 'Друг %s — за меня даже работать будет. Шучу. Наверное.',
    'diary.friend.dreamer': '%s и я — друзья. Так бывает редко, и это ценно.',
    'diary.friend.stoic': 'Дружба с %s. Надёжно.',
}
for k, v in N.items():
    L[k] = v.replace('%с', '%s')
V2 = {
    'coward': {
        'wounded': 'Ранен! Я же говорил — не лезть... почему меня послали?!',
        'sick': 'Хворь... я не умру, я не хочу умирать!',
        'quarrel': '%s на меня наорал. Я промолчал. Но запомню!',
        'winter': 'Зима. В темноте что-то ходит... я слышал!',
        'tavern': 'Сидел в углу таверны. На всякий случай у двери.'},
    'kind': {
        'wounded': 'Рана болит, но другие ранены сильнее — им бы помочь.',
        'sick': 'Хворь одолела... кто же теперь накормит сирот?',
        'quarrel': 'Я и %s в ссоре... Первым подойду мириться.',
        'winter': 'Зима. Обхожу дворы — все ли с дровами.',
        'tavern': 'В таверне слушал больше, чем говорил. Улыбался всем.'},
    'strong': {
        'wounded': 'Царапина. Носить рану — не для моих плеч.',
        'sick': 'Хворь слабее меня. Завтра встану.',
        'quarrel': '%s и я не поделили слово. Я сильнее — я и уступлю.',
        'winter': 'Зима? Зиму ношу, как полено — на одном плече.',
        'tavern': 'В таверне меня ставили на руку — выиграл всё пиво.'},
    'hardworking': {
        'wounded': 'Руки чешутся работать, а приходится отлёживать.',
        'sick': 'Кто же работу доделает, если я лежу?..',
        'quarrel': 'Поругался с %s — а после ссоры и работать сподручнее.',
        'winter': 'Зима — не повод. Лёд рубится, полки строятся.',
        'tavern': 'В таверне не пью — слушаю заказы и планирую день.'},
    'glutton': {
        'wounded': 'Рана болит почти так же сильно, как хочется есть.',
        'sick': 'Хворь без аппетита — вот это по-настоящему страшно.',
        'quarrel': '%s отнял у меня лучший кусок — вот и вся ссора!',
        'winter': 'Зима. Погреб — самое тёплое место в городе.',
        'tavern': 'Съел больше всех — за это и полюбили.'},
    'magiclover': {
        'wounded': 'Рана горит... коснуться благодати — заживёт к утру.',
        'sick': 'Хворь? Держу кристалл — он греет лучше порошков.',
        'quarrel': '%s назвал мою тягу к благодати пороком. Пусть.',
        'winter': 'Зима, а кристалл светит — благодать теплее дров.',
        'tavern': 'В таверне рассказывали о кристаллах — слушал, как заворожённый.'},
}
cnt = 0
for v, d in V2.items():
    for k, t in d.items():
        key = 'diary.%s.%s' % (k, v)
        L[key] = t.replace('%с', '%s')
        cnt += 1
feast = {
    'chron.harvest_feast': 'Город пировал урожаем: столы на площади, песни до утра.',
    'dlog.feast': 'Праздник урожая! Столы на площади — город гулял до утра.',
    'dlog.fire': 'Песни у костра. Хороший вечер.',
    'city.harvest_feast': 'Праздник урожая!',
}
for k, v in feast.items():
    L[k] = v
io.open(p, 'w', encoding='utf-8', newline='\n').write(json.dumps(L, ensure_ascii=False, indent='\t'))
print('локали ок; новых абзацев:', cnt, '; всего ключей:', len(L))
