# AI Pressure Director — research + scaffold

Цель: после 30 минут на Dual Gap сделать AI-союзников Артёма полезнее — не переписывая
Sorian AI, а точечно дожимая простаивающие армии SIM-командами.

Статус: **MVP D3 (land waves + experimental missions + forward fortify,
dry-run по умолчанию)**. Файлы в `lua/ai_director/`:
- `director.lua` — поток: survey-лог состава AI-армий стороны Artem раз в
  `AIDirectorIntervalSeconds` после `AIDirectorStartSeconds`, затем per-army тики
  модулей приказов (каждый за pcall);
- `targeting.lua` — общий выбор цели (скоринг структур Марка) для D1/D2;
- `land_waves.lua` — D1: сбор волны idle land combat и атака;
- `experimental_mission.lua` — D2: личные миссии idle land эксперименталов;
- `fortify.lua` — D3: idle инженеры укрепляют базу и mex-кластеры.
При `AIDirectorOrdersEnabled = false` всё считается и логируется, но ни один
приказ не выдаётся (dry-run).

Текущий config выставлен под **real-orders smoke test**: `AIDirectorStartSeconds
= 60`, `AIDirectorIntervalSeconds = 60`, `AIDirectorOrdersEnabled = true`. После
обкатки вернуть `AIDirectorStartSeconds = 1800` и решить судьбу OrdersEnabled.

## D1: staged land waves (lua/ai_director/land_waves.lua)

Волна (per AI армия):
- Кандидаты: `GetListOfUnits(WaveCat, idle=true)`, WaveCat = LAND×MOBILE −
  ENGINEER − COMMAND − EXPERIMENTAL − TRANSPORTATION; достроенные, не Attached,
  не из активной волны. Сортировка детерминированная: масса desc, entityId asc.
- Late game (>= `AIDirectorLateGameSeconds`, 2400с): в волну попадает максимум
  `AIDirectorT1SpamLimit` (5) юнитов TECH1 — отсев слабого T1-спама
  (лог `late-game filtered weak_t1=N`).
- Пороги: >= `AIDirectorMinWaveUnits` (12) юнитов И >= `AIDirectorMinWaveMass`
  (2000) суммарной build-cost массы; больше `AIDirectorMaxWaveUnits` (40) не
  берём (лишние копятся дальше). Ниже порога — только лог, никаких приказов
  (никаких одиночных самоубийств).
- Cooldown: `AIDirectorWaveCooldownSeconds` (180с) на армию после выданной волны;
  одновременно живёт максимум одна волна на армию.

Выбор цели (детерминированная эвристика, честная по intel):
- Кандидаты — достроенные STRUCTURE армий Марка, которые эта AI-армия хоть раз
  видела (`GetBlip(army)` + `blip:IsSeenEver(army)`, за pcall).
- Базовая ценность по классу (первый матч): gameender (T3 arti / NUKE silo /
  experimental structure) 400 → factory 250 → mex/massfab 150 → energy 120 →
  прочие структуры 40.
- Штраф за оборону: масса видимых (intel-aware `GetUnitsAroundPoint(...,'Enemy')`)
  PD/indirect-defense/щитов (без стен и AA) в радиусе
  `AIDirectorTargetDefenseRadius` (40); score = value − threat/10. Скан обороны
  только у топ-12 по ценности.
- Гейты в порядке score: threat >= масса волны × `AIDirectorMaxTargetThreatFactor`
  (0.5) → high_threat (избегаем killzone); `NavUtils.CanPathTo('Land', wavePos,
  targetPos)` ложь → no_path. Первый прошедший — цель. Никто не прошёл → skip
  (prefer no order). Nav mesh: `NavUtils.Generate()` один раз при активации
  (no-op, если AI-брейны его уже построили).
- Приказ: `IssueClearCommands` (выбранные и так idle) + `IssueAggressiveMove` на
  точку цели. Один приказ на волну — без per-tick спама.

Stuck safety (M28-идея, счётчик вместо спама):
- Волна трекается по units/цели; прогресс = уменьшение минимальной дистанции до
  цели. Ближе 30 — считается «дерутся у цели», не stuck.
- Нет прогресса `AIDirectorStuckTicks` (3) тика подряд → один retarget
  (ClearCommands + повторный AggressiveMove выжившим); снова stuck → release
  (ClearCommands, юниты возвращаются в пул сбора) + свежий wave-cooldown, иначе
  освобождённые юниты на следующем тике ушли бы новой волной на ту же
  детерминированную цель (бесконечный цикл приказов). Больше волна не трогается.
- Волна снимается, когда все юниты мертвы или все снова idle (дошли/добили);
  завершение без stuck cooldown не продлевает — следующая волна не задерживается.
- В логах волна имеет номер (`wave=N` в issued/stuck) для сопоставления событий.

Тест dry-run (по умолчанию): `AIDirectorStartSeconds = 60` для скорости, катка с
AI, в game.log смотреть `wave candidate` → `target score` → `dry-run wave` и
причины `skipped wave` (below_threshold / cooldown / no_target / high_threat /
no_path). Приказов быть не должно.
Тест реальных приказов: то же + `AIDirectorOrdersEnabled = true`; смотреть
`issued land wave`, поведение волны в игре, `wave stuck ... action=retarget/release`.

## D2: experimental missions (lua/ai_director/experimental_mission.lua)

- Кандидаты: idle достроенные `EXPERIMENTAL × LAND × MOBILE` (не Attached), у
  которых нет активной миссии; воздушные/морские эксперименталы не трогаем.
  Детерминированный порядок: масса desc, entityId asc.
- Каждому — независимая миссия: цель из общего `targeting.SelectTarget` с
  «бюджетом» = масса самого экспериментала и мягким порогом
  `AIDirectorExperimentalThreatFactor` (1.0 — экспериментал танкует PD, поэтому
  оборона до его собственной массы допустима); слой пути — из
  `bp.Physics.MotionType` юнита: RULEUMT_Amphibious/AmphibiousFloating →
  'Amphibious' (GC/Monkeylord/Megalith ходят по дну), RULEUMT_Hover → 'Hover',
  иначе 'Land' (Fatboy — не амфибия, для него 'Amphibious'-проверка приняла бы
  недостижимые цели). Приказ — один `IssueClearCommands` + `IssueAggressiveMove`.
- Stuck safety как в D1, но per-unit: дистанция до цели не сокращается
  `AIDirectorStuckTicks` тиков (и юнит дальше 35 от цели) → один retarget, снова
  stuck → release (юнит возвращается в пул) + личный cooldown
  `AIDirectorWaveCooldownSeconds`, иначе юнит немедленно получил бы новую миссию
  на ту же детерминированную цель (лог `skipped ... reason=release_cooldown`).
  Миссия снимается, когда юнит мёртв или снова idle (дошёл/добил).
- Wave-cooldown'а нет: миссия «одна на юнита», спама нет по построению.
- Dry-run: `dry-run experimental mission army=... unit=... target=...`; реальные:
  `experimental mission ...`, отказ: `skipped experimental ... reason=...`.

## D3: forward fortify (lua/ai_director/fortify.lua)

Кто строит: idle достроенные инженеры AI-армий (MOBILE × ENGINEER − COMMAND −
POD − INSIGNIFICANT; `ENGINEER - POD` — идиома самой FAF, sorianutilities.lua:913),
не Attached; порядок — tech desc, entityId asc. Максимум
`AIDirectorFortifyMaxEngineersPerTick` (3) задач на армию за проход; проход раз в
`AIDirectorFortifyIntervalSeconds` (90с) после `AIDirectorFortifyStartSeconds`
(1200с) — свой темп внутри тика директора, без отдельного потока.

Точки укрепления: база (`GetArmyStartPos`) + по одной точке на кластер своих
достроенных мексов (дедупликация позиций по сетке 32; сортировка ключей —
детерминизм). Staging-точек у D1 нет (волны копятся на месте), chokepoint-API
нет — обе идеи пропущены осознанно. После выдачи задачи точка получает cooldown
`AIDirectorFortifyAreaCooldownSeconds` (300с).

Пакет обороны (первый непокрытый пункт — одна задача одному инженеру):
radar (1 в радиусе 30) → AA (2 в 24) → PD (2 в 24) → TMD ANTIMISSILE×TECH2,
чтобы SMD не засчитывался (1 в 24, tech≥2) → shield (1 в 24, tech≥2; T3
инженер сначала пробует T3ShieldDefense, fallback T2). «Уже есть» считается
intel-честно по союзным юнитам (`GetUnitsAroundPoint(...,'Ally')`) — оборону
союзника не дублируем; недостроенные тоже считаются.

Build-путь (FAF-нативный): `brain:DecideWhatToBuild(eng, buildingType,
BuildingTemplates[faction])` (CAiBrain.lua:101) → фракционно/техово верный
blueprint; `brain:CanBuildStructureAt(bpId, pos)` (CAiBrain.lua:71) по
детерминированной сетке офсетов вокруг точки (до ±17) → первое валидное место;
`IssueBuildMobile({eng}, pos, bpId, {})` (engine/Sim.lua:768).
`AIExecuteBuildStructure` отвергнут: завязан на builder-manager данные Sorian и
зовёт `GetFocusArmy()` из sim-кода.

Dry-run: `fortify planned structure=... pos=...`; реальные приказы:
`fortify candidate` → `fortify issued army=... eng=... structure=...`;
отказы: `fortify skipped reason=no_engineer/no_build_api/no_spot/cooldown/duplicate`.

Риски D3: инженер из пула может быть перехвачен Sorian между нашим приказом и
его исполнением (разовый конфликт); `CanBuildStructureAt` даёт false positives —
неудачный приказ просто вернёт инженера в idle до следующего прохода; пакет
строится по одному зданию за проход — застройка площадки размазана по времени.

Риски D1:
- Sorian может забрать idle-юниты в свой платун после нашего приказа (юнит
  перестанет быть idle — мы его не перехватим обратно; конфликт приказов
  разовый, не циклический).
- `GetListOfUnits(idle)` включает юнитов на транспортных площадках/в очередях —
  отфильтрованы только Attached; редкие ложные включения возможны.
- Оценка обороны не видит мобильные армии Марка на пути волны — волна может
  встретить полевую армию; смягчено порогом массы и aggressive move.
- T1 фильтр по категории TECH1 груб (отсеет и полезный T1 мобильный AA в волне).

## Изоляция (контракт удаляемости)

- Весь код директора — только в `mod/BuffDraft/lua/ai_director/` (сейчас один
  файл `director.lua`; будущие модули — рядом в этой папке).
- Внешние точки подключения ровно три:
  1. `lua/config.lua` — `EnableAIDirector` + кнобы с префиксом `AIDirector*`;
  2. `hook/lua/simInit.lua` — один guarded-вызов: `if config.EnableAIDirector
     then import('/mods/BuffDraft/lua/ai_director/director.lua').Start(sides)`.
     Флаг гейтит сам import, поэтому при выключенном флаге папка не читается;
  3. этот документ.
- Полное удаление части 2 = удалить папку `lua/ai_director/` и поставить
  `EnableAIDirector = false`. Никакой buff/draft/effects/UI файл не имеет права
  импортировать что-либо из `ai_director/`.
- Контрольные логи: `FAF_AI_DIRECTOR: loaded from lua/ai_director` (import) и
  `FAF_AI_DIRECTOR: disabled by config` (флаг выключен).

Лог-формат:
```
FAF_AI_DIRECTOR: army=<idx> ai=<nick> land=<n> landIdle=<n> transports=<n> experimentals=<n> experimentalsIdle=<n> engineers=<n> engineersIdle=<n>
```

## Подтверждённые API (references/fa-develop/fa-develop)

- FAF_AI_DIRECTOR: API found armies-of-side via mod hook simInit (BuffDraftSides из slot detection); human vs AI = `brain.BrainType == 'Human' | 'AI'` (уже в FINDINGS, aibrain.lua OnCreateArmyBrain).
- FAF_AI_DIRECTOR: API found idle-units via `brain:GetListOfUnits(category, needToBeIdle)` (engine/Sim/CAiBrain.lua:337; третий параметр requireBuilt НЕ работает — фильтровать `GetFractionComplete() < 1` вручную). Per-unit: `unit:IsIdleState()` (engine/Sim/Unit.lua:369), `unit:IsUnitState('Busy'|'TransportLoading'|'Attached')` (Unit.lua:400).
- FAF_AI_DIRECTOR: API found group-orders via engine/Sim.lua: `IssueMove(units, pos)` (:888), `IssueAggressiveMove(units, target)` (:743, target = Unit|Vector), `IssueAttack(units, target)` (:750), `IssuePatrol(units, pos)` (:917), `IssueClearCommands(units)` (:790, мгновенно), `IssueGuard(units, target)` (:874). Все берут таблицу юнитов, возвращают SimCommand.
- FAF_AI_DIRECTOR: API found transports via `IssueTransportLoad(units, transport)` (engine/Sim.lua:998) + `IssueTransportUnload(transports, position)` (:1005). Рабочие паттерны: lua/AI/aiutilities.lua `GetTransports` (:1634) — фильтр свободного транспорта `categories.TRANSPORTATION - categories.uea0203`, `not IsUnitState('Busy')`, `not IsUnitState('TransportLoading')`, `table.empty(unit:GetCargo())`, `GetFractionComplete() == 1`; `UseTransports` (:1753) — полный цикл load→move→unload. M28AI (references/M28AI-main/.../M28Orders.lua:1795) оборачивает `IssueTransportLoad` в pcall — движок может кинуть ошибку на невалидной паре юнит/транспорт; копировать pcall.
- FAF_AI_DIRECTOR: API found enemy-base via `markBrain:GetArmyStartPos()` → x, z (engine/Sim/CAiBrain.lua:188) и `brain:GetStartVector3f()` (используется в lua/aibrains/base-ai.lua:391). Живые цели: `brain:GetUnitsAroundPoint(cat, pos, radius, 'Enemy')` (CAiBrain.lua:430, intel-aware; уже в FINDINGS).
- FAF_AI_DIRECTOR: API found pathability via lua/sim/NavUtils.lua: `CanPathTo(layer, origin, destination)` (:603, layer = 'Land'|'Water'|'Amphibious'|...), `GetLabel(layer, pos)` (:971, сравнение label'ов = «в одной наземной зоне»); engine-вариант `unit:CanPathTo(position)` (engine/Sim/Unit.lua:110). Это решает «идти пешком или грузить в транспорт».
- FAF_AI_DIRECTOR: API found engineer-build via `IssueBuildMobile(units, position, blueprintID, {})` (engine/Sim.lua:768, применяется ≥3 тика) и высокоуровневый `AIExecuteBuildStructure(aiBrain, builder, buildingType, closeToBuilder, relative, buildingTemplate, baseTemplate, ...)` (lua/ai/aibuildstructures.lua:119) + `brain:DecideWhatToBuild(builder, 'T2GroundDefense', buildingTemplate)` (CAiBrain.lua:101) — фракционно-независимый выбор блюпринта по BuildingTemplates.
- FAF_AI_DIRECTOR: API found experimentals via `categories.EXPERIMENTAL` + те же Issue*-приказы.
- FAF_AI_DIRECTOR: API found defeated-check via `ArmyIsOutOfGame(armyIndex)` (engine/Sim.lua:67).
- FAF_AI_DIRECTOR: API found pool-platoon via `brain:GetPlatoonUniquelyNamed('ArmyPool')` (CAiBrain.lua:378); в skirmish-инициализации pool AI выключен (`poolPlatoon:TurnOffPoolAI()`, lua/aibrains/base-ai.lua:363-368) — idle-юниты в пуле реально «ничьи». `brain:MakePlatoon(name, plan)` (:461) + `brain:AssignUnitsToPlatoon(platoon, units, squad, formation)` (:34) — забрать юниты в свой платун, чтобы менеджер платунов их не растаскивал.

## Отсутствующие / неподтверждённые API

- FAF_AI_DIRECTOR: API missing stuck-with-orders detection reason=прямого API нет; юнит с приказом, упершийся в берег, не «idle». M28 решает трекингом позиции между тиками — для директора достаточно idle-only + свой трекинг позиций позже.
- FAF_AI_DIRECTOR: API missing non-interference guarantee reason=Sorian platoon builder может забрать pool-юниты в новый платун ПОСЛЕ нашего приказа и перекомандовать. Гипотеза-митигация: свой платун через MakePlatoon+AssignUnitsToPlatoon (или переиздание приказов каждый тик) — требует проверки в реальной игре, в коде гарантии не найдено.
- FAF_AI_DIRECTOR: API missing per-order ownership check reason=Issue* не проверяют армию юнита относительно «отправителя» (SIM-код всесилен) — фильтр «только AI армии стороны Artem, без COMMAND» обязан жить в самом директоре.

## Риски

- Приказы юнитам живых Sorian-платунов = война приказов (платун перекомандует). Трогать только idle (пул).
- `GetListOfUnits` не учитывает intel — для своих армий ок; для целей Mark использовать start pos + `GetUnitsAroundPoint(..., 'Enemy')`, чтобы не читерить знанием.
- Транспортный цикл легко теряет юниты (транспорт умер в пути) — каждая стадия с таймаутом и pcall (паттерн aiutilities.UseTransports).
- ACU несёт ENGINEER и COMMAND — во всех категориях директора COMMAND вычтен.

## M28AI findings

Источник: `references/M28AI-main/M28AI-main` (lua/AI/*.lua). Прочитано:
M28Orders.lua (order-трекинг, stuck-детект), M28Land.lua (зоны, threat, рейдеры,
эксперименталы — по функциям), M28Overseer.lua (транспортный ferry-цикл),
M28UnitInfo.lua (threat rating), M28Engineer.lua (action-система, обзор).

- FAF_AI_DIRECTOR: M28AI finding license=**CC BY-NC-SA 4.0** (LICENSE в корне).
  Наш мод приватный и некоммерческий — использование ок; но скопированный код
  делает мод Adapted Material: при любом расшаривании — та же лицензия +
  атрибуция. Вывод: **идеи и паттерны берём свободно (идеи не копирайтятся),
  код не копируем**; если когда-то очень нужен маленький хелпер — переписывать
  своими словами под наш стиль, а не вставлять.
- FAF_AI_DIRECTOR: M28AI finding architecture: M28 вообще НЕ использует платуны —
  юниты приписываются к «land zones» (плато/зоны из nav-меша, M28Map), каждая
  зона управляется своим циклом `ManageSpecificLandZone` → `ManageCombatUnitsInLandZone`
  (M28Land.lua:11559/4481). Подтверждает наш выбор: прямые Issue*-приказы юнитам
  вне платунов — рабочая модель, платуны не обязательны.
- FAF_AI_DIRECTOR: M28AI finding order-dedup: все приказы идут через обёртки
  M28Orders (`IssueTrackedMove` и т.п.), которые хранят последний приказ на
  юните и НЕ переиздают его, если тип совпал и цель сместилась < порога
  (M28Orders.lua:389). Идея для D1: хранить на юните `unit.BuffDraftDirector =
  { order, target, time }` и не спамить одинаковыми приказами каждый тик.
- FAF_AI_DIRECTOR: M28AI finding non-interference: «занятые» юниты помечаются
  флагом `refbSpecialMicroActive` + время сброса `refiGameTimeToResetMicroActive`
  (M28Overseer.lua:4026-4036) — остальная логика такие юниты не трогает. Идея:
  наш маркер на юните защищает от повторного захвата директором; от Sorian он
  не защищает, но Sorian pool AI выключен (см. выше).
- FAF_AI_DIRECTOR: M28AI finding stuck-detect: НЕТ движкового API — счётчик на
  юните: раз в тик, если дистанция до цели почти не изменилась, `+1..+5`, при
  сумме >= 10 юнит считается stuck → сброс приказов и переиздание
  (M28Orders.lua:346-414, refiPatrolStuckCount; для инженеров
  refiMoveAndBuildStuckCount >= 5, :575-593). Мегалиты стакались с валидными
  приказами на дистанции ~8.6 — порог «дошёл» брать ~12.
- FAF_AI_DIRECTOR: M28AI finding transport-ferry (M28Overseer.lua:3960-4090):
  цикл = выбрать свободный транспорт (built, без micro-флага) → `IssueTrackedMove`
  транспорта к грузу до дистанции < 15 → `IssueTransportLoad` → ждать
  `cargo:IsUnitState('Attached')`, **переиздавая load каждые 30с** (движковый
  приказ тихо умирает) → `IssueTransportUnload` в цель → после отцепки move-приказы
  грузу. Перед погрузкой — проверка зоны на enemy GroundAA/корабли через
  `GetUnitsAroundPoint` (:3973). Load-приказы у M28 и в pcall (M28Orders.lua:1795).
- FAF_AI_DIRECTOR: M28AI finding threat-rating: `M28UnitInfo.GetCombatThreatRating
  (tUnits, ...)` (:712) — по сути **масса юнитов** как прокси силы (bJustGetMassValue),
  с вариантами direct-fire/indirect/AA. Решение «атаковать или копить»:
  `CompareNearbyAlliedAndEnemyLandThreats` (M28Land.lua:13776) суммирует ally/enemy
  DF-threat по своей и соседним зонам и сравнивает с порогами и коэффициентами
  (напр. net enemy threat у базы >= 800 массы → приоритет производства). Идея для
  D1: наш порог = суммарная масса собранной волны vs масса врага по пути.
- FAF_AI_DIRECTOR: M28AI finding staging/rally: у каждой зоны есть rally points
  (`GetNearestLandRallyPoint`/`RefreshLandRallyPoints`, M28Land.lua:1868/2060);
  юниты не идут в атаку поодиночке — отступают/копятся на rally и выдвигаются,
  когда сравнение threat в пользу своих. Дальняя цель ревизится на промежуточную
  (`ReviseTargetLZIfFarAway`, :1833) — не маршировать через полкарты одним приказом.
- FAF_AI_DIRECTOR: M28AI finding experimental-attack: атакующий экспериментал
  регистрируется в зоне (`RecordAttackingExperimental`, M28Land.lua:14391) и
  окружение подтягивается его поддерживать (`HaveAttackingExperimentalToSupport`,
  :14408 — свежесть отметки 30с, близость DF-врагов). Т.е. экспериментал — якорь
  отдельной «миссии», не часть общей волны.
- FAF_AI_DIRECTOR: M28AI finding engineer-defense: инженерами управляет
  action-система (`refActionBuildAA = 32` и десятки других, M28Engineer.lua:120,
  таблицы категория/приказ на action) — целиком завязана на зоны/команды M28,
  тащить нельзя. Для нас правильный путь — FAF-нативный `AIExecuteBuildStructure`
  + `DecideWhatToBuild` (уже подтверждён выше).

### Integration plan

| Что | Решение |
|---|---|
| Zone/threat framework, M28Map, M28Team, action-система инженеров | **не тащить** — тысячи строк взаимозависимостей (M28Engineer 2.1 MB, M28Land 1.5 MB), проще и безопаснее свои 3 числа |
| Идеи: order-dedup, stuck-счётчик, micro-флаг занятости, load-reissue 30с, staging по threat-порогу, экспериментал как отдельная миссия | **брать как идеи**, реализовывать заново в нашем стиле |
| Копирование кода as-is (даже маленьких хелперов) | **не копировать**: CC BY-NC-SA заражает мод ShareAlike-обязательствами при расшаривании; всё нужное — тривиальные циклы поверх подтверждённых FAF API |
| FAF-нативные утилиты (aiutilities.UseTransports-паттерн, AIExecuteBuildStructure, NavUtils) | **использовать напрямую** — это код самой FAF, доступен из мода через import |

## Предлагаемый порядок MVP (пересмотрен после M28AI)

1. **MVP D0 (сделан)**: survey-логи. Погонять катку >30 мин, посмотреть реальные числа landIdle/transports.
2. **MVP D1 (сделан, dry-run по умолчанию)** — staged land waves, детали в секции D1 выше. Исходный план:
   - **gather**: idle land combat (без Attached/COMMAND) → `IssueMove` на staging point
     (точка между базой AI и базой Марка на своей стороне; для старта — смещение от
     GetArmyStartPos AI в сторону Марка, позже — rally по nav-меш label);
   - **strength threshold**: суммарная масса собранной волны (`bp.Economy.BuildCostMass`)
     >= `AIDirectorWaveMassThreshold` — только тогда волна выдвигается
     (`IssueAggressiveMove` к базе Марка), и только те юниты, для кого
     `NavUtils.CanPathTo('Land', pos, target)` истинно;
   - **wave cooldown**: `AIDirectorWaveCooldownSeconds` между волнами одной армии;
   - **no single-unit suicide**: юниты ниже порога остаются копиться на staging;
   - **order-dedup**: маркер на юните (приказ+цель+время), не переиздавать каждый тик;
   - **stuck-счётчик** (M28-паттерн): позиция не меняется N тиков → IssueClearCommands
     + вернуть на staging.
3. **MVP D2 (сделан, dry-run по умолчанию)** — experimental missions, детали в
   секции D2 выше. Эскорт волной не реализован (возможное улучшение).
4. **MVP D3 — transport ferry** (только при `landIdle >= AIDirectorFerryMinUnits` и
   недостижимости пешком): M28-цикл — транспорт к грузу (<15) → IssueTransportLoad в
   pcall → переиздание каждые 30с до IsUnitState('Attached') → unload на берег зоны
   Марка; перед дропом проверка GroundAA через GetUnitsAroundPoint.
5. **MVP D3/D4 (сделан как D3 forward fortify, dry-run по умолчанию)** — idle
   инженеры укрепляют базу и mex-кластеры, детали в секции D3 выше (вместо
   AIExecuteBuildStructure — прямой DecideWhatToBuild+CanBuildStructureAt+
   IssueBuildMobile). Transport ferry остаётся отдельным будущим MVP.

Все новые кнобы — с префиксом `AIDirector*` в config.lua; вся логика — в
`lua/ai_director/`.

## Safe next step prompt

Перед следующим кодом — **обкатать D1+D2 в реальной катке**: сначала dry-run
(смотреть planned волны/миссии и причины skip), потом `AIDirectorOrdersEnabled =
true` и смотреть поведение волн/эксперименталов. Дальше по плану D3 transport
ferry (самый хрупкий движковый цикл — только после обкатки D1/D2) либо D4
engineer defense, если ferry не нужен после того, как эксперименталы начали
ходить по дну.

```
MVP D3: transport ferry. Только в mod/BuffDraft/lua/ai_director/ (+ кнобы
AIDirector* в config.lua): новый модуль transport_ferry.lua. Условие: у армии
есть idle land combat юниты, для которых CanPathTo('Land', pos, цель) ложь при
живой цели от targeting.SelectTarget, и свободные транспорты (built, не Busy,
не TransportLoading, GetCargo пуст). Цикл M28-паттерна: move транспорта к грузу
(<15) → IssueTransportLoad в pcall → переиздавать каждые 30с, пока груз не
IsUnitState('Attached') → IssueTransportUnload на берег зоны цели (точка на
land-label цели через NavUtils.GetLabel) → после выгрузки юниты подхватит D1.
Перед дропом скан GroundAA через GetUnitsAroundPoint; порог юнитов
AIDirectorFerryMinUnits=6, максимум 1 ferry-операция на армию одновременно.
Уважать AIDirectorOrdersEnabled (dry-run). Логи: FAF_AI_DIRECTOR: ferry ...
planned/loading/unloading/skipped reason=... Таймауты на каждую стадию, при
таймауте release всех участников. Обновить docs/AI_DIRECTOR.md.
```
