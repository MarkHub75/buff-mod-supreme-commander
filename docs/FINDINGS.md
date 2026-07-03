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
- **У UI-контролов НЕТ метода `:IsDestroyed()`** — вызов падает с `attempt to call method 'IsDestroyed' (a nil value)`. Проверка живости контрола — глобальная функция: `if control and not IsDestroyed(control) then` (так в ConnectionDialog.lua, lobby/chatarea.lua). Найдено на краше кнопки Choose в MVP 6.
