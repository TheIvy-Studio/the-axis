-- the Axis · physics lab · эксперимент 16
-- Порядок точности схем интегрирования: измерение, а не декларация.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "16",
	name = "integration_methods",
	title = "Порядок точности схем интегрирования",

	question = [[
В документации написано «первый порядок», «второй», «четвёртый». Проверим
это измерением: если схема действительно порядка p, то уменьшение шага вдвое
должно уменьшать ошибку в 2^p раз.

Отдельно проверяется гипотеза о схеме Верле: не теряет ли она порядок, когда
сила зависит от скорости? Для нас это не праздный вопрос — сопротивление
воздуха зависит от скорости всегда.

Забегая вперёд: гипотеза оказалась НЕВЕРНОЙ, и измерение это показало.
Подробности в разборе ниже.]],

	model = [[
Глобальная ошибка схемы порядка p ведёт себя как
    err(dt) = C * dt^p + O(dt^(p+1))

Отсюда способ измерить порядок, не зная константы C:
    p ~= log2( err(dt) / err(dt/2) )

Эталон — гармонический осциллятор с точным решением
    x(t) = A*cos(w*t),   v(t) = -A*w*sin(w*t)

Вторая задача — осциллятор с ВЯЗКИМ трением, где сила зависит от скорости:
    d2x/dt2 = -w^2*x - 2*zeta*w*dx/dt
Точное решение при zeta < 1:
    x(t) = A*exp(-zeta*w*t)*(cos(wd*t) + zeta/sqrt(1-zeta^2)*sin(wd*t))
    wd = w*sqrt(1 - zeta^2)

Ожидаемые порядки [hairer_odes]:
    явный Эйлер        1
    полунеявный Эйлер  1
    Верле              2
    РК4                4

Про Верле с вязкостью. Правдоподобное рассуждение: последняя строка схемы
неявна, значит подстановка предсказанной скорости v_pred = v + a*dt портит
порядок. Разложение показывает, что это не так: ошибка предсказания сама
порядка dt^2, а входит она в слагаемое, уже умноженное на dt/2, поэтому
вклад в локальную ошибку остаётся O(dt^3) — как и требуется для второго
порядка. Теряется не порядок, а симплектичность; но для системы с трением
она и не определена, потому что такая система не гамильтонова.

Цена шага, вызовов функции ускорения:
    Эйлеры и Верле — 1, РК4 — 4.
Поэтому сравнивать схемы честно надо не по шагу, а по числу вызовов: РК4 с
шагом dt стоит столько же, сколько Верле с шагом dt/4.]],

	simplifications = [[
Измеряется ошибка положения в конечный момент времени. Можно мерить и
норму по всей траектории — порядок получится тот же, а числа чуть другие.

При очень мелком шаге у РК4 ошибка упирается в машинную точность, и оценка
порядка портится. Поэтому диапазон шагов выбран так, чтобы ошибка оставалась
заметно выше 10^-14.]],

	references = { R.hairer_odes, R.swope_1982 },

	params = {
		omega = { value = 2.0, note = "частота осциллятора, рад/с" },
		zeta = { value = 0.15, note = "затухание для второй задачи" },
		duration = { value = 10.0, note = "интервал интегрирования, с" },
		coarse_dt = { value = 0.04, note = "самый крупный шаг, с" },
		refinements = { value = 5, note = "сколько раз делить шаг пополам" },
	},

	run = function(P, ctx)
		local w = P.omega
		local amplitude = 1.0

		----------------------------------------------------------------------
		-- Задача 1: сила зависит только от положения
		----------------------------------------------------------------------
		local function conservative_accel(x) return vec3.new(-w * w * x.x, 0, 0) end

		local function conservative_exact(t)
			return amplitude * math.cos(w * t)
		end

		----------------------------------------------------------------------
		-- Задача 2: сила зависит и от скорости
		----------------------------------------------------------------------
		local zeta = P.zeta
		local wd = w * math.sqrt(1 - zeta * zeta)

		local function damped_accel(x, v)
			return vec3.new(-w * w * x.x - 2 * zeta * w * v.x, 0, 0)
		end

		local function damped_exact(t)
			return amplitude * math.exp(-zeta * w * t)
				* (math.cos(wd * t)
					+ zeta / math.sqrt(1 - zeta * zeta) * math.sin(wd * t))
		end

		----------------------------------------------------------------------
		local function study(label, accel, exact)
			print()
			print(label)
			print(text.row {
				{ "схема", 22 }, { "dt", 10 }, { "ошибка", 14 },
				{ "отношение", 12 }, { "порядок", 10 },
			})

			local orders = {}
			local curves = {}

			for _, method in ipairs(integrate.methods) do
				local previous_error
				local points = {}
				local measured = {}

				for level = 0, P.refinements do
					local dt = P.coarse_dt / 2 ^ level

					local final = integrate.simulate {
						method = method.key,
						accel = accel,
						x0 = vec3.new(amplitude, 0, 0),
						v0 = vec3.zero,
						dt = dt,
						duration = P.duration,
					}

					local err = math.abs(final.x.x - exact(P.duration))
					local ratio = previous_error and previous_error / err or nil
					local order = ratio and math.log(ratio) / math.log(2) or nil

					if order then
						measured[#measured + 1] = order
					end

					points[#points + 1] = { math.log(dt) / math.log(10),
						math.log(math.max(err, 1e-18)) / math.log(10) }

					print(text.row {
						{ level == 0 and method.label or "", 22 },
						{ ("%.5f"):format(dt), 10 },
						{ ("%.4e"):format(err), 14 },
						{ ratio and ("%.2f"):format(ratio) or "—", 12 },
						{ order and ("%.3f"):format(order) or "—", 10 },
					})

					previous_error = err
				end

				-- Порядок берём по самым мелким шагам: там асимптотика чище
				orders[method.key] = measured[#measured]
				curves[#curves + 1] = {
					label = method.label,
					mark = method.key:sub(1, 1),
					points = points,
				}
			end

			return orders, curves
		end

		local conservative_orders, conservative_curves =
			study("ЗАДАЧА 1. Сила зависит только от положения (осциллятор):",
				conservative_accel, conservative_exact)

		local damped_orders, damped_curves =
			study("ЗАДАЧА 2. Сила зависит и от скорости (вязкое трение):",
				damped_accel, damped_exact)

		----------------------------------------------------------------------
		print()
		print("Измеренные порядки:")
		print(text.row {
			{ "схема", 24 }, { "заявлено", 12 }, { "без вязкости", 16 },
			{ "с вязкостью", 16 },
		})

		for _, method in ipairs(integrate.methods) do
			print(text.row {
				{ method.label, 24 },
				{ tostring(method.order), 12 },
				{ ("%.3f"):format(conservative_orders[method.key]), 16 },
				{ ("%.3f"):format(damped_orders[method.key]), 16 },
			})
		end

		print()
		print("РЕЗУЛЬТАТ, ОПРОВЕРГНУВШИЙ ГИПОТЕЗУ:")
		print("Верле сохраняет второй порядок и при силе, зависящей от")
		print("скорости. Явная подстановка предсказанной скорости вносит")
		print("ошибку порядка dt^2 в слагаемое, уже умноженное на dt/2, то")
		print("есть O(dt^3) в локальную ошибку — этого достаточно для второго")
		print("порядка. Комментарий в lab/integrate.lua, утверждавший обратное,")
		print("исправлен по результату этого измерения.")

		----------------------------------------------------------------------
		-- Честное сравнение: по числу вызовов, а не по шагу
		----------------------------------------------------------------------
		print()
		print("Сравнение при ОДИНАКОВОЙ цене (одинаковое число вызовов "
			.. "функции ускорения):")
		print(text.row {
			{ "схема", 24 }, { "dt", 12 }, { "вызовов", 12 }, { "ошибка", 14 },
		})

		local budget = 4000

		for _, method in ipairs(integrate.methods) do
			local steps = budget / method.evaluations
			local dt = P.duration / steps

			local final, _, calls = integrate.simulate {
				method = method.key,
				accel = conservative_accel,
				x0 = vec3.new(amplitude, 0, 0),
				v0 = vec3.zero,
				dt = dt,
				duration = P.duration,
			}

			print(text.row {
				{ method.label, 24 },
				{ ("%.6f"):format(dt), 12 },
				{ tostring(calls), 12 },
				{ ("%.4e"):format(math.abs(final.x.x
					- conservative_exact(P.duration))), 14 },
			})
		end

		print()
		print("Даже с поправкой на четырёхкратную цену РК4 выигрывает на")
		print("порядки. Но для игровой физики решает не это (эксперимент 14).")

		ctx.show(conservative_curves, {
			title = "Ошибка от шага в логарифмических осях (наклон = порядок)",
			xlabel = "log10(dt)",
			ylabel = "log10(ошибка)",
		})

		ctx.save(conservative_curves, {
			title = "Порядок точности схем",
			xlabel = "log10(dt)",
			ylabel = "log10(ошибка)",
		}, {
			headers = { "log_dt", "euler", "symplectic", "verlet", "rk4" },
			rows = (function()
				local rows = {}

				for index = 1, #conservative_curves[1].points do
					rows[index] = {
						conservative_curves[1].points[index][1],
						conservative_curves[1].points[index][2],
						conservative_curves[2].points[index][2],
						conservative_curves[3].points[index][2],
						conservative_curves[4].points[index][2],
					}
				end

				return rows
			end)(),
		})

		----------------------------------------------------------------------
		local suite = check.new("порядок точности")

		local why = "порядок оценивается по двум самым мелким шагам, где "
			.. "асимптотика err ~ C*dt^p уже установилась; допуск 0.1 "
			.. "покрывает вклад следующего члена разложения"

		suite:close("явный Эйлер — первого порядка",
			conservative_orders.euler, 1, 0.1, why)

		suite:close("полунеявный Эйлер — первого порядка",
			conservative_orders.symplectic, 1, 0.1, why)

		suite:close("Верле — второго порядка при консервативной силе",
			conservative_orders.verlet, 2, 0.1, why)

		suite:close("РК4 — четвёртого порядка",
			conservative_orders.rk4, 4, 0.15,
			why .. "; у РК4 допуск шире, потому что при самых мелких шагах "
			.. "ошибка приближается к машинной точности")

		suite:close("Верле сохраняет второй порядок и при вязкости",
			damped_orders.verlet, 2, 0.1,
			"опровержение исходной гипотезы: ошибка предсказанной скорости "
			.. "порядка dt^2 входит в член с множителем dt/2, значит вклад "
			.. "O(dt^3) и порядок сохраняется. Допуск тот же, что у "
			.. "остальных измерений порядка")

		suite:is_true("РК4 сохраняет порядок и при вязкости",
			damped_orders.rk4 > 3.5,
			"схема Рунге — Кутты вычисляет ускорение в промежуточных точках "
			.. "с согласованными положением и скоростью, поэтому "
			.. "зависимость от скорости её не портит")

		return suite
	end,
}
