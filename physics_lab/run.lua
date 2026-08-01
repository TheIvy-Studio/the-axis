-- the Axis · physics lab
-- Общий прогон: запускает все эксперименты и говорит, остались ли результаты
-- физически осмысленными.
--
--     luajit run.lua                  сводка по всем экспериментам
--     luajit run.lua --full           полный вывод каждого
--     luajit run.lua --only 04        только эксперимент 04
--     luajit run.lua --only lift      поиск по имени
--     luajit run.lua --svg --csv      записать графики и данные в out/
--     luajit run.lua --list           перечислить эксперименты
--     luajit run.lua --constants      таблица констант с обоснованиями
--     luajit run.lua --references     библиография
--
-- Код возврата: 0 — всё сошлось, 1 — есть расхождения.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "?.lua;")
	.. package.path

-- Флаг переключает файлы экспериментов из режима «запусти себя» в режим
-- «верни описание».
LAB_BATCH = true

local text = require("lab.text")

--------------------------------------------------------------------------------
-- Список экспериментов
--------------------------------------------------------------------------------
--
-- Список задан явно, а не вычитан из каталога: порядок здесь осмысленный
-- (от простого к сложному), и его не должна определять сортировка имён.
-- Новый эксперимент добавляется сюда же.

local FILES = {
	"experiments/01_constant_acceleration.lua",
	"experiments/02_gravity.lua",
	"experiments/03_drag_force.lua",
	"experiments/04_air_resistance.lua",
	"experiments/05_thrust.lua",
	"experiments/06_lift.lua",
	"experiments/07_pitch.lua",
	"experiments/08_roll.lua",
	"experiments/09_yaw.lua",
	"experiments/10_turn_radius.lua",
	"experiments/11_inertia.lua",
	"experiments/12_angular_velocity.lua",
	"experiments/13_momentum.lua",
	"experiments/14_energy_conservation.lua",
	"experiments/15_collision_response.lua",
	"experiments/16_integration_methods.lua",
	"experiments/17_numerical_stability.lua",
	"experiments/18_framerate_independence.lua",
	"experiments/19_damping.lua",
	"experiments/20_interpolation.lua",
}

-- Проверки соответствия: сверяют НАСТОЯЩИЙ код мода с эталонами лаборатории.
-- Ведутся отдельным списком, потому что отвечают на другой вопрос: не
-- «верна ли модель», а «то ли самое стоит в игре».
local PARITY = {
	"parity/01_smoothing.lua",
	"parity/02_behaviour_damping.lua",
	"parity/03_inertia.lua",
	"parity/04_drag.lua",
	"parity/05_lift.lua",
	"parity/06_turn.lua",
	"parity/07_mass.lua",
	"parity/08_pointing.lua",
	"parity/09_airship.lua",
	"parity/10_assembly.lua",
}

--------------------------------------------------------------------------------
-- Разбор аргументов
--------------------------------------------------------------------------------

local flags = {}
local only

do
	local index = 1

	while arg[index] do
		local item = arg[index]
		local flag = item:match("^%-%-([%w%-]+)$")

		if flag == "only" then
			index = index + 1
			only = arg[index]
		elseif flag then
			flags[flag] = true
		end

		index = index + 1
	end
end

--------------------------------------------------------------------------------
-- Служебные режимы
--------------------------------------------------------------------------------

if flags.references then
	require("lab.references").print()
	os.exit(0)
end

if flags.constants then
	require("lab.constants").print()
	os.exit(0)
end

--------------------------------------------------------------------------------
-- Загрузка
--------------------------------------------------------------------------------

local specs = {}
local parity_specs = {}

local function load_spec(path)
	local chunk, message = loadfile(path)

	if not chunk then
		io.stderr:write(("не удалось загрузить %s: %s\n"):format(path, message))
		os.exit(2)
	end

	local spec = chunk()

	if type(spec) ~= "table" or not spec.execute then
		io.stderr:write(("%s не вернул описание эксперимента\n"):format(path))
		os.exit(2)
	end

	spec.path = path

	return spec
end

for _, path in ipairs(FILES) do
	specs[#specs + 1] = load_spec(path)
end

for _, path in ipairs(PARITY) do
	local spec = load_spec(path)

	spec.parity = true
	parity_specs[#parity_specs + 1] = spec
	specs[#specs + 1] = spec
end

if flags.list then
	print(("Экспериментов: %d, из них проверок соответствия %d")
		:format(#specs, #parity_specs))
	print()

	for _, spec in ipairs(specs) do
		print(("  %s  %s"):format(spec.id, spec.title))
		print(("      %s"):format(spec.path))
	end

	os.exit(0)
end

--------------------------------------------------------------------------------
-- Отбор
--------------------------------------------------------------------------------

local selected = {}

for _, spec in ipairs(specs) do
	if not only or spec.id == only or spec.name:find(only, 1, true)
			or spec.title:lower():find(only:lower(), 1, true) then
		selected[#selected + 1] = spec
	end
end

if #selected == 0 then
	io.stderr:write(("по запросу '%s' ничего не найдено\n"):format(only))
	os.exit(2)
end

--------------------------------------------------------------------------------
-- Проверка размерностей до всего остального
--------------------------------------------------------------------------------

print(string.rep("=", 78))
print("the Axis · физическая лаборатория")
print(string.rep("=", 78))
print()
print("Проверка согласованности размерностей (исполняемая, на величинах СИ):")

local dimension_failures = 0

for _, module_name in ipairs({ "lab.aero", "lab.rigid" }) do
	local module = require(module_name)

	for _, entry in ipairs(module.dimension_selftest()) do
		if not entry.ok then
			dimension_failures = dimension_failures + 1

			print(("  СБОЙ %s: получено [%s], ожидалось [%s]")
				:format(entry.name, entry.got, entry.expected))
		end
	end
end

if dimension_failures == 0 then
	print("  все формулы размерно согласованы")
else
	print(("  расхождений: %d"):format(dimension_failures))
end

--------------------------------------------------------------------------------
-- Прогон
--------------------------------------------------------------------------------

local run_flags = {
	quiet = not flags.full,
	svg = flags.svg or false,
	csv = flags.csv or false,
}

local results = {}
local started = os.clock()

if run_flags.quiet then
	print()
	print(("Запуск %d экспериментов (полный вывод — ключ --full):")
		:format(#selected))
	print()
end

for _, spec in ipairs(selected) do
	if run_flags.quiet then
		io.write(("  %s %s ... "):format(spec.id,
			text.pad(spec.title, 46)))
		io.flush()
	end

	local result = spec.execute({}, run_flags)

	results[#results + 1] = result

	if run_flags.quiet then
		if result.crashed then
			print("АВАРИЯ")
		else
			print(("%s  (%d из %d)")
				:format(result.ok and "ОК" or "СБОЙ",
					result.total - result.failed, result.total))
		end
	end
end

local elapsed = os.clock() - started

--------------------------------------------------------------------------------
-- Сводка
--------------------------------------------------------------------------------

local total_checks, total_failed, failed_experiments = 0, 0, 0
local parity_failed, parity_total = 0, 0
local artifacts = 0

for index, result in ipairs(results) do
	if selected[index].parity then
		parity_total = parity_total + 1

		if not result.ok then
			parity_failed = parity_failed + 1
		end
	end
end

for _, result in ipairs(results) do
	total_checks = total_checks + result.total
	total_failed = total_failed + result.failed
	artifacts = artifacts + #result.artifacts

	if not result.ok then
		failed_experiments = failed_experiments + 1
	end
end

print()
print(string.rep("=", 78))
print("СВОДКА")
print(string.rep("=", 78))
print(("Экспериментов:      %d, из них с расхождениями %d")
	:format(#results, failed_experiments))
print(("Проверок:           %d, из них не сошлось %d")
	:format(total_checks, total_failed))
print(("Соответствие моду:  %d проверок, расхождений %d")
	:format(parity_total, parity_failed))
print(("Размерности:        %s")
	:format(dimension_failures == 0 and "согласованы"
		or ("расхождений " .. dimension_failures)))
print(("Время счёта:        %.2f с"):format(elapsed))

if artifacts > 0 then
	print(("Записано файлов:    %d (каталог out/)"):format(artifacts))
end

if failed_experiments > 0 then
	print()
	print("Расхождения:")

	for _, result in ipairs(results) do
		if not result.ok then
			print(("  %s %s — %s"):format(result.id, result.title,
				result.crashed or (result.failed .. " проверок не сошлось")))
		end
	end

	print()
	print("Подробности: luajit run.lua --only <номер> ")
	print()
	print("Расхождение — повод искать причину, а не подгонять допуск.")
end

print()

if failed_experiments > 0 or dimension_failures > 0 then
	print("ВЫВОД: результаты физически НЕ подтверждены.")
	os.exit(1)
end

print("ВЫВОД: все результаты сошлись с аналитическими эталонами и законами")
print("сохранения. Физика в пределах проверенного остаётся осмысленной,")
print("а код мода совпадает с проверенными формулами.")
os.exit(0)
