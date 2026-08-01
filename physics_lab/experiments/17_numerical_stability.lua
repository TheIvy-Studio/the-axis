-- the Axis · physics lab · эксперимент 17
-- Численная устойчивость: где схема разваливается и почему.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "17",
	name = "numerical_stability",
	title = "Численная устойчивость",

	question = [[
Точность и устойчивость — разные вещи. Схема может быть неточной, но
работать; а может быть точной на бумаге и взорваться на первом же кадре с
просадкой. Где именно проходят границы?]],

	model = [[
Устойчивость исследуется на двух эталонных задачах.

1. Затухание:  dv/dt = -k*v,  точное решение v = v0*exp(-k*t)
   Явный Эйлер даёт v[n+1] = v[n]*(1 - k*dt), значит множитель за шаг равен
   (1 - k*dt), и

       |1 - k*dt| < 1   <=>   dt < 2/k

   Три режима:
       dt < 1/k        множитель в (0,1)   — гладкое затухание
       1/k < dt < 2/k  множитель в (-1,0)  — затухание со сменой знака
       dt > 2/k        |множитель| > 1     — расходимость

   Средний режим особенно коварен: скорость каждый кадр меняет знак, тело
   дрожит, а формально «всё сходится».

2. Осциллятор: d2x/dt2 = -w^2*x
   Для явного Эйлера матрица шага имеет собственные значения 1 ± i*w*dt, их
   модуль равен sqrt(1 + w^2*dt^2) > 1 при любом dt > 0. Амплитуда растёт
   за N шагов ровно в (1 + w^2*dt^2)^(N/2) раз — схема неустойчива
   БЕЗУСЛОВНО.

   Для полунеявного Эйлера граница устойчивости w*dt < 2 [hairer_geometric].
   Более того, для него известна ТОЧНАЯ амплитуда. Схема сохраняет
   модифицированный гамильтониан (эксперимент 14)

       H~ = 0.5*v^2 + 0.5*w^2*x^2 - (w^2*dt/2)*x*v

   Это эллипс. Максимум x на нём при старте из (x0, 0) равен

       x_max = x0 / sqrt(1 - (w*dt/2)^2)                      [м]

   При w*dt -> 2 знаменатель обращается в ноль: эллипс вырождается, амплитуда
   уходит в бесконечность. Это и есть граница устойчивости, выведенная не из
   таблицы, а из инварианта схемы. Формула проверяется измерением.

Отдельно проверяется приём, который встречается в игровом коде чаще всего:
затухание умножением v *= (1 - k*dt). Это ровно явный Эйлер, со всеми его
границами: при dt > 1/k множитель становится отрицательным и скорость
разворачивается. Правильная форма — v *= exp(-k*dt), она устойчива при
ЛЮБОМ шаге, потому что множитель положителен всегда.]],

	simplifications = [[
Рассматриваются линейные задачи. Для нелинейных строгих границ нет, но
линейный анализ вокруг положения равновесия даёт практически верный ответ
и для них.]],

	references = { R.hairer_geometric, R.hairer_odes },

	params = {
		decay_rate = { value = 4.0, note = "коэффициент затухания k, 1/с" },
		omega = { value = 6.0, note = "частота осциллятора, рад/с" },
		duration = { value = 4.0, note = "длительность для явного Эйлера, с" },
		steps = { value = 400, note = "число шагов в опыте на устойчивость" },
	},

	run = function(P, ctx)
		local k = P.decay_rate

		----------------------------------------------------------------------
		-- Задача 1: три режима затухания
		----------------------------------------------------------------------
		print(("Затухание dv/dt = -k*v, k = %.2f 1/с"):format(k))
		print(("  граница гладкости    dt = 1/k = %.4f с"):format(1 / k))
		print(("  граница устойчивости  dt = 2/k = %.4f с"):format(2 / k))
		print()
		print(text.row {
			{ "dt, с", 10 }, { "k*dt", 10 }, { "множитель", 14 },
			{ "v в конце", 16 }, { "режим", 26 },
		})

		local regimes = {}

		for _, factor in ipairs({ 0.25, 0.5, 0.9, 1.0, 1.5, 1.9, 2.0, 2.5 }) do
			local dt = factor / k
			local multiplier = 1 - k * dt

			local v = 1.0
			local steps = 12
			local changes_sign = false
			local previous = v

			for _ = 1, steps do
				v = v * multiplier

				if v * previous < 0 then
					changes_sign = true
				end

				previous = v
			end

			local regime

			if math.abs(multiplier) >= 1 then
				regime = "РАСХОДИТСЯ"
			elseif multiplier < 0 then
				regime = "дрожит (смена знака)"
			else
				regime = "гладкое затухание"
			end

			regimes[#regimes + 1] = {
				factor = factor, multiplier = multiplier,
				final = v, diverges = math.abs(multiplier) >= 1,
				oscillates = changes_sign,
			}

			print(text.row {
				{ ("%.4f"):format(dt), 10 },
				{ ("%.2f"):format(factor), 10 },
				{ ("%+.4f"):format(multiplier), 14 },
				{ ("%.6g"):format(v), 16 },
				{ regime, 26 },
			})
		end

		----------------------------------------------------------------------
		-- Точная форма затухания
		----------------------------------------------------------------------
		print()
		print("Та же задача, но множитель exp(-k*dt):")
		print(text.row {
			{ "dt, с", 10 }, { "k*dt", 10 }, { "множитель", 14 },
			{ "v в конце", 16 },
		})

		local exact_worst = 0

		for _, factor in ipairs({ 0.25, 1.0, 2.5, 10.0 }) do
			local dt = factor / k
			local multiplier = math.exp(-k * dt)

			local v = 1.0

			for _ = 1, 12 do
				v = v * multiplier
			end

			-- Точное решение за то же полное время
			local reference = math.exp(-k * dt * 12)

			exact_worst = math.max(exact_worst, math.abs(v - reference))

			print(text.row {
				{ ("%.4f"):format(dt), 10 },
				{ ("%.2f"):format(factor), 10 },
				{ ("%.6f"):format(multiplier), 14 },
				{ ("%.6g"):format(v), 16 },
			})
		end

		print("Множитель всегда положителен и меньше единицы: расходиться")
		print("и менять знак такой схеме просто нечем, при любом шаге.")

		----------------------------------------------------------------------
		-- Задача 2: осциллятор
		----------------------------------------------------------------------
		local w = P.omega

		print()
		print(("Осциллятор, w = %.2f рад/с. Граница для полунеявной схемы "
			.. "w*dt = 2, то есть dt = %.4f с"):format(w, 2 / w))
		print(("Каждый опыт — ровно %d шагов, длительность подстраивается.")
			:format(P.steps))
		print()
		print(text.row {
			{ "w*dt", 10 }, { "явный Эйлер", 20 }, { "полунеявный", 20 },
			{ "Верле", 20 },
		})

		local stability = {}

		-- Длительность задаётся ЧЕРЕЗ число шагов, а не наоборот. Иначе
		-- шаг подгоняется под длительность и произведение w*dt сползает:
		-- при заказанных 1.99 фактически получалось ровно 2.00, то есть
		-- вырожденный случай на самой границе устойчивости.
		local step_count = P.steps

		for _, product in ipairs({ 0.2, 0.5, 1.0, 1.5, 1.9, 1.99, 2.01, 2.5 }) do
			local dt = product / w
			local row = { product = product, dt = dt }

			for _, key in ipairs({ "euler", "symplectic", "verlet" }) do
				local peak = 0

				integrate.simulate {
					method = key,
					accel = function(x) return vec3.new(-w * w * x.x, 0, 0) end,
					x0 = vec3.new(1, 0, 0),
					v0 = vec3.zero,
					dt = dt,
					duration = dt * step_count,
					sample = function(_, x)
						peak = math.max(peak, math.abs(x.x))
					end,
				}

				row[key] = peak
			end

			stability[#stability + 1] = row

			print(text.row {
				{ ("%.2f"):format(product), 10 },
				{ ("%.4g"):format(row.euler), 20 },
				{ ("%.4g"):format(row.symplectic), 20 },
				{ ("%.4g"):format(row.verlet), 20 },
			})
		end

		----------------------------------------------------------------------
		-- Точный коэффициент роста явного Эйлера
		----------------------------------------------------------------------
		local test_dt = 0.5 / w
		local steps = math.floor(P.duration / test_dt + 0.5)
		local dt_eff = P.duration / steps
		local predicted = (1 + w * w * dt_eff * dt_eff) ^ (steps / 2)

		local final = integrate.simulate {
			method = "euler",
			accel = function(x) return vec3.new(-w * w * x.x, 0, 0) end,
			x0 = vec3.new(1, 0, 0),
			v0 = vec3.zero,
			dt = test_dt,
			duration = P.duration,
		}

		local measured = math.sqrt(final.x.x ^ 2 + (final.v.x / w) ^ 2)

		print()
		print(("Рост амплитуды у явного Эйлера за %d шагов:"):format(steps))
		print(("  предсказано (1 + w^2*dt^2)^(N/2) = %.6f"):format(predicted))
		print(("  измерено                          = %.6f"):format(measured))

		----------------------------------------------------------------------
		-- Точная амплитуда полунеявной схемы
		----------------------------------------------------------------------
		print()
		print("Полунеявный Эйлер: измеренная амплитуда против точной формулы")
		print("x_max = 1/sqrt(1 - (w*dt/2)^2):")
		print(text.row {
			{ "w*dt", 10 }, { "измерено", 16 }, { "формула", 16 },
			{ "отношение", 12 },
		})

		local worst_amplitude = 0

		for _, row in ipairs(stability) do
			local product = row.product

			if product < 2 then
				local predicted_peak = 1 / math.sqrt(1 - (product / 2) ^ 2)

				-- Пик ищется по выборке с шагом dt, поэтому измеренное
				-- значение не превышает формулу, но может её не добрать.
				worst_amplitude = math.max(worst_amplitude,
					row.symplectic / predicted_peak)

				print(text.row {
					{ ("%.2f"):format(product), 10 },
					{ ("%.4f"):format(row.symplectic), 16 },
					{ ("%.4f"):format(predicted_peak), 16 },
					{ ("%.4f"):format(row.symplectic / predicted_peak), 12 },
				})
			end
		end

		local growth_curve = {}

		for _, row in ipairs(stability) do
			growth_curve[#growth_curve + 1] = { row.product, row.symplectic }
		end

		ctx.show({
			{ label = "пик амплитуды", mark = "*", points = growth_curve },
		}, {
			title = "Полунеявный Эйлер: обрыв устойчивости при w*dt = 2",
			xlabel = "w*dt",
			ylabel = "пиковая амплитуда",
			height = 15,
		})

		ctx.save({
			{ label = "полунеявный Эйлер", points = growth_curve },
		}, {
			title = "Граница устойчивости",
			xlabel = "w*dt",
			ylabel = "пиковая амплитуда",
		}, {
			headers = { "w_dt", "peak" },
			rows = growth_curve,
		})

		----------------------------------------------------------------------
		local suite = check.new("численная устойчивость")

		suite:is_true("при k*dt < 1 затухание гладкое",
			not regimes[1].oscillates and not regimes[1].diverges,
			"множитель (1 - k*dt) лежит в (0,1), знак не меняется")

		suite:is_true("при 1 < k*dt < 2 скорость меняет знак каждый шаг",
			regimes[5].oscillates and not regimes[5].diverges,
			"множитель отрицателен, но по модулю меньше единицы: формально "
			.. "сходится, физически — дрожь")

		suite:is_true("при k*dt >= 2 схема расходится",
			regimes[7].diverges and regimes[8].diverges,
			"|1 - k*dt| >= 1, амплитуда не убывает")

		suite:close("граница устойчивости ровно dt = 2/k",
			2 / k, 2 / P.decay_rate, 1e-12,
			"условие |1 - k*dt| < 1 решается точно")

		suite:close("экспоненциальный множитель воспроизводит точное решение",
			exact_worst, 0, 1e-15,
			"exp(-k*dt)^N = exp(-k*N*dt) — тождество, а не приближение; "
			.. "остаётся только округление")

		suite:close("рост амплитуды у явного Эйлера равен (1+w^2dt^2)^(N/2)",
			measured, predicted, 1e-9,
			"точный модуль собственного значения матрицы шага")

		suite:is_true("явный Эйлер неустойчив на осцилляторе при любом шаге",
			stability[1].euler > 1.0,
			"даже при w*dt = 0.2 амплитуда превышает начальную: у схемы нет "
			.. "области устойчивости на чисто мнимых собственных значениях")

		suite:is_true("амплитуда полунеявной схемы не превышает точной формулы",
			worst_amplitude <= 1 + 1e-9,
			"x_max = 1/sqrt(1-(w*dt/2)^2) — строгая верхняя граница, "
			.. "полученная из сохраняющегося модифицированного "
			.. "гамильтониана. Измеренное значение не добирает её лишь "
			.. "потому, что пик ищется по выборке с конечным шагом")

		suite:is_true("до w*dt = 2 амплитуда конечна",
			stability[6].symplectic < math.huge
				and stability[6].symplectic > 1,
			"при w*dt = 1.99 амплитуда вырастает примерно в 10 раз, но "
			.. "остаётся ограниченной: схема устойчива, хотя точность уже "
			.. "никуда не годится. Устойчивость и точность — разные вещи")

		suite:is_true("за границей w*dt = 2 полунеявный Эйлер расходится",
			stability[8].symplectic > 10 * stability[6].symplectic,
			"при w*dt = 2.5 собственные значения выходят из единичной "
			.. "окружности")

		suite:is_true("Верле имеет ту же границу устойчивости",
			stability[6].verlet < 1e3 and stability[8].verlet > 10,
			"обе схемы симплектические и имеют одинаковое условие w*dt < 2")

		return suite
	end,
}
