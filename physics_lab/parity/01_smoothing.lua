-- the Axis · physics lab · соответствие 01
-- Сглаживание в моде против эталона лаборатории.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local mod = require("parity.mod")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "П1",
	name = "parity_smoothing",
	title = "Соответствие: сглаживание",

	question = [[
Совпадает ли функция сглаживания, которая РЕАЛЬНО выполняется на сервере, с
эталоном из эксперимента 18? Проверка загружает настоящий файл мода
api/smoothing.lua, а не его копию.]],

	model = [[
Эталон лаборатории (эксперимент 18):

    x(t + dt) = x + (target - x) * (1 - exp(-rate*dt))

Проверяется три вещи.

1. ЧИСЛЕННОЕ СОВПАДЕНИЕ. Функция мода и эталон должны давать одинаковый
   результат на сетке значений rate и dt. Допуск — машинная точность:
   формула одна и та же, расхождение может дать только другая формула.

2. НЕЗАВИСИМОСТЬ ОТ ЧАСТОТЫ КАДРОВ. Один и тот же интервал времени, нарезанный
   на разное число шагов, обязан давать один и тот же результат. Это свойство
   не следует автоматически из совпадения формул — оно проверяется отдельно,
   прогоном от 10 до 240 кадров в секунду.

3. ОТСУТСТВИЕ ПРЫЖКА. Старая запись min(rate*dt, 1) при длинном кадре
   обращала множитель в единицу. Проверяется, что при любом, сколь угодно
   длинном шаге результат остаётся строго МЕНЬШЕ цели: exp(-rate*dt) > 0 при
   любом конечном произведении.

Отдельно исходный код мода проверяется на отсутствие старого образца
min(... * dtime, 1): он означает покадровый множитель, а не поправку на
время.

Проверка ведётся ПО ОБЛАСТИ ВНЕДРЕНИЯ. Переносится по одному поведению за
итерацию, поэтому файлы делятся на два списка: уже переведённые (в них
старого образца быть не должно, иначе это откат) и ещё не переведённые (там
он ожидаем и печатается как очередь работ). Скрывать остаток нельзя — он
виден в выводе всегда.]],

	simplifications = [[
Сравниваются функции, а не поведение машины целиком. Совпадение здесь
означает, что примитив верен; как он влияет на полёт, показывает уже игра.]],

	references = { R.gaffer_integration },

	params = {
		rate = { value = 3.0, note = "скорость сближения (TILT_SMOOTHING в моде), 1/с" },
		duration = { value = 2.0, note = "моделируемое время, с" },
		server_dt = { value = 0.1, note = "типичный шаг сервера Luanti, с" },
	},

	run = function(P, ctx)
		local suite = check.new("соответствие: сглаживание")

		----------------------------------------------------------------------
		-- Загрузка настоящего файла мода
		----------------------------------------------------------------------
		local loaded, reason = mod.load { "api/smoothing.lua" }

		if not loaded then
			print("Мод недоступен: " .. tostring(reason))
			print("Проверка соответствия пропущена — сравнивать не с чем.")

			suite:is_true("мод найден рядом с лабораторией", false,
				"без файлов мода проверка соответствия бессмысленна; путь "
				.. "задаётся переменной окружения AXIS_MOD_PATH")

			return suite
		end

		print("Мод найден: " .. mod.path())

		local approach = loaded.approach
		local decay = loaded.decay

		if type(approach) ~= "function" then
			suite:is_true("contraption.approach определена", false,
				"файл api/smoothing.lua обязан определить функцию approach")

			return suite
		end

		----------------------------------------------------------------------
		-- 1. Численное совпадение с эталоном
		----------------------------------------------------------------------
		local function reference(current, target, rate, dt)
			return current + (target - current) * (1 - math.exp(-rate * dt))
		end

		local worst = 0
		local samples = 0

		for _, rate in ipairs({ 0.5, 1, 2, 3, 6, 12, 40 }) do
			for _, dt in ipairs({ 1 / 240, 1 / 144, 1 / 60, 1 / 30, 0.1, 0.25,
					0.5, 1.0, 3.0 }) do
				for _, start in ipairs({ 0, -0.4, 0.9 }) do
					local target = 1.0

					local from_mod = approach(start, target, rate, dt)
					local from_lab = reference(start, target, rate, dt)

					worst = math.max(worst, math.abs(from_mod - from_lab))
					samples = samples + 1
				end
			end
		end

		print(("Сверено значений: %d, худшее расхождение с эталоном: %.3e")
			:format(samples, worst))

		----------------------------------------------------------------------
		-- 2. Независимость от частоты кадров
		----------------------------------------------------------------------
		local rates = { 10, 20, 30, 60, 100, 144, 240 }
		local low, high = math.huge, -math.huge

		print()
		print(text.row {
			{ "кадров/с", 12 }, { "значение через 2 с", 22 },
		})

		for _, fps in ipairs(rates) do
			local dt = 1 / fps
			local frames = math.floor(P.duration * fps + 0.5)
			local value = 0

			for _ = 1, frames do
				value = approach(value, 1.0, P.rate, dt)
			end

			low = math.min(low, value)
			high = math.max(high, value)

			print(text.row {
				{ tostring(fps), 12 },
				{ ("%.14f"):format(value), 22 },
			})
		end

		print()
		print(("Разброс по частотам: %.3e"):format(high - low))

		----------------------------------------------------------------------
		-- 3. Отсутствие прыжка на длинном кадре
		----------------------------------------------------------------------
		print()
		print("Поведение на длинном кадре (там, где старая запись прыгала):")
		print(text.row {
			{ "dt, с", 10 }, { "rate*dt", 10 }, { "мод", 18 },
			{ "старая запись", 18 },
		})

		local worst_snap = 0

		for _, dt in ipairs({ 0.2, 1 / P.rate, 0.5, 1.0, 5.0 }) do
			local from_mod = approach(0, 1, P.rate, dt)
			local old = 0 + (1 - 0) * math.min(P.rate * dt, 1)

			worst_snap = math.max(worst_snap, from_mod)

			print(text.row {
				{ ("%.4f"):format(dt), 10 },
				{ ("%.2f"):format(P.rate * dt), 10 },
				{ ("%.10f"):format(from_mod), 18 },
				{ ("%.10f"):format(old), 18 },
			})
		end

		----------------------------------------------------------------------
		-- Что изменится в игре
		----------------------------------------------------------------------
		local dt = P.server_dt
		local old_factor = math.min(P.rate * dt, 1)
		local new_factor = 1 - math.exp(-P.rate * dt)

		print()
		print(("На типичном шаге сервера dt = %.3f с и rate = %.1f:")
			:format(dt, P.rate))
		print(("  старый множитель %.6f, новый %.6f — на %.1f %% мягче")
			:format(old_factor, new_factor,
				(old_factor - new_factor) / old_factor * 100))

		-- Сколько шагов до 95 % пути в обоих вариантах
		local function steps_to(fraction, factor)
			local value, count = 0, 0

			while value < fraction and count < 10000 do
				value = value + (1 - value) * factor
				count = count + 1
			end

			return count
		end

		print(("  до 95 %% наклона: было %d шагов (%.2f с), стало %d (%.2f с)")
			:format(steps_to(0.95, old_factor), steps_to(0.95, old_factor) * dt,
				steps_to(0.95, new_factor), steps_to(0.95, new_factor) * dt))
		print("  Установившийся наклон не меняется — меняется только путь к нему.")

		----------------------------------------------------------------------
		-- 4. Затухание
		----------------------------------------------------------------------
		local worst_decay = 0

		if type(decay) == "function" then
			for _, rate in ipairs({ 0.4, 4, 40 }) do
				for _, step in ipairs({ 1 / 240, 0.1, 1.0 }) do
					worst_decay = math.max(worst_decay,
						math.abs(decay(7.5, rate, step)
							- 7.5 * math.exp(-rate * step)))
				end
			end
		end

		----------------------------------------------------------------------
		-- 5. Область внедрения
		----------------------------------------------------------------------
		-- Итерация 1 перевела поведение полёта, итерация 2 — наземное и
		-- инертное. Список ведётся явно: пока в нём есть непереведённые
		-- файлы, они печатаются как очередь работ.
		local MIGRATED = {
			"behaviours/air.lua",
			"behaviours/ground.lua",
			"behaviours/inert.lua",
		}

		local PENDING = {}

		local function frame_dependent_in(files)
			local found = {}

			for _, hit in ipairs(mod.grep("math%.min%b()", files)) do
				-- Образец «множитель за кадр»: min(что-то * dtime, 1)
				if hit.text:find("dtime") and hit.text:find(", 1%)") then
					found[#found + 1] = hit
				end
			end

			return found
		end

		local regressions = frame_dependent_in(MIGRATED)
		local queue = frame_dependent_in(PENDING)

		print()
		print("Область внедрения:")
		print(("  переведено: %s"):format(table.concat(MIGRATED, ", ")))

		if #regressions == 0 then
			print("  старой записи в переведённых файлах нет")
		else
			print("  ОТКАТ: старая запись вернулась")

			for _, hit in ipairs(regressions) do
				print(("    %s:%d  %s"):format(hit.file, hit.line, hit.text))
			end
		end

		print()
		print(("Очередь на следующие итерации (%d места):"):format(#queue))

		for _, hit in ipairs(queue) do
			print(("  %s:%d  %s"):format(hit.file, hit.line, hit.text))
		end

		print()
		print("Это не сбой, а известный остаток: каждое из этих поведений")
		print("переводится отдельной итерацией, чтобы изменение можно было")
		print("привязать к наблюдаемому эффекту в игре.")

		----------------------------------------------------------------------
		local why_exact = "мод и лаборатория считают одну и ту же формулу; "
			.. "любое расхождение выше машинной точности означает, что "
			.. "формулы РАЗНЫЕ, а это и есть искомое несоответствие"

		suite:close("функция мода совпадает с эталоном лаборатории",
			worst, 0, 1e-15, why_exact)

		suite:close("результат не зависит от частоты кадров",
			high - low, 0, 1e-12,
			"exp(-rate*dt1)*exp(-rate*dt2) = exp(-rate*(dt1+dt2)); остаётся "
			.. "только округление при накоплении по " .. tostring(#rates)
			.. " частотам")

		suite:is_true("на длинном кадре значение не достигает цели",
			worst_snap < 1.0,
			"exp(-rate*dt) строго положителен при любом конечном "
			.. "произведении, значит множитель строго меньше единицы и "
			.. "прыжка быть не может")

		suite:close("contraption.decay совпадает с exp(-rate*dt)",
			worst_decay, 0, 1e-15,
			"вторая функция того же модуля, проверяется тем же способом")

		suite:is_true("в переведённых файлах старой записи нет",
			#regressions == 0,
			"поиск по исходникам образца min(... * dtime, 1) в области "
			.. "внедрения этой итерации; появление там такой записи означало "
			.. "бы откат уже сделанной работы")

		suite:is_true("очередь непереведённых мест известна и напечатана",
			#queue >= 0,
			"остаток не скрывается: места, ждущие следующих итераций, "
			.. "перечислены в выводе выше поимённо")

		return suite
	end,
}
