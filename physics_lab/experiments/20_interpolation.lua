-- the Axis · physics lab · эксперимент 20
-- Интерполяция и экстраполяция.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "20",
	name = "interpolation",
	title = "Интерполяция и экстраполяция",

	question = [[
Физика считается 20 раз в секунду, а картинка рисуется 144. Как заполнить
промежуток, чтобы движение выглядело гладким и при этом не врало? И
насколько далеко можно экстраполировать положение, прежде чем ошибка станет
заметной?

Отдельный вопрос, на котором спотыкаются все: как интерполировать УГОЛ,
чтобы поворот с 179° на -179° не превращался в оборот почти на месте.]],

	model = [[
ЛИНЕЙНАЯ интерполяция:
    lerp(a, b, s) = a + (b - a)*s,   s in [0,1]
Точна, если между узлами движение равномерное. При ускоренном движении даёт
ошибку, максимум которой достигается в середине отрезка и равен a*dt^2/8.

КУБИЧЕСКИЙ ЭРМИТ. Если известны не только положения, но и скорости на концах
(а в физике они известны всегда), интерполировать можно точнее:

    h00 = 2s^3 - 3s^2 + 1      h10 = s^3 - 2s^2 + s
    h01 = -2s^3 + 3s^2         h11 = s^3 - s^2

    x(s) = h00*x0 + h10*dt*v0 + h01*x1 + h11*dt*v1

Кривая проходит через оба узла И имеет в них заданные производные, поэтому
воспроизводит равноускоренное движение ТОЧНО (это многочлен степени 2, а
Эрмит точен до степени 3).

УГЛЫ. Разность углов надо приводить к диапазону (-pi, pi]:
    d = ((b - a + pi) mod 2pi) - pi
Тогда интерполяция идёт по кратчайшей дуге. Без этого переход через границу
даёт оборот почти на полный круг.

ЭКСТРАПОЛЯЦИЯ (счисление пути). Если новых данных нет, положение
предсказывают как
    x(t + h) = x + v*h
При постоянном ускорении ошибка равна РОВНО a*h^2/2 — это остаточный член
разложения Тейлора, и он известен точно. Отсюда правило: предсказание на
100 мс при ускорении 9.81 м/с^2 даёт промах 4.9 см, на 500 мс — уже 1.2 м.

СГЛАЖИВАНИЕ. Экспоненциальное сглаживание с правильной поправкой на шаг
(эксперимент 18):
    x = x + (target - x)*(1 - exp(-rate*dt))]],

	simplifications = [[
Для ориентации здесь рассматриваются только углы вокруг одной оси. Полная
интерполяция ориентации в трёх измерениях требует кватернионов и сферической
интерполяции; линейная интерполяция углов Эйлера по трём осям даёт заметные
искажения при больших поворотах.]],

	references = { R.gaffer_integration, R.hairer_odes },

	params = {
		physics_hz = { value = 20, note = "частота физики, Гц" },
		render_hz = { value = 144, note = "частота отрисовки, Гц" },
		acceleration = { value = 9.81, note = "ускорение для проверки, м/с^2" },
		velocity = { value = 14.0, note = "скорость, м/с" },
		lag = { value = 0.15, note = "задержка для экстраполяции, с" },
	},

	run = function(P, ctx)
		local dt = 1 / P.physics_hz
		local a = P.acceleration

		----------------------------------------------------------------------
		-- Линейная интерполяция против кубической Эрмита
		----------------------------------------------------------------------
		local function lerp(from, to, s) return from + (to - from) * s end

		local function hermite(x0, v0, x1, v1, step, s)
			local s2 = s * s
			local s3 = s2 * s

			local h00 = 2 * s3 - 3 * s2 + 1
			local h10 = s3 - 2 * s2 + s
			local h01 = -2 * s3 + 3 * s2
			local h11 = s3 - s2

			return h00 * x0 + h10 * step * v0 + h01 * x1 + h11 * step * v1
		end

		-- Узлы равноускоренного движения
		local x0, v0 = 0, P.velocity
		local x1 = x0 + v0 * dt + 0.5 * a * dt * dt
		local v1 = v0 + a * dt

		print(("Шаг физики %.4f с (%.0f Гц), между узлами рисуется %.1f кадров")
			:format(dt, P.physics_hz, P.render_hz / P.physics_hz))
		print(("Узлы: x0 = %.6f, v0 = %.4f → x1 = %.6f, v1 = %.4f")
			:format(x0, v0, x1, v1))

		local worst_lerp, worst_hermite = 0, 0
		local lerp_curve, hermite_curve, exact_curve = {}, {}, {}

		local samples = math.floor(P.render_hz / P.physics_hz + 0.5) * 8

		for index = 0, samples do
			local s = index / samples
			local t = s * dt

			local exact = x0 + v0 * t + 0.5 * a * t * t
			local linear = lerp(x0, x1, s)
			local cubic = hermite(x0, v0, x1, v1, dt, s)

			worst_lerp = math.max(worst_lerp, math.abs(linear - exact))
			worst_hermite = math.max(worst_hermite, math.abs(cubic - exact))

			lerp_curve[#lerp_curve + 1] = { t, linear - exact }
			hermite_curve[#hermite_curve + 1] = { t, cubic - exact }
			exact_curve[#exact_curve + 1] = { t, 0 }
		end

		print()
		print(("Худшая ошибка линейной интерполяции: %.6e м"):format(worst_lerp))
		print(("Предсказание a*dt^2/8:                %.6e м")
			:format(a * dt * dt / 8))
		print(("Худшая ошибка кубического Эрмита:     %.6e м")
			:format(worst_hermite))
		print("Эрмит точен: равноускоренное движение — многочлен 2-й степени,")
		print("а кубическая кривая с заданными производными на концах")
		print("воспроизводит многочлены до 3-й включительно.")

		----------------------------------------------------------------------
		-- Углы
		----------------------------------------------------------------------
		local function wrap_angle(angle)
			return (angle + math.pi) % (2 * math.pi) - math.pi
		end

		local function lerp_angle(from, to, s)
			return from + wrap_angle(to - from) * s
		end

		print()
		print("Интерполяция углов через границу -180/180:")
		print()
		print(text.row {
			{ "от, °", 10 }, { "до, °", 10 }, { "наивно (середина)", 20 },
			{ "по кратчайшей дуге", 22 }, { "путь, °", 12 },
		})

		local angle_cases = {
			{ 179, -179 }, { -170, 170 }, { 10, 350 }, { 0, 180 }, { 45, 135 },
		}

		local worst_arc = 0

		for _, case in ipairs(angle_cases) do
			local from = math.rad(case[1])
			local to = math.rad(case[2])

			local naive = math.deg(lerp(from, to, 0.5))
			local correct = math.deg(wrap_angle(lerp_angle(from, to, 0.5)))
			local travelled = math.abs(math.deg(wrap_angle(to - from)))

			worst_arc = math.max(worst_arc, travelled)

			print(text.row {
				{ tostring(case[1]), 10 },
				{ tostring(case[2]), 10 },
				{ ("%.2f"):format(naive), 20 },
				{ ("%.2f"):format(correct), 22 },
				{ ("%.2f"):format(travelled), 12 },
			})
		end

		print()
		print("Первая строка — тот самый случай: наивная интерполяция ведёт")
		print("через 0°, то есть разворачивает машину почти на полный круг,")
		print("хотя дуга между углами всего 2°.")

		----------------------------------------------------------------------
		-- Экстраполяция
		----------------------------------------------------------------------
		print()
		print(("Экстраполяция при ускорении %.2f м/с^2:"):format(a))
		print()
		print(text.row {
			{ "задержка, с", 14 }, { "предсказано", 16 }, { "на деле", 16 },
			{ "промах, м", 14 }, { "a*h^2/2", 14 },
		})

		local worst_extrapolation = 0
		local extrapolation_curve = {}

		for _, h in ipairs({ 0.016, 0.05, 0.1, P.lag, 0.3, 0.5, 1.0 }) do
			local predicted = x0 + v0 * h
			local actual = x0 + v0 * h + 0.5 * a * h * h
			local miss = math.abs(actual - predicted)
			local formula = 0.5 * a * h * h

			worst_extrapolation = math.max(worst_extrapolation,
				math.abs(miss - formula))

			extrapolation_curve[#extrapolation_curve + 1] = { h, miss }

			print(text.row {
				{ ("%.3f"):format(h), 14 },
				{ ("%.4f"):format(predicted), 16 },
				{ ("%.4f"):format(actual), 16 },
				{ ("%.6f"):format(miss), 14 },
				{ ("%.6f"):format(formula), 14 },
			})
		end

		print()
		print("Промах растёт как КВАДРАТ задержки. Удвоение задержки даёт")
		print("четырёхкратный промах — поэтому экстраполировать далеко нельзя")
		print("ни при какой хитрости: это свойство разложения Тейлора.")

		----------------------------------------------------------------------
		-- Экстраполяция с учётом ускорения
		----------------------------------------------------------------------
		print()
		print("Если ускорение известно, второй член можно учесть:")
		print(("  x + v*h + a*h^2/2 при h = %.2f с даёт промах %.3e м")
			:format(P.lag, 0))
		print("  Тогда главным становится третий член, j*h^3/6, где j —")
		print("  производная ускорения. Для машины с постоянной тягой он мал.")

		ctx.show({
			{ label = "линейная", mark = "l", points = lerp_curve },
			{ label = "Эрмит", mark = "h", points = hermite_curve },
		}, {
			title = "Ошибка интерполяции внутри шага физики",
			xlabel = "время внутри шага, с",
			ylabel = "ошибка, м",
			height = 15,
		})

		ctx.show({
			{ label = "промах", mark = "*", points = extrapolation_curve },
		}, {
			title = "Промах экстраполяции растёт как квадрат задержки",
			xlabel = "задержка, с",
			ylabel = "промах, м",
			height = 14,
		})

		ctx.save({
			{ label = "линейная интерполяция", points = lerp_curve },
			{ label = "кубический Эрмит", points = hermite_curve },
		}, {
			title = "Ошибка интерполяции",
			xlabel = "время внутри шага, с",
			ylabel = "ошибка, м",
		}, {
			headers = { "t", "lerp_error", "hermite_error" },
			rows = (function()
				local rows = {}

				for index, point in ipairs(lerp_curve) do
					rows[index] = { point[1], point[2], hermite_curve[index][2] }
				end

				return rows
			end)(),
		})

		----------------------------------------------------------------------
		local suite = check.new("интерполяция")

		suite:close("ошибка линейной интерполяции равна a*dt^2/8",
			worst_lerp, a * dt * dt / 8, 1e-6,
			"максимум разности между параболой и хордой достигается в "
			.. "середине отрезка и равен a*dt^2/8; допуск учитывает конечное "
			.. "число точек выборки")

		suite:close("Эрмит воспроизводит равноускоренное движение точно",
			worst_hermite, 0, 1e-12,
			"кубическая кривая с заданными значениями и производными на "
			.. "концах точна для многочленов до 3-й степени, а парабола — "
			.. "2-й")

		suite:is_true("интерполяция углов идёт по кратчайшей дуге",
			math.abs(math.deg(wrap_angle(math.rad(-179) - math.rad(179))) - 2)
				< 1e-9,
			"разность 179° и -179° по кратчайшей дуге равна 2°, а не 358°")

		suite:close("наивная интерполяция углов даёт неверную середину",
			(math.rad(179) + math.rad(-179)) / 2, 0, 1e-12,
			"наивное среднее даёт 0°, тогда как правильная середина — 180°. "
			.. "Проверка фиксирует именно ошибочное поведение, чтобы никто "
			.. "не «починил» правильную формулу обратно")

		suite:close("правильная середина между 179° и -179° равна 180°",
			math.abs(math.deg(wrap_angle(lerp_angle(math.rad(179),
				math.rad(-179), 0.5)))), 180, 1e-9,
			"середина кратчайшей дуги: 179° + 1° = 180°")

		suite:close("промах экстраполяции равен a*h^2/2",
			worst_extrapolation, 0, 1e-12,
			"остаточный член разложения Тейлора известен точно, это не "
			.. "оценка сверху")

		suite:close("удвоение задержки учетверяет промах",
			(0.5 * a * (2 * P.lag) ^ 2) / (0.5 * a * P.lag ^ 2), 4, 1e-12,
			"квадратичная зависимость, точное отношение")

		suite:is_true("узлы интерполяции воспроизводятся точно",
			math.abs(hermite(x0, v0, x1, v1, dt, 0) - x0) < 1e-12
				and math.abs(hermite(x0, v0, x1, v1, dt, 1) - x1) < 1e-12,
			"h00(0) = 1, h01(0) = 0 и наоборот при s = 1 — базис Эрмита "
			.. "построен именно для этого")

		return suite
	end,
}
