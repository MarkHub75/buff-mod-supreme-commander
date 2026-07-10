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
- **Production-баффы (`EnergyProduction`/`MassProduction`) пишут в `unit.EnergyProdAdjMod` / `unit.MassProdAdjMod` и вызывают `unit:UpdateProductionValues()`**. Это тот же путь, что используют adjacency storage bonus и cheat income, поэтому кастомный eco-бафф нельзя просто вручную держать в этих полях: следующий adjacency recalculation его перетрёт. Безопасный паттерн — отдельные BuffType для energy/mass production, плюс `UpdateProductionValues()` после late post-build кода, если hook сработал до класса структуры.
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
все 28 BuffBlueprint зарегистрированы и используются. Пул драфта = весь каталог, т.е. not implemented
баффы драфтятся и при пике только логируются (no-op) — это осознанно.

Общее для всех parts-баффов: current units = да (свип на пике; 'built'-parts пропускают недостроенных,
их добирает OnStopBeingBuilt), future units = да (хуки OnCreate/OnStopBeingBuilt), guard от двойного
применения = да (HasBuffApplied per unit per part; кастомные — маркер unit.BuffDraftApplied). Отличия
отмечены в таблице.

| buffId | status | categories | current | future | guard | примечание |
|---|---|---|---|---|---|---|
| engineer_build_speed_1 | implemented | ENGINEER − COMMAND | да | да | да | x5 build rate |
| factory_build_speed_1 | implemented | FACTORY | да | да | да | x3 |
| air_speed_1 | implemented | AIR × MOBILE | да | да | да | x1.25 MoveMult |
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
| missile_storm_1 | partial | TACTICALMISSILEPLATFORM | да | да | да | аппроксимация: x2.5 RoF (CombinedWeaponMult, стекается с range-баффами) + x2.5 build rate ракет (свой BuffType, стекается с tactical_supremacy); настоящий мульти-залп не сделан — MuzzleSalvoSize только в блюпринте |
| orbital_lance_1 | implemented | страйк по точке карты (ручное наведение) | да | да | cooldown 1/армию | АКТИВНЫЙ бафф: Activate → command mode 'ping' → клик → SIM валидирует → shield-aware DamageArea: 5 импульсов x800 r=5 за ~2с; живые купола щитов в точке сначала поглощают/блокируют урон, остаток бьёт землю и обе стороны; cooldown 90с, отмена/провал не тратят; fallback — авто-страйк; HP-дебаг за DebugAdmin |
| nano_swarm_1 | partial | ALLUNITS | да | да | да | +5 реген постоянно; out-of-combat детект небезопасен |
| experimental_discount_1 | partial | билдеры ENGINEER + FACTORY, цели EXPERIMENTAL | да** | да | Stacks=IGNORE + checked remove | x2.5 build rate при стройке экспериментала; удешевление не сделано (economy — глобальный блюпринт) |
| rapid_deployment_1 | implemented | MOBILE | НЕТ (futureOnly) | да | да | x2 скорость на 60с только новым юнитам — так задумано |
| fortress_protocol_1 | implemented | STRUCTURE (HP); MOBILE (замедление) | да | да | да | x3 HP / x0.85 скорость |
| hunter_protocol_1 | implemented | MOBILE (зрение, скорость); MOBILE × RADAR (радар) | да | да | да | радар только у юнитов с радаром (иначе RadarRadius его раздаёт) |
| black_market_economy_1 | implemented | килы любых юнитов армии | да | да | флаг 1/армию | 10% mass/energy стоимости жертвы через OnKilledUnit + GiveResource |
| chain_lightning_weapons_1 | partial | все юниты с beam-оружием (bp.BeamLifetime) | да | да | да | аппроксимация: x1.5 урон + 1.5 splash на beam/laser оружиях; настоящий arcing не сделан — нужны кастомные projectile-скрипты |
| tactical_supremacy_1 | implemented | TACTICALMISSILEPLATFORM | да | да | да | x3 дальность + x2 build rate ракет |
| air_superiority_1 | implemented | AIR × MOBILE | да | да | да | x2 скорость, x1.5 урон, x0.75 HP |
| naval_dreadnoughts_1 | implemented | NAVAL × MOBILE | да | да | да | x3 HP, x1.5 дальность |
| radar_omniscience_1 | implemented | (COMMAND + STRUCTURE × RADAR × TECH3) × OMNI; STRUCTURE × RADAR × TECH3 | да | да | да | x3 омни, x2.5 радар |
| salvage_explosion_1 | partial | килы любых юнитов армии | да | да | флаг 1/армию | 25% шанс взрыва убитого врага (DamageArea r=3, 150, без friendly fire); доп. reclaim не сделан — wreckage только в блюпринте жертвы |
| reclaim_bonus_1 | partial | билдеры ENGINEER (во время реклейма) | да | да | Stacks=IGNORE + checked remove | x2 скорость реклейма через условный BuildRate-бафф на OnStartReclaim/OnStopReclaim (reclaim rate следует за build rate); суммарный yield НЕ меняется — на него per-unit API нет |

Итог: 26 implemented, 9 partial, 0 not implemented (orbital_lance_1 → implemented после
добавления ручного наведения). Все 35 баффов каталога имеют эффект;
partial = основной эффект работает, заявленная часть пропущена и логируется при пике
(`FAF_BUFF_DRAFT: <buffId> skipped <part> because ...`).
Баффы в каталоге без эффекта: нет.
Эффекты в коде вне каталога: нет.

Дополнение (remaining buffs MVP) — подтверждённые API:
- **`brain:GetUnitsAroundPoint(category, position, radius, 'Enemy')`** — enemy-фильтр (sorianutilities.lua:689, platoon-adaptive-*.lua). Возвращает и невидимых юнитов — видимость проверять отдельно.
- **`target:GetBlip(armyIndex)` + `blip:IsSeenEver(armyIndex)`** — «армия хоть раз опознала юнит» (SimObjectives.lua:1666-1678, там же комментарий про identified). Нет блипа → армия юнит не видела.
- **`ScenarioInfo.size[1]/[2]`** — размер карты в SIM (NavGenerator.lua:138).
- **`CreateLightParticle(entity, bone, army, size, lifetime, texture, ramp)`** — SIM-глобал для вспышки (cybranprojectiles.lua:191: `CreateLightParticle(self, -1, self.Army, 7, 12, 'glow_03', 'ramp_red_06')`).
- **Beam-оружие детектится по `bp.BeamLifetime`** — DefaultBeamWeapon.lua:27 абортит setup без него, т.е. поле есть у каждого beam-блюпринта. Урон бима идёт через damage table оружия → ChangeDamage/AddDamageRadiusMod работают (CollisionBeam.lua:133 использует DamageData.DamageRadius).
- **`Unit.OnStartReclaim(self, target)` / `OnStopReclaim(self, target)`** (Unit.lua:860/892) — хукаются как OnStartBuild; скорость реклейма пропорциональна build rate юнита, поэтому условный BuildRate-бафф ускоряет реклейм, не меняя yield.

## КРИТИЧНО: хуки методов Unit обязаны пробрасывать return (source: lua/sim/Unit.lua:2838-2913, units/StructureUnit.lua:4-6, 593-598, units/FactoryUnit.lua:110-123, 428-458)
- **`Unit.OnStartBuild(self, built, order)` ВОЗВРАЩАЕТ true/false** (false — restricted unit / upgrade-exploit, Unit.lua:2851/2863/2912). `StructureUnit.OnStartBuild` проверяет: `if not UnitOnStartBuild(...) then return false end` и только ПОСЛЕ этого делает `self.UnitBeingBuilt = unitBeingBuilt` (StructureUnit.lua:595-598).
- Наш хук-враппер вызывал оригинал и **терял его return** → StructureUnit получал nil → считал старт стройки провальным → `UnitBeingBuilt` не выставлялся → `FactoryUnit.BuildingState.Main` падал на `unitBeingBuilt:HideBone(0,true)` (FactoryUnit.lua:437), `RolloffBody` — на сравнении размеров (:393), фабрика застревала в Busy и переставала строить. Ошибки в game.log: `factoryunit.lua(437): attempt to call method HideBone (a nil value)`, `factoryunit.lua(393): call expected but got table`.
- **Правило для ВСЕХ хуков-врапперов**: `local result = oldUnit.Method(self, ...) ... return result`. Плюс свой код за `pcall`, чтобы баг мода не прерывал базовый build/reclaim/kill-флоу на середине (паттерн в mod/BuffDraft/hook/lua/sim/Unit.lua). `StructureUnit` кэширует базовые методы как file-locals (строки 4-6) — но это ссылки на УЖЕ обёрнутый Unit, т.е. хук работает; проблема была только в потерянном return.
- Spawn-потоки drone_foundry_1/engineer_swarm_1 оказались НЕ виноваты — оставлены включёнными.

## Active buff framework (effects.lua, только orbital_lance_1)
- SIM API: `CanUseActiveBuff(army, buffId)`, `UseActiveBuff(army, buffId, payload)`, `GetActiveBuffSyncState()` в effects.lua. Определения — `ActiveBuffDefs[buffId] = { cooldown, use = fn(army, payload) -> ok, reason }`; состояние — `ActiveBuffState[army][buffId] = { cooldownUntil, lastUsed }`.
- Время: `GetGameTimeSeconds()` — SIM-глобал (BrainConditionsMonitor.lua:325), игровые секунды. Cooldown детерминирован, UI времени не считает: SIM-поток раз в секунду шлёт событие `{event="active", states=...}` через Sync.BuffDraft, UI показывает remaining из события.
- UI → SIM: `SimCallback BuffDraftUseActive { buffId }`; армия берётся ТОЛЬКО из `GetCurrentCommandSourceArmy()` (не из data), ownership+cooldown валидируются сим-стороной. Неудачное использование (нет цели) cooldown не заряжает.
- UI: секция активных баффов в панели (history.lua) — anchor-группа `activeArea` нулевой высоты между кнопкой Choose и history-рядами; ряды пересоздаются только при смене набора buffId (ключ-конкатенация id), иначе in-place SetText/Enable/Disable раз в секунду. Периодический update НЕ вызывает panel:Show(), чтобы не воскрешать закрытую панель.

## SupCom Lua / UI ловушки (найдено на крашах admin-панели)
- **Замыкания НЕ должны захватывать переменную for-цикла**: после завершения цикла захваченное значение становится nil (LuaPlus). Клик по кнопке, чей обработчик захватил `sideName` из `for _, sideName in {...}`, записал nil → краш «attempt to concatenate upval (a nil value)». Фикс — копия в body-local перед созданием замыкания: `local side = sideName`. Сама FAF так и делает: `local index = i` в multifunction.lua:307, construction.lua.
- **Текстур '/BUTTON/small/' НЕ СУЩЕСТВУЕТ** — во всей FAF только `/BUTTON/medium/` и `/BUTTON/large/`. `CreateButtonWithDropshadow(..., '/BUTTON/small/', ...)` рендерится как «плавающий» текст нулевого размера, по которому нельзя кликнуть (выглядит как сломанный layout).
- **Один упавший обработчик Sync-события глушит остальные события этого beat**: ProcessEvents шёл по списку без защиты, краш на «history»-обработчике съедал следующее «pending»-событие (count=0), и кнопка Open pending choice оставалась активной с count=1. Фикс — каждый dispatch за pcall + WARN.

## Buff rarity tiers (source: mod/BuffDraft/lua/buffs.lua BuffRarityTiers, draft.lua генерация)
- **legendary (8)**: orbital_lance_1, fortress_protocol_1, air_superiority_1, naval_dreadnoughts_1, tactical_supremacy_1, experimental_discount_1, drone_foundry_1, engineer_swarm_1.
- **rare (13)**: engineer_build_speed_1, factory_build_speed_1, land_rate_of_fire_1, eco_overclock_1, naval_armor_1, experimentals_health_1, overcharged_shields_1, napalm_rounds_1, missile_storm_1, nano_swarm_1, rapid_deployment_1, hunter_protocol_1, black_market_economy_1.
- **common (14)**: всё остальное (shield_health, tactical_range, air_speed, acu_regen, artillery_range, radar_vision, mobile_shields, anti_air_damage, reclaim_bonus, emergency_fabrication, teleport_doctrine, chain_lightning_weapons, radar_omniscience, salvage_explosion).
- Хранение: `BuffRarityTiers` в buffs.lua мержится в записи каталога (`buff.rarity`, дефолт common) — единый источник для SIM и UI.

Правила генерации (draft.lua, детерминированный sim RNG в фиксированном порядке):
1. Номер choice стороны = picked + pending + 1. rare/legendary доступны с choice #6 (`RareUnlockPickNumber`/`LegendaryUnlockPickNumber`).
2. Один общий **rarity pattern на тик** для обеих сторон (одинаковые редкости слотов, НЕ одинаковые баффы): слот legendary с шансом `LegendaryChancePercent` (20, максимум 1 на choice), rare — `RareChancePercent` (35), иначе common. Тир попадает в pattern, если доступен хотя бы одной стороне; неспособная сторона понижает слот с логом (`rarity downgrade ... reason=locked/cooldown/no candidates`).
3. Кулдаун legendary: после ПОЯВЛЕНИЯ legendary-опции у стороны `LegendaryOfferCooldownChoices` (3) resolved-пиков без legendary (декремент в ApplyResolvedPick, admin grant не считается). У rare кулдауна нет.
4. Кросс-сторонний avoid-set: вторая сторона по возможности не получает те же buffId в этом тике (fallback на дубликат, если кандидатов нет). No-repeat picked/pending фильтры прежние.
5. Исчерпание commons (late game): слот поднимается вверх только в уже разблокированные тиры (лог «no common candidates left»).
- UI: цвет заголовка опции — rare зелёный 'FF80FF80', legendary фиолетовый 'FFC080FF' + текстовый тег [Rare]/[Legendary] (читаемо без цвета); тултипы history и админка показывают rarity текстом.

## Balance-конфиг (mod/BuffDraft/lua/config.lua, регион «balance knobs»)
- Все балансные числа мода — named-поля в config.lua: `DraftIntervalSeconds` (300 = один выбор каждые 5 минут), `OptionsPerTick`, все множители баффов (имена совпадают с локалами effects.lua: ENGINEER_BUILD_RATE_MULT и т.д.), интервалы спавна, параметры salvage и orbital lance.
- Читатели: effects.lua (весь блок констант через nil-safe `Knob(name, default)`), hook/simInit.lua (интервал драфта), draft.lua (OptionsPerTick), buffs.lua (тексты тултипов собираются из тех же значений — правка конфига меняет и геймплей, и то, что читает игрок). Дефолты продублированы у каждого читателя → удалённое поле конфига ничего не ломает.
- Orbital lance больше не держит projectile/beam asset paths: sky projectile/beam path disabled after engine crash.
- Контроль при старте: `FAF_BUFF_DRAFT: config draftInterval=... options=...` (BeginSession) и `FAF_BUFF_DRAFT: orbital_lance config cooldown=... ticks=...` (загрузка effects.lua).

## Debug admin panel (mod/BuffDraft/lua/ui/admin.lua + config.lua)
- **Консольная команда**: своей регистрации именованных команд (`buffdraft_admin`) из мода НЕТ безопасного API — slash-команды нового чата требуют правки core-файла ChatController. Работает `ui_lua <lua>` (движковая команда, пример: keymap/debugKeyActions.lua:125): открытие панели — `ui_lua import('/mods/BuffDraft/lua/ui/admin.lua').Open()`. Fallback — кнопка Admin в панели Buff Draft (только при DebugAdmin).
- **Debug-флаг**: `DebugAdmin` в `/mods/BuffDraft/lua/config.lua` — статический файл, импортируется и UI, и SIM; SIM перепроверяет флаг в draft.AdminGrantBuff/AdminRemoveBuff, так что UI обойти его не может; одинаков на всех клиентах — desync нет.
- **Кнопка Admin owner-only, но visibility надо пересчитывать после создания панели**: `GetArmiesTable()`/nickname может быть ещё не готов в первый UI tick. Создавать кнопку по `DebugAdmin`, держать скрытой до совпадения `AdminOwnerNickname`, пересчитывать layout на sync events; `admin.Open()` и SIM callbacks всё равно проверяют owner-gate.
- **Grant** идёт тем же путём, что обычный пик (draft.ApplyResolvedPick): history + sync + ApplyPickedBuff; валидации: сторона, buffId из каталога, не picked, не висит опцией в pending choice, sides известны.
- **Remove** (effects.RemovePickedBuff): buff-парты — Buff.RemoveBuff по юнитам; custom-парты — `unapply` = тот же хелпер с обратным множителем (CombinedWeaponMult пересчитывает от блюпринта, так что apply+unapply возвращает сток; щит — floor-дрейф ±1 HP); conditional-баффы — снятие с текущих носителей + флаг; army-эффекты — `armyRemove` (kill-флаги, UnregisterActiveBuff, стоп spawn-потоков через SpawnThreadActive["buffId:army"]). НЕ откатывается: заспавненные юниты, выданные ресурсы, уже идущие 60с баффы rapid_deployment (истекают сами).
- После remove buffId убирается из PickedHistory → снова может выпасть в драфте или быть выдан заново (armyApplied сбрасывается для повторного armyApply).
- **Owner-gate админки** (`AdminOwnerNickname` в config.lua): UI — `GetArmiesTable()` возвращает `{ armiesTable = { [i] = { nickname, civilian, ... } }, focusArmy = n }` (score.lua:409, поле nickname:299); ник локального игрока = `armiesTable[focusArmy].nickname`. SIM — `ArmyBrains[senderArmy].Nickname` (заполняется в OnCreateArmyBrain), senderArmy строго из GetCurrentCommandSourceArmy → UI-обход невозможен. Пустая строка в конфиге отключает ник-проверку (остаётся DebugAdmin). Ограничение: ник наблюдателя/реплея не проверяется — но такие отправители отсекаются раньше по nil senderArmy.
- **Гонка respawn-потоков исправлена generation-токеном**: bool-флаг позволял remove+re-grant внутри одного WaitSeconds-интервала оставить ДВА потока спавна; теперь и remove, и повторный grant инкрементируют счётчик поколения, старый поток видит чужое поколение и выходит.

## Target-point UI (паттерн ping-кнопок, source: lua/ui/game/multifunction.lua, commandmode.lua, ping.lua)
- **Command mode `'ping'`** (commandmode.lua:99) — не выдаёт приказов, «passes data from StartCommandMode to EndCommandMode». Запуск: `import('/lua/ui/game/commandmode.lua').StartCommandMode('ping', modeData)` (multifunction.lua:326-333, PingClickHandler); `modeData.cursor` — курсор на время режима ('RULEUCC_Guard'/'RULEUCC_Move'/'RULEUCC_Attack' у ping-кнопок). Свои поля в modeData проходят насквозь.
- **Конец режима**: зарегистрировать `CommandMode.AddEndBehavior(fn, identifier)` (commandmode.lua:159) — fn(mode, data) зовётся на конец ЛЮБОГО command mode, свои режимы метить своим полем в data. Левый клик по миру завершает 'ping' с `data.isCancel = false`, отмена (Esc) — с `isCancel = true` (commandmode.lua:196-205; условие из multifunction EndBehavior: `mode == 'ping' and data.pingLocation and not data.isCancel`).
- **Позиция клика**: в end behavior вызвать `GetMouseWorldPos()` (UI-глобал; ping.lua:104, DoPing) — мышь ещё на точке клика. NaN-проверка каждой координаты `v ~= v` (клик мимо мира), как в DoPing:105-110.
- **SIM-высота точки**: `GetSurfaceHeight(x, z)` — SIM-глобал (area-attack-ground-order.lua:65), даёт поверхность (вода поверх дна), лучше GetTerrainHeight для страйков.
- Точка от UI — сырой payload: SIM обязан валидировать типы и границы карты (`ScenarioInfo.size`), армию брать только из GetCurrentCommandSourceArmy.
- ~~Ограничение: у точечного страйка нет вспышки~~ РЕШЕНО: **FX в произвольной точке = barebone entity**: `local Entity = import('/lua/sim/entity.lua').Entity; local e = Entity(); Warp(e, pos)` → `CreateEmitterAtEntity(e, army, template)` + `CreateLightParticle(e, -1, ...)`, entity уничтожить через пару секунд. Это паттерн самой FAF: EffectUtilities.lua:1069 («Using a barebone entity to position effects»), simInit.BeginSessionEffects:548. Шаблоны взрывов: `import('/lua/EffectTemplates.lua').ExplosionLarge` (список emitter-строк, EffectTemplates.lua:152; используется в defaultexplosions.lua).
- **DamageArea 'Normal' по точке ПОГЛОЩАЕТСЯ куполом щита** — ровно поэтому в /lua/sim/DamageArea.lua есть спец-вариант для нюков «to bypass the bubble damage absorbation of shields». Страйк по щитованной базе снимает HP щита, юниты не страдают — выглядит как «ничего не произошло». Дебаг-лог до/после HP (за DebugAdmin) показывает это как «no units affected».
- `brain:GetUnitsAroundPoint(cat, pos, r, 'Ally')` — alliance-параметр 'Ally' тоже валиден (sorianutilities.lua:913).

## Скриптовые снаряды и лучи (orbital lance crash finding; source: game.log + engine/Sim/Entity.lua, lua/sim/Projectile.lua, shield.lua)
- **ОТКЛЮЧЕНО для orbital_lance_1:** barebone `Entity():CreateProjectile(...)` + `proj:PassDamageData(...)` and `AttachBeamEntityToEntity(...)` between temporary bare entities reached `FAF_BUFF_DRAFT: orbital_lance_1 debug units before...` and then crashed ForgedAlliance.exe with `EXCEPTION_ACCESS_VIOLATION 0xc0000005`, no Lua traceback. Root hypothesis: the engine projectile/beam path expects a real launcher/weapon owner or longer-lived entities; the crash is native, so `pcall` cannot make it safe.
- **Rule:** no orbital_lance_1 sky projectile/beam path unless proven safe from FAF references and in-game crash testing. Current MVP uses boring `DamageArea` with manual shield detection instead.
- Щит-объект: `shield.Size` — ДИАМЕТР купола (shield.lua:185), `shield:GetPosition()`; проверка «точка под куполом» = 2D-дистанция ≤ Size/2. `Shield:IsUp()` (shield.lua:800) gates active shields. `Shield.ApplyDamage(instigator, amount, vector, dmgType, doOverspill)` (shield.lua:529) safely damages shield HP when an instigator unit is available.

Дополнение (salvage explosion MVP): **`DamageArea(instigator, location, radius, damage, damageType, damageFriendly, damageSelf)`**
— SIM-глобал, используется в DefaultDamage.lua:99, EffectUtilities.lua:1340, defaultcomponents.lua:565.
`damageFriendly=false` не трогает союзников instigator'а. В `Unit.OnKilledUnit` жертва ещё валидна
(`GetPosition()` работает) — хук вызывается из `OnKilled` до деструкции.

## Передача юнитов между армиями (AI control tool; source: lua/SimUtils.lua, SimCallbacks.lua, engine/User.lua)
- **`SimUtils.TransferUnitsOwnership(units, toArmy, captured, noRestrictions)`** (SimUtils.lua:246) —
  штатный путь передачи юнитов: им пользуются diplomacy «give units» (`GiveUnitsToPlayer`, :736,
  callback SimCallbacks.lua:162), full share при смерти и capture (Unit.lua:1010). Переносит
  ветеранство/апгрейды/боезапас silo; **юнит ЗАМЕНЯЕТСЯ новым объектом** (старый умирает — внешние
  ссылки на юнит увидят `Dead`), возвращает список новых юнитов. Сам фильтрует: attached/дочерние,
  недостроенные, в процессе капчура, `INSIGNIFICANTUNIT`; сортирует по ценности.
- Vanilla-валидация дающей стороны: `OkayToMessWithArmy(army)` (может ли текущий command source
  управлять армией) + `IsAlly(owner, toArmy)` — для «забрать у союзного AI» OkayToMessWithArmy НЕ
  подходит (обычный игрок не управляет армией союзника), нужна своя валидация в моде.
- **`GetEntityById(id)`** — SIM-глобал (SimCallbacks.lua:34, паттерн `SecureUnits`:88): entity id из
  UI → юнит в симе. Id юнита на UI-стороне: `unit:GetEntityId()`, у ховера — `GetRolloverInfo().entityId`
  (+ `.armyIndex`; класс RolloverInfo в keymap/selectedinfo.lua:1).
- **`GetSelectedUnits()` (UI) возвращает только СВОИ юниты** — движок не даёт выделять юнитов
  союзника, поэтому UX «выделил юнитов AI → забрал» невозможен без переключения армии. Рабочая
  альтернатива для «забрать у AI»: клик по точке через command mode 'ping' (паттерн orbital lance)
  → SIM сам собирает юниты союзного AI вокруг точки (`GetUnitsAroundPoint(cat, pos, r, 'Ally')`).
- `ScenarioInfo.Options.ManualUnitShare` ('none'/'no_builders') ограничивает vanilla give-путь —
  прямой вызов TransferUnitsOwnership опции лобби не проверяет (мод сам решает, что разрешено).

## Warning triage notes (source: warnings folder + references/fa-develop)
- `LazyVar` circular dependency at `layouthelpers.lua:240/254` means a control is evaluating `Left = Right - Width` and `Right = Left + Width` recursively. In BuffDraft UI this can happen when rows anchor to `activeArea.Right()` via `AtRightIn` while the parent area is stretched only by opposite edges. Fix used in `history.lua`: give `activeArea` an explicit `Width` from `client.Width() - padding`, then let its `Right` derive from `Left + Width`.
- `tech-ai.lua:498`, `platoon.lua:1528`, `platoon.lua:3337`, and `*AI WARNING: ... Invalid location` are core AI manager/platoon failures. BuffDraft does not mutate `BuilderManagers`, but `EnableAIDirector=true`, `AIDirectorOrdersEnabled=true`, and `EnableAIControl=true` can indirectly stress AI state. `AIControl` currently uses `LAND * MOBILE`, so it can transfer allied AI engineers unless `ENGINEER` is explicitly excluded.
- `StructureUnit.lua:785/824` adjacency warnings happen before adjacency buffs are applied, while writing `AdjacentUnits[adjacentUnit.EntityId]`. This points to an engine/core adjacency edge case with a bad adjacent entity, not to BuffDraft buff blueprints directly.
- `shield.lua:606` under `projectile.lua` is projectile damage hitting shield code with an invalid/non-entity instigator. Current BuffDraft orbital lance uses `DamageArea` and manual `shield:ApplyDamage`, not `CreateProjectile`/`PassDamageData`; without full `game.log` timing this warning is not proven to be from BuffDraft.
- AI Director must select orderable units from `unit.PlatoonHandle.ArmyPool`, not merely from `brain:GetListOfUnits`: `IsIdleState()` can be briefly true inside a running stock platoon. The FAF pattern is `MakePlatoon` + `AssignUnitsToPlatoon` before issuing orders, followed by `PlatoonDisband` when the custom task ends. Direct orders to arbitrary brain units can race/corrupt stock platoon plans and manifest later as failures in `platoon.lua` or builder managers.
- Multi-tick damage abilities must revalidate their instigator with `IsEntity`/`Dead` on every pulse. `ChangeUnitArmy` replaces the entity and deaths destroy it; retaining the original unit across `WaitSeconds` can feed a stale object into `DamageArea`/shield APIs.
- `StructureUnit.OnAdjacentTo`/`OnNotAdjacentTo` index adjacency tables by `EntityId` without validating it. External-factory completion can surface an adjacent object with no id; a small `StructureUnit` wrapper should skip only those malformed callbacks and preserve the original return for valid ones.
- `AirUnit.OnImpact('Water')` assumes `colliderProj:Destroy()` exists, while XRA0105 can impact before its crash state is initialized. A unit-specific hook can recover the blueprint `DeathImpact` weapon and supply a no-op collider only for that missing-state call. Delayed `Sinker.StartSinking` also needs a destroyed-target check and a cleanup fallback when `AttachBoneTo` fails.

## FAF keybind hazards (source: references/fa-develop/fa-develop/lua/keymap/defaultKeyMap.lua, keyactions.lua, keydescriptions.lua)
- `Ctrl-F` in all stock FAF presets (`defaultKeyMap.lua`, `hotbuildKeyMap.lua`, `alternativeKeyMap.lua`) is bound to `cap_frame`, described as "Take a screen shot". The action is the engine console command `Dump_Frame`, not a Lua function and not BuffDraft code. If it freezes/crashes on a machine, the practical workaround is to unbind/remap "Take a screen shot" in FAF keybindings or remove/change the `['Ctrl-F'] = 'cap_frame'` user keymap entry in `game.prefs`.
