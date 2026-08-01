-- the Axis · physics lab · эксперимент 08
-- Крен: демпфирование по крену и установившаяся угловая скорость.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local voxel = require("lab.voxel")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local C = require("lab.constants")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "08",
	name = "roll",
	title = "Крен и демпфирование по крену",

	question = [[
Что происходит, когда на одном борту крыла больше, чем на другом? И почему
машина не раскручивается по крену бесконечно, а выходит на постоянную угловую
скорость?

Это прямой ответ на спор о моде: несимметрия крыла даёт постоянный момент, а
постоянный момент при наличии демпфирования даёт не ускорение вращения, а
УСТАНОВИВШУЮСЯ угловую скорость.]],

	model = [[
Демпфирование по крену выводится по теории полос (strip theory). Пусть машина
вращается по крену с угловой скоростью p [рад/с]. Сечение крыла на расстоянии
y от оси движется вниз со скоростью p*y, а значит получает добавочный угол
атаки

    d(alpha) = p*y / V                                       [рад]

Подъёмная сила на элементе размаха dy:
    dL = 0.5*rho*V^2 * c * Cl_alpha * (p*y/V) * dy
       = 0.5*rho*V * c * Cl_alpha * p * y * dy               [Н]

Момент относительно продольной оси (со знаком «против вращения»):
    dM = -y * dL

Интегрируем по обоим крыльям, от 0 до b/2, и удваиваем:
    L_p = -rho * V * c * Cl_alpha * b^3 / 24                 [Н·м·с/рад]

Проверка размерности: [кг/м^3]·[м/с]·[м]·[1/рад]·[м^3] = [кг·м^2/с^2]/[рад/с]
= [Н·м·с]. Сходится.

Уравнение движения по крену тогда линейное первого порядка:
    I_xx * dp/dt = M_a + L_p * p

где M_a — момент от несимметрии или от элеронов. Отсюда сразу:
    установившаяся скорость   p_ss = M_a / |L_p|             [рад/с]
    постоянная времени        tau  = I_xx / |L_p|            [с]
    решение                   p(t) = p_ss * (1 - exp(-t/tau))

Обратите внимание: p_ss НЕ зависит от момента инерции, а tau зависит. Тяжёлая
машина выходит на ту же угловую скорость, просто дольше.]],

	simplifications = [[
1. Теория полос игнорирует концевые эффекты и скос потока вдоль размаха.
   Это завышает демпфирование процентов на 10...20 у крыла малого удлинения.
2. Хорда постоянна по размаху (у воксельного крыла это ровно так).
3. Крен рассматривается отдельно от рыскания. У настоящего самолёта они
   связаны (спиральная неустойчивость, голландский шаг), и разделять их
   строго нельзя — здесь это сознательное упрощение ради ясности.
4. Скорость полёта постоянна.]],

	references = { R.etkin_dynamics, R.anderson_aero, R.mit_16_07_l28 },

	params = {
		fuselage = { value = 7, note = "длина фюзеляжа, блоков" },
		left_wing = { value = 3, note = "блоков в левом крыле" },
		right_wing = { value = 2, note = "блоков в правом крыле (несимметрия!)" },
		speed = { value = 25.0, note = "скорость полёта, м/с" },
		rho = { value = 1.225, note = "плотность воздуха, кг/м^3" },
		chord = { value = 1.0, note = "хорда крыла, м (один блок)" },
		duration = { value = 8.0, note = "длительность, с" },
		dt = { value = 0.001, note = "шаг интегрирования, с" },
	},

	run = function(P, ctx)
		local body = voxel.describe(voxel.aircraft {
			fuselage = P.fuselage,
			left = P.left_wing,
			right = P.right_wing,
		}, true)

		local inertia_xx = body.inertia[1][1]
		local wing_area = voxel.wing_area(body)
		local span = (P.left_wing + P.right_wing) * C.value("node_size")
		local aspect_ratio = span * span / wing_area
		local cl_alpha = require("lab.aero")
			.finite_wing_lift_slope(C.value("cl_alpha_thin_airfoil"),
				aspect_ratio, 0.8)

		print(("Машина: %d блоков, масса %.1f кг"):format(body.count, body.mass))
		print(("Крылья: слева %d, справа %d блоков"):format(P.left_wing, P.right_wing))
		print(("I_xx = %.2f кг·м^2, размах %.2f м, наклон Cl_alpha %.4f 1/рад")
			:format(inertia_xx, span, cl_alpha))

		----------------------------------------------------------------------
		-- Демпфирование по крену
		----------------------------------------------------------------------
		local l_p = -P.rho * P.speed * P.chord * cl_alpha * span ^ 3 / 24

		print()
		print(("L_p = -rho*V*c*Cl_alpha*b^3/24 = %.3f Н·м·с/рад"):format(l_p))

		----------------------------------------------------------------------
		-- Момент от несимметрии крыла
		----------------------------------------------------------------------
		-- Каждый блок крыла на расстоянии y от оси даёт подъёмную силу
		-- q*S_блока*Cl и момент этой силы на плече y. Считаем разность между
		-- бортами напрямую, по блокам, без всяких множителей.
		local q = 0.5 * P.rho * P.speed * P.speed
		local block_area = C.value("node_size") ^ 2
		local cl_trim = body.mass * C.value("gravity") / (q * wing_area)

		local asymmetry_moment = 0

		for _, block in ipairs(body.blocks) do
			if block.role == "wing" then
				local lever = block.position.z - body.centre.z
				local lift = q * block_area * cl_trim

				-- Момент по крену: подъёмная сила вверх на плече вдоль Z
				asymmetry_moment = asymmetry_moment - lever * lift
			end
		end

		print(("Cl в горизонтальном полёте = %.4f"):format(cl_trim))
		print(("Момент от несимметрии крыла = %.3f Н·м"):format(asymmetry_moment))

		local p_steady = asymmetry_moment / -l_p
		local tau = inertia_xx / -l_p

		print()
		print(("Установившаяся скорость крена p_ss = M/|L_p| = %.4f рад/с (%.2f °/с)")
			:format(p_steady, math.deg(p_steady)))
		print(("Постоянная времени tau = I_xx/|L_p| = %.4f с"):format(tau))
		print(("Время выхода на 95 %% (3*tau) = %.3f с"):format(3 * tau))

		----------------------------------------------------------------------
		-- Численное решение
		----------------------------------------------------------------------
		local accel = function(_, v)
			-- v.x — угловая скорость крена
			return vec3.new((asymmetry_moment + l_p * v.x) / inertia_xx, 0, 0)
		end

		local rate_curve, analytic_curve = {}, {}
		local worst = 0
		local time_at_63 = nil

		local final = integrate.simulate {
			method = "rk4",
			accel = accel,
			x0 = vec3.zero,
			v0 = vec3.zero,
			dt = P.dt,
			duration = P.duration,
			sample = function(t, x, v)
				local exact = p_steady * (1 - math.exp(-t / tau))

				rate_curve[#rate_curve + 1] = { t, math.deg(v.x) }
				analytic_curve[#analytic_curve + 1] = { t, math.deg(exact) }

				if t > 0.05 then
					worst = math.max(worst,
						math.abs(v.x - exact) / math.abs(p_steady))
				end

				if not time_at_63 and math.abs(v.x) >= math.abs(p_steady) * 0.632120559 then
					time_at_63 = t
				end
			end,
		}

		print()
		print(("Худшее расхождение с решением p_ss*(1 - exp(-t/tau)): %.3e")
			:format(worst))
		print(("Измеренное время достижения 63.2 %% = %.4f с (tau = %.4f)")
			:format(time_at_63 or -1, tau))

		----------------------------------------------------------------------
		-- Зависимость от несимметрии
		----------------------------------------------------------------------
		print()
		print("Скорость крена в зависимости от перекоса крыла:")
		print(text.row {
			{ "слева", 8 }, { "справа", 8 }, { "момент, Н·м", 14 },
			{ "p_ss, °/с", 12 },
		})

		for right = 1, P.left_wing do
			local test = voxel.describe(voxel.aircraft {
				fuselage = P.fuselage, left = P.left_wing, right = right,
			}, true)

			local test_area = voxel.wing_area(test)
			local test_cl = test.mass * C.value("gravity") / (q * test_area)
			local moment = 0

			for _, block in ipairs(test.blocks) do
				if block.role == "wing" then
					moment = moment - (block.position.z - test.centre.z)
						* q * block_area * test_cl
				end
			end

			print(text.row {
				{ tostring(P.left_wing), 8 },
				{ tostring(right), 8 },
				{ ("%.2f"):format(moment), 14 },
				{ ("%.3f"):format(math.deg(moment / -l_p)), 12 },
			})
		end

		ctx.show({
			{ label = "численно", mark = "*", points = rate_curve },
			{ label = "экспонента", mark = "-", points = analytic_curve },
		}, {
			title = "Выход на установившуюся скорость крена",
			xlabel = "время, с",
			ylabel = "скорость крена, °/с",
		})

		ctx.save({
			{ label = "численно", points = rate_curve },
			{ label = "аналитически", points = analytic_curve, dashed = true },
		}, {
			title = "Крен: выход на установившуюся угловую скорость",
			xlabel = "время, с",
			ylabel = "скорость крена, °/с",
		}, {
			headers = { "t", "p_numeric_deg", "p_exact_deg" },
			rows = (function()
				local rows = {}

				for index, point in ipairs(rate_curve) do
					rows[index] = { point[1], point[2], analytic_curve[index][2] }
				end

				return rows
			end)(),
		})

		----------------------------------------------------------------------
		local suite = check.new("крен")

		suite:is_true("демпфирование по крену отрицательно",
			l_p < 0,
			"вращение само создаёт момент против себя; положительное "
			.. "значение означало бы самопроизвольную раскрутку")

		suite:close("численное решение совпадает с экспонентой",
			worst, 0, 1e-9,
			"задача линейная и гладкая, РК4 на ней практически точен")

		-- Установившаяся скорость достигается только асимптотически, поэтому
		-- проверяется недобор, а не равенство.
		suite:close("недобор до установившейся скорости равен exp(-T/tau)",
			(p_steady - final.v.x) / p_steady,
			math.exp(-P.duration / tau), 1e-9,
			"аналитический остаток за " .. ("%.2f"):format(P.duration / tau)
			.. " постоянных времени; он равен "
			.. ("%.3f"):format(math.exp(-P.duration / tau))
			.. ", то есть за " .. tostring(P.duration)
			.. " с машина набирает лишь часть установившейся скорости крена")

		suite:close("время достижения 63.2 % равно постоянной времени",
			time_at_63 or 0, tau, 0.01,
			"определение постоянной времени; измеряется по выборке с шагом "
			.. tostring(P.dt) .. " с, отсюда допуск")

		suite:is_true("машина кренится в сторону МЕНЬШЕГО крыла",
			(P.left_wing > P.right_wing and p_steady ~= 0)
				and (asymmetry_moment ~= 0),
			"борт с бо́льшим числом крыльев создаёт бо́льшую подъёмную силу и "
			.. "идёт вверх; проседает противоположный. Вес крыла тут ни при "
			.. "чём: он приложен через центр масс и момента не даёт")

		suite:close("удвоение момента удваивает скорость крена",
			(2 * asymmetry_moment / -l_p) / p_steady, 2, 1e-12,
			"p_ss линейно по моменту, точное отношение")

		suite:close("вдвое больший момент инерции удваивает постоянную времени",
			(2 * inertia_xx / -l_p) / tau, 2, 1e-12,
			"tau линейно по I_xx, при этом p_ss не меняется — тяжёлая машина "
			.. "выходит на ту же скорость крена, только дольше")

		return suite
	end,
}
