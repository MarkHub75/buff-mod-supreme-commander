# Findings

## FAF mod hooking (source: references/fa-develop/lua/MODS.LUA)
- SIM-мод = папка в `/mods` с `mod_info.lua` (`ui_only = false`). Обязательные поля: `name`, `version` (integer), `author`, `uid` (GUID, новый на каждую версию).
- Мод может содержать папку `/hook`, повторяющую структуру игровых файлов. Файл хука **конкатенируется в конец** оригинального скрипта после его загрузки — можно переопределять функции, сохранив старую через `local oldFn = Fn` внутри блока `do ... end` (чтобы локальные переменные не конфликтовали с другими модами).

## Точка входа SIM (source: references/fa-develop/lua/simInit.lua)
- `BeginSession()` в `/lua/simInit.lua` вызывается движком после создания армий, прямо перед стартом игры — стандартное место для запуска фоновой логики мода.
- Паттерн фонового SIM-потока: `ForkThread(fn)` + `WaitSeconds(n)` в цикле (так делает сама игра: `GameOverListenerThread` в simInit.lua, интервалы в `lua/sim/score.lua`). `WaitSeconds` ждёт **игровые** секунды (1 игровая секунда = 10 тиков), т.е. интервал следует за игровым временем, а не реальным.
- `LOG(...)` из SIM-кода пишет в `game.log`.

## Армии, команды и альянсы (source: references/fa-develop/lua/simInit.lua, lua/aibrain.lua)
- `ArmyBrains` — глобальный массив брейнов, заполняется в `OnCreateArmyBrain(index, brain, name, nickname)`. У брейна есть поля: `Name` (имя армии, напр. ARMY_1), `Nickname` (имя игрока/AI), `BrainType` (`'Human'` | `'AI'`), `Human`, `Civilian`, `AI`, `Army` (кэш `GetArmyIndex()`).
- `ScenarioInfo.ArmySetup[name]` — настройки армии из лобби: `.Team` (число; `> 1` = армия в команде, `1` = без команды), `.ArmyIndex`, `.Human`, `.Civilian`, `.AIPersonality`.
- Альянсы из лобби применяются в `BeginSessionTeams()` (вызывается внутри `BeginSession()`): для всех армий с одинаковым `Team > 1` вызывается `SetAlliance(i, j, "Ally")`. До этого момента все армии считаются врагами. Проверка: SIM-глобал `IsAlly(i, j)`; `IsAlly(i, i)` = true (на этом полагается `BeginSessionUnionArmy`).
- Фракция брейна: движковый метод `brain:GetFactionIndex()`.

## Random, import и SIM-state модов (source: references/fa-develop)
- `Random(min, max)` в SIM-коде — синхронизированный движковый RNG, часть детерминированного состояния симуляции: все клиенты получают одинаковые значения (используется в `lua/sim/BuilderManager.lua`, `FactoryBuilderManager.lua` и др.). Вызывать его из UI-кода нельзя — это desync. `os.time`/реальное время в SIM не использовать.
- Файлы мода доступны для `import` по пути `/mods/<имя папки мода>/...` (пример в самой FAF: `import("/mods/supremescoreboard/modules/score_board.lua")` в `lua/ui/game/multifunction.lua`). Путь зависит от имени папки мода в каталоге mods.
- **`table.concat` в SupCom (LuaPlus) принимает только строки** — числа и таблицы вызывают ошибку `bad argument #1 to 'concat' (table contains non-strings)` (в отличие от стандартного Lua, где числа допустимы). Перед concat всё прогонять через `tostring`. Найдено на краше MVP 3 в реальной катке.
- `import` кэширует модули (таблица `__modules`): повторный import возвращает ту же таблицу, поэтому локальное состояние на уровне модуля живёт всю SIM-сессию — рабочий паттерн для SIM-state мода.

## Система баффов FAF (source: references/fa-develop/fa-develop/lua/sim/Buff.lua, lua/system/BuffBlueprints.lua)
- Бафф регистрируется вызовом глобальной `BuffBlueprint { Name=..., BuffType=..., Stacks=..., Duration=..., EntityCategory=..., Affects={...} }` — можно из любого SIM-модуля в любой момент (пишет в глобальную таблицу `Buffs`). Применение: `import('/lua/sim/Buff.lua').ApplyBuff(unit, buffName)`.
- Аффект `BuildRate = { Add, Mult }` пересчитывает build rate юнита от blueprint-значения (`Economy.BuildRate`) и вызывает `unit:SetBuildRate(val)` — blueprint не мутируется, эффект per-unit-instance. Готовый пример ровно нашего кейса: `BaseManagerEngineerDefaultBuildRate` в `lua/sim/OpBuffDefinitions.lua` (EntityCategory='ENGINEER', Mult=3, Stacks='REPLACE', Duration=-1).
- `Stacks='IGNORE'` — повторный ApplyBuff того же BuffType игнорируется; `Duration=-1` — перманентный бафф.
- **`Buff.HasBuff` небезопасен**: индексирует `unit.Buffs.BuffTable[BuffType][name]` без проверки на nil — падает, если юнит никогда не имел баффа этого BuffType. Проверять наличие самим: `unit.Buffs.BuffTable[type]` → и только потом `[name]`.
- Паттерн «баффать будущие юниты»: FAF применяет AI cheat-баффы в конце `Unit.OnCreate` (lua/sim/Unit.lua, `if self.Brain.CheatEnabled then ApplyCheatBuffs(self)`). Для мода — хук `/hook/lua/sim/Unit.lua` с обёрткой класса: `local oldUnit = Unit; Unit = Class(oldUnit) { OnCreate = function(self) oldUnit.OnCreate(self) ... end }`. Этот же паттерн использует сама FAF в конце Unit.lua (блок «Backwards compatibility with mods»), а подклассы (defaultunits и т.д.) создаются позже и наследуют обёртку.
- Категории: ACU несёт категорию ENGINEER — идиома FAF для «инженеры без ACU»: `categories.ENGINEER - categories.COMMAND` (см. lua/platoon.lua). SCU/инженерные станции/поды остаются в ENGINEER.

## UI ↔ SIM коммуникация (source: references/fa-develop/fa-develop/lua/SimCallbacks.lua, UserSync.lua, SimSync.lua; мод U4S из FAF-UI-Mods)
- **Хуки конкатенируются текстом ДО выполнения** (MODS.LUA: «the file is concatenated to the end of the script before it is run») — поэтому file-local переменные оригинала видны в хуке. Так мод добавляет SimCallback: в `/hook/lua/SimCallbacks.lua` просто `Callbacks.MyFunc = function(data, units) ... end` (таблица `Callbacks` — local в оригинале).
- **UI → SIM**: в UI-коде глобальная `SimCallback({ Func = 'MyFunc', Args = {...} })`; в сим-коллбек приходит `data` = Args. Отправителя проверять через `import('/lua/simutils.lua').GetCurrentCommandSourceArmy()` — возвращает army index человека, пославшего команду (nil для observer/replay). Коллбеки обязаны валидировать всё против читов.
- **SIM → UI**: в SIM писать в глобальную таблицу `Sync` (создаётся в SimSync.lua) — она копируется на UI-сторону каждый sim beat и сбрасывается; накопительные события класть списком под своим ключом (`Sync.MyKey = Sync.MyKey or {}; table.insert(...)` — так делает Sync.Voice). UI-сторона: хук `/hook/lua/UserSync.lua` с обёрткой `local _OnSync = OnSync; function OnSync() _OnSync(); if Sync.MyKey then ... end end` (точный паттерн — мод U4S).
- **Минимальный popup**: `UIUtil.QuickDialog(GetFrame(0), text, btn1Text, btn1Cb, btn2Text, btn2Cb, btn3Text, btn3Cb, destroyOnCallback, modalInfo)` — до 3 кнопок, текст переносится автоматически, возвращает `Popup` (метод `:Close()`, унаследован `IsDestroyed()`). При наличии коллбеков сам закрывается после клика (destroyOnCallback по умолчанию true).
- `GetFocusArmy()` (UI-глобал) — army index локального игрока; сравнивать с army index из сима, чтобы показать UI только нужному игроку. SIM-мод (`ui_only = false`) может хукать и UI-файлы — hook-папка применяется в обоих слоях.

## UI-виджеты FAF (source: references/fa-develop/fa-develop/lua/maui/window.lua, multilinetext.lua, ui/uiutil.lua)
- **Draggable окно** (стиль minimap): `Window(parent, title, icon, pin, config, lockSize, lockPosition, prefID, defaultPosition, textureTable)` из `/lua/maui/window.lua`. Drag за title bar встроен; позиция/размер сохраняются в профиль под `prefID`. Контент класть в `window:GetClientGroup()`. Переопределяемые: `OnClose` (крестик, по умолчанию no-op), `OnPinCheck(checked)` (pin-чекбокс — удобно как toggle), `OnMove/OnResize`. `defaultPosition` — {Left,Top,Right,Bottom}: числа (масштабируются автоматически) или lazy-функции (используются как есть). `lockSize=true` отключает ресайз мышью. Пример вызова: `CreateMinimap` в lua/ui/game/minimap.lua.
- **`MultiLineText` НЕ умеет word wrap** (TODO в коде). Для переноса текста: `import("/lua/maui/text.lua").WrapText(text, widthPx, advanceFn)` → список строк, каждая в свой `Text` (паттерн `UIUtil.QuickDialog`); advanceFn = `someText:GetStringAdvance(text)`.
- Кастомный модальный диалог = `Group` (руками посчитать Width/Height) + `Popup(parent, dialog)` из `/lua/ui/controls/popups/popup.lua`; `popup.OnShadowClicked/OnEscapePressed` переопределить в no-op, чтобы не закрывался мимо кнопок. Закрытие: `popup:Close()`.
- Кнопки: `UIUtil.CreateButtonWithDropshadow(parent, '/BUTTON/large/'|'/BUTTON/medium/'|'/BUTTON/small/', label)` — размер задаётся текстурой.
- Layout: смешивать реальные пиксели (`text:Height()`, ширины текстур) со скалированными отступами `LayoutHelpers.ScaleNumber(n)`; `LayoutHelpers.Below(a, b, pad)` выравнивает и Left по `b`, `AnchorToBottom` двигает только Top.
## Эффекты баффов: тонкости (source: references/fa-develop/fa-develop/lua/sim/Buff.lua, AdjacencyBuffs.lua, shield.lua, engine/Sim)
- **RateOfFire в бафф-системе инвертирован**: `BuffEffects.RateOfFire` делает `wep:ChangeRateOfFire(bp.RateOfFire / val)` — val < 1 означает БЫСТРЕЕ (adjacency-баффы дают отрицательные Add). При прямом вызове семантика обычная: blueprint `RateOfFire` = выстрелов/сек, `ChangeRateOfFire(bp.RateOfFire * 1.25)` = +25% скорострельности.
- **Weapon-аффекты (Damage/RateOfFire/MaxRadius) бьют по ВСЕМ оружиям юнита** — для выборочного эффекта (только AA, только direct fire) нужен свой цикл по `unit:GetWeapon(i)` с фильтром `wepBp.RangeCategory`: 'UWRC_AntiAir', 'UWRC_DirectFire', 'UWRC_IndirectFire', 'UWRC_AntiNavy', 'UWRC_Countermeasure'. Методы `wep:ChangeDamage/ChangeRateOfFire/ChangeMaxRadius` — те же engine-вызовы, что использует сама бафф-система.
- **Щит** — отдельная сущность `unit.MyShield`, создаётся в базовом `Unit.OnStopBeingBuilt` (не в OnCreate!). У неё стандартный entity health API: `GetMaxHealth/SetMaxHealth/GetHealth/SetHealth(instigator, val)`. Хук, обёртывающий OnStopBeingBuilt и вызывающий оригинал первым, уже видит созданный щит.
- **`brain:GetListOfUnits(cat, needToBeIdle, requireBuilt)` — третий параметр НЕ работает** (annotation в engine/Sim/CAiBrain.lua: "Appears to be not functional"). Недостроенных фильтровать вручную: `unit:GetFractionComplete() < 1`.
- **`BuffEffects.RadarRadius` ДАЁТ радар юнитам без радара** (вызывает InitIntel+EnableIntel, если радар не включён) — ограничивать EntityCategory категорией RADAR, иначе бафф раздаст радары всем.
- Regen-аффект: Mult считается от MaxHealth и обязан быть < 1 (иначе WARN и отмена) — для плоского бонуса использовать только Add.
- MaxHealth-аффект по умолчанию поднимает и текущее HP на ту же дельту (флаг DoNotFill отключает).
- Эффекты, для которых per-unit API НЕТ: reclaim bonus (yield лежит на пропах/команде реклейма).
## Расширение эффектов (source: references/fa-develop/fa-develop/lua/sim/buff.lua, Weapon.lua, Unit.lua, ui/game/tooltip.lua)
- **`ApplyBuff` сам проверяет `EntityCategory` блюпринта баффа** (`ParseEntityCategory` + `EntityCategoryContains`, buff.lua:711-716) и молча выходит, если юнит не подходит. Для составных категорий проще ставить `EntityCategory = 'ALLUNITS'` и точно таргетить своим category-объектом.
- **`Duration` баффа — в игровых секундах**: `BuffWorkThread` делает `WaitSeconds(buffDef.Duration)` и снимает бафф (`RemoveBuff` пересчитывает аффекты от оставшихся баффов). Рабочий паттерн временного баффа: `Duration = 60, Stacks = 'IGNORE'`.
- **`BuffCalculate` агрегирует ВСЕ баффы юнита по типу аффекта** (adds суммируются, mults перемножаются) — разные BuffType с MoveMult/MaxHealth корректно стекаются; снятие одного пересчитывает остальное.
- **`RemoveBuff` небезопасен как `HasBuff`**: индексирует `unit.Buffs.BuffTable[def.BuffType][buffName]` без nil-проверки — вызывать только после своей проверки наличия.
- **`wep:AddDamageMod(add)` / `wep:AddDamageRadiusMod(add)`** — плоские per-instance добавки к damage table оружия (Weapon.lua:688-698), значения подхватываются при следующем выстреле. А вот `DoTTime`/`DoTPulses` и `MuzzleSalvoSize` читаются напрямую из блюпринта — DoT и размер залпа per-instance не изменить.
- **`CreateUnitHPR(bpId, armyIndex, x, y, z, pitch, yaw, roll)`** — стандартный спавн юнита в SIM (сценарии, поды, external factories); `GetTerrainHeight(x, z)` — SIM-глобал для высоты. Faction index брейна (1 UEF, 2 Aeon, 3 Cybran, 4 Sera) → выбор блюпринта по фракции.
- **`brain:GiveResource('MASS'|'ENERGY', amount)`** — движковый метод, молча капится хранилищем (см. SimUtils.GiveResourcesToPlayer). `IsEnemy(a1, a2)` — SIM-глобал.
- **Условный build rate** («строит X быстрее»): хук `Unit.OnStartBuild(self, built, order)` → `ApplyBuff`, `OnStopBuild`/`OnFailedToBuild` → `RemoveBuff`. `Stacks='IGNORE'` делает повторный apply на очереди целей no-op.
- **Тултипы UI**: `import('/lua/ui/game/tooltip.lua').CreateMouseoverDisplay(parent, {text=title, body=desc}, delay, true--[[extended]], width, forced)` на MouseEnter + `DestroyMouseoverDisplay()` на MouseExit (паттерн `AddControlTooltipManual`). Тултип — ребёнок parent-контрола, умирает вместе с ним. `forced=true` игнорирует игровую опцию tooltips.

- **У UI-контролов НЕТ метода `:IsDestroyed()`** — вызов падает с `attempt to call method 'IsDestroyed' (a nil value)`. Проверка живости контрола — глобальная функция: `if control and not IsDestroyed(control) then` (так в ConnectionDialog.lua, lobby/chatarea.lua). Найдено на краше кнопки Choose в MVP 6.

## Buff implementation matrix (audit, catalog = 35 buffs)

Источник: mod/BuffDraft/lua/buffs.lua (каталог/пул драфта), effects.lua (BuffSpecs + NotImplementedReasons).
Сверка автоматическая: 35 id каталога = 30 BuffSpecs + 5 NotImplementedReasons, орфанов нет в обе стороны;
все 25 BuffBlueprint зарегистрированы и используются. Пул драфта = весь каталог, т.е. not implemented
баффы драфтятся и при пике только логируются (no-op) — это осознанно.

Общее для всех parts-баффов: current units = да (свип на пике; 'built'-parts пропускают недостроенных,
их добирает OnStopBeingBuilt), future units = да (хуки OnCreate/OnStopBeingBuilt), guard от двойного
применения = да (HasBuffApplied per unit per part; кастомные — маркер unit.BuffDraftApplied). Отличия
отмечены в таблице.

| buffId | status | categories | current | future | guard | примечание |
|---|---|---|---|---|---|---|
| engineer_build_speed_1 | implemented | ENGINEER − COMMAND | да | да | да | x5 build rate |
| factory_build_speed_1 | implemented | FACTORY | да | да | да | x3 |
| air_speed_1 | implemented | AIR × MOBILE | да | да | да | x2 MoveMult |
| naval_armor_1 | implemented | NAVAL × MOBILE | да | да | да | x2.5 HP |
| experimentals_health_1 | implemented | EXPERIMENTAL | да | да | да | x2 HP |
| acu_regen_1 | implemented | COMMAND | да | да | да | +60 регена |
| eco_overclock_1 | implemented | STRUCTURE × (MASSPROD + ENERGYPROD) | да | да | да | x2.5 |
| radar_vision_1 | implemented | RADAR; SCOUT | да | да | да | x2 радар / x2 зрение |
| anti_air_damage_1 | implemented | ANTIAIR (оружия UWRC_AntiAir) | да | да | да | x2.5 урон |
| land_rate_of_fire_1 | implemented | LAND × MOBILE (UWRC_DirectFire) | да | да | да | x2 РоФ |
| artillery_range_1 | implemented | ARTILLERY (UWRC_IndirectFire) | да | да | да | x1.5 |
| tactical_range_1 | implemented | TACTICALMISSILEPLATFORM | да | да | да | x2; стекается с tactical_supremacy через CombinedWeaponMult |
| shield_health_1 | implemented | STRUCTURE × SHIELD | да | да | да | x2 щит |
| mobile_shields_1 | implemented | MOBILE × SHIELD | да | да | да | x2 щит |
| drone_foundry_1 | implemented | спавн у STRUCTURE × FACTORY × LAND | да* | да* | поток 1/армию | *волна каждые 45с берёт текущие фабрики; T1 танк по фракции |
| engineer_swarm_1 | implemented | спавн у STRUCTURE × FACTORY × LAND | да* | да* | поток 1/армию | *аналогично, T1 инженер каждые 60с |
| emergency_fabrication_1 | implemented | билдеры ENGINEER, цели STRUCTURE × DEFENSE | да** | да | Stacks=IGNORE + checked remove | **со следующего начала стройки; x3 build rate на время стройки |
| overcharged_shields_1 | partial | SHIELD (все с unit.MyShield) | да | да | да | x2.5 щит; перезарядка не сделана — shield spec фиксирован при создании |
| napalm_rounds_1 | partial | LAND × MOBILE (direct) + ARTILLERY (indirect) | да | да | да | +1 радиус урона; DoT не сделан — DoTTime/Pulses только в блюпринте |
| teleport_doctrine_1 | partial | ENGINEER + COMMAND + SUBCOMMANDER | да | да | да | x2 скорость; сам телепорт не сделан — нужен enhancement + UI |
| missile_storm_1 | not implemented | — | — | — | — | MuzzleSalvoSize — данные блюпринта оружия, per-instance API нет |
| orbital_lance_1 | not implemented | — | — | — | — | нужен target-point UI + кастомный страйк; TODO |
| nano_swarm_1 | partial | ALLUNITS | да | да | да | +5 реген постоянно; out-of-combat детект небезопасен |
| experimental_discount_1 | partial | билдеры ENGINEER + FACTORY, цели EXPERIMENTAL | да** | да | Stacks=IGNORE + checked remove | x2.5 build rate при стройке экспериментала; удешевление не сделано (economy — глобальный блюпринт) |
| rapid_deployment_1 | implemented | MOBILE | НЕТ (futureOnly) | да | да | x2 скорость на 60с только новым юнитам — так задумано |
| fortress_protocol_1 | implemented | STRUCTURE (HP); MOBILE (замедление) | да | да | да | x3 HP / x0.85 скорость |
| hunter_protocol_1 | implemented | MOBILE (зрение, скорость); MOBILE × RADAR (радар) | да | да | да | радар только у юнитов с радаром (иначе RadarRadius его раздаёт) |
| black_market_economy_1 | implemented | килы любых юнитов армии | да | да | флаг 1/армию | 10% mass/energy стоимости жертвы через OnKilledUnit + GiveResource |
| chain_lightning_weapons_1 | not implemented | — | — | — | — | нужны кастомные projectile/weapon скрипты; TODO |
| tactical_supremacy_1 | implemented | TACTICALMISSILEPLATFORM | да | да | да | x3 дальность + x2 build rate ракет |
| air_superiority_1 | implemented | AIR × MOBILE | да | да | да | x2 скорость, x1.5 урон, x0.75 HP |
| naval_dreadnoughts_1 | implemented | NAVAL × MOBILE | да | да | да | x3 HP, x1.5 дальность |
| radar_omniscience_1 | implemented | (COMMAND + STRUCTURE × RADAR × TECH3) × OMNI; STRUCTURE × RADAR × TECH3 | да | да | да | x3 омни, x2.5 радар |
| salvage_explosion_1 | not implemented | — | — | — | — | wreckage считается из блюпринта жертвы при смерти; со стороны баффающего API нет |
| reclaim_bonus_1 | not implemented | — | — | — | — | reclaim yield живёт на пропах/команде реклейма, per-unit API нет |

Итог: 25 implemented, 5 partial, 5 not implemented.
Баффы в каталоге без эффекта: missile_storm_1, orbital_lance_1, chain_lightning_weapons_1,
salvage_explosion_1, reclaim_bonus_1 (все логируют причину при пике).
Эффекты в коде вне каталога: нет.
