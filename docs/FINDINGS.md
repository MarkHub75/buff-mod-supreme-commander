# Findings

## FAF mod hooking (source: references/fa-develop/lua/MODS.LUA)
- SIM-мод = папка в `/mods` с `mod_info.lua` (`ui_only = false`). Обязательные поля: `name`, `version` (integer), `author`, `uid` (GUID, новый на каждую версию).
- Мод может содержать папку `/hook`, повторяющую структуру игровых файлов. Файл хука **конкатенируется в конец** оригинального скрипта после его загрузки — можно переопределять функции, сохранив старую через `local oldFn = Fn` внутри блока `do ... end` (чтобы локальные переменные не конфликтовали с другими модами).

## Точка входа SIM (source: references/fa-develop/lua/simInit.lua)
- `BeginSession()` в `/lua/simInit.lua` вызывается движком после создания армий, прямо перед стартом игры — стандартное место для запуска фоновой логики мода.
- Паттерн фонового SIM-потока: `ForkThread(fn)` + `WaitSeconds(n)` в цикле (так делает сама игра: `GameOverListenerThread` в simInit.lua, интервалы в `lua/sim/score.lua`). `WaitSeconds` ждёт **игровые** секунды (1 игровая секунда = 10 тиков), т.е. интервал следует за игровым временем, а не реальным.
- `LOG(...)` из SIM-кода пишет в `game.log`.
