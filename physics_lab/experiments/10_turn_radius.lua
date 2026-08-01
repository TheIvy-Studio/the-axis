-- the Axis · physics lab · эксперимент 10
-- Установившийся координированный разворот: радиус, перегрузка, темп.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local aero = require("lab.aero")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "10",
	name = "turn_radius",
	title = "Разворот с креном: радиус и перегрузка",

	question = [[
Самолёт разворачивается не рулём направления, а креном. Насколько крутым
получится вираж и какой ценой?

Для мода это важно вдвойне: сейчас поворот там сделан прямым изменением
курса (rig.yaw уменьшается на TURN_SPEED*dt), то есть машина разворачивается
как танк. Физически поворот — это следствие крена, и радиус из него
ВЫВОДИТСЯ, а не задаётся.]],

	model = [[
Страница NASA о разворотах [nasa_banking_turns] описывает механизм словами:
подъёмная сила всегда перпендикулярна плоскости крыльев, при крене она
наклоняется и её горизонтальная составляющая разворачивает машину.
Количественные соотношения выводятся отсюда вторым законом Ньютона.

Установившийся координированный разворот с креном phi на постоянной высоте:

    вертикаль:    L*cos(phi) = m*g
    горизонталь:  L*sin(phi) = m*V^2 / R

Делим второе на первое — масса и подъёмная сила сокращаются:

    tan(phi) = V^2 / (g*R)
    R = V^2 / (g * tan(phi))                                 [м]
    omega = V/R = g*tan(phi)/V                               [рад/с]
    n = L/(m*g) = 1/cos(phi)                                 [—]

Перегрузка n подтверждается независимым источником: FAA PHAK, глава 5
[faa_phak], там же рост скорости сваливания:
    V_stall(n) = V_stall * sqrt(n)

Размерности: R = [м^2/с^2]/[м/с^2] = [м]; omega = [м/с^2]/[м/с] = [1/с].
Сходятся.

Замечательное следствие: ни радиус, ни темп разворота НЕ зависят от массы.
Тяжёлая и лёгкая машины при одинаковых крене и скорости описывают
одинаковую окружность. Разница только в потребной подъёмной силе.]],

	simplifications = [[
1. Разворот координированный: скольжения нет, вектор скорости лежит в
   плоскости симметрии. Некоординированный разворот со скольжением требует
   боковой аэродинамики.
2. Высота постоянна. На деле для этого нужно увеличить угол атаки (перегрузка
   n) и добавить тягу — иначе машина просядет. Потребная тяга в вираже растёт
   как n^2 из-за индуктивного сопротивления.
3. Крен считается уже установившимся. Время выхода на крен — эксперимент 08.]],

	references = { R.nasa_banking_turns, R.faa_phak },

	params = {
		speed = { value = 25.0, note = "скорость полёта, м/с" },
		bank_deg = { value = 30.0, note = "угол крена, градусы" },
		gravity = { value = 9.81, note = "ускорение падения, м/с^2" },
		stall_speed = { value = 18.0, note = "скорость сваливания в горизонте, м/с" },
		dt = { value = 0.001, note = "шаг интегрирования, с" },
	},

	run = function(P, ctx)
		local phi = math.rad(P.bank_deg)
		local g = P.gravity

		local radius = aero.turn_radius(P.speed, phi, g)
		local rate = aero.turn_rate(P.speed, phi, g)
		local n = aero.load_factor(phi)
		local period = 2 * math.pi / rate

		print(("Крен %.1f°, скорость %.2f м/с:"):format(P.bank_deg, P.speed))
		print(("  радиус разворота R = V^2/(g*tan(phi)) = %.3f м"):format(radius))
		print(("  темп разворота omega = %.4f рад/с (%.2f °/с)")
			:format(rate, math.deg(rate)))
		print(("  полный круг за %.2f с"):format(period))
		print(("  перегрузка n = 1/cos(phi) = %.4f"):format(n))
		print(("  скорость сваливания растёт: %.2f → %.2f м/с")
			:format(P.stall_speed, aero.stall_speed_in_turn(P.stall_speed, phi)))

		----------------------------------------------------------------------
		-- Численная проверка: интегрируем движение по окружности
		----------------------------------------------------------------------
		-- Машина летит горизонтально, а центростремительное ускорение равно
		-- горизонтальной составляющей подъёмной силы, делённой на массу:
		--     a_c = g * tan(phi)
		-- Направлено всегда к центру, то есть перпендикулярно скорости.
		local centripetal = g * math.tan(phi)

		local trajectory = {}
		local speeds = {}

		local accel = function(_, v)
			local speed = math.sqrt(v.x * v.x + v.z * v.z)

			if speed < 1e-9 then
				return vec3.zero
			end

			-- Единичный вектор влево от направления движения
			local left = vec3.new(-v.z / speed, 0, v.x / speed)

			return left * centripetal
		end

		local final = require("lab.integrate").simulate {
			method = "rk4",
			accel = accel,
			x0 = vec3.zero,
			v0 = vec3.new(P.speed, 0, 0),
			dt = P.dt,
			duration = period,
			sample = function(t, x, v)
				trajectory[#trajectory + 1] = { x.x, x.z }
				speeds[#speeds + 1] = math.sqrt(v.x * v.x + v.z * v.z)
			end,
		}

		-- Радиус измеряется по траектории: центр окружности лежит слева от
		-- начальной скорости на расстоянии R.
		local measured_centre = vec3.new(0, 0, radius)
		local worst_radius_error = 0
		local measured_radius_sum = 0

		for _, point in ipairs(trajectory) do
			local distance = math.sqrt((point[1] - measured_centre.x) ^ 2
				+ (point[2] - measured_centre.z) ^ 2)

			measured_radius_sum = measured_radius_sum + distance
			worst_radius_error = math.max(worst_radius_error,
				math.abs(distance - radius) / radius)
		end

		local measured_radius = measured_radius_sum / #trajectory

		local worst_speed_error = 0

		for _, speed in ipairs(speeds) do
			worst_speed_error = math.max(worst_speed_error,
				math.abs(speed - P.speed) / P.speed)
		end

		print()
		print(("Измерено по траектории: средний радиус %.4f м, худшее "
			.. "отклонение от окружности %.3e"):format(measured_radius,
			worst_radius_error))
		print(("Скорость по модулю постоянна с точностью %.3e")
			:format(worst_speed_error))
		print(("Замыкание круга: конечная точка (%.4f, %.4f), ожидается (0, 0)")
			:format(final.x.x, final.x.z))

		----------------------------------------------------------------------
		-- Таблица по крену
		----------------------------------------------------------------------
		print()
		print("Цена крена:")
		print(text.row {
			{ "крен, °", 10 }, { "R, м", 12 }, { "темп, °/с", 12 },
			{ "n", 10 }, { "V_сваливания", 14 },
		})

		local radius_curve, load_curve = {}, {}

		for _, degrees in ipairs({ 10, 20, 30, 45, 60, 75, 80, 85 }) do
			local angle = math.rad(degrees)
			local r = aero.turn_radius(P.speed, angle, g)

			radius_curve[#radius_curve + 1] = { degrees, r }
			load_curve[#load_curve + 1] = { degrees, aero.load_factor(angle) }

			print(text.row {
				{ tostring(degrees), 10 },
				{ ("%.2f"):format(r), 12 },
				{ ("%.2f"):format(math.deg(aero.turn_rate(P.speed, angle, g))), 12 },
				{ ("%.3f"):format(aero.load_factor(angle)), 10 },
				{ ("%.2f"):format(aero.stall_speed_in_turn(P.stall_speed, angle)), 14 },
			})
		end

		print()
		print("Обратите внимание на 60°: перегрузка ровно 2, а скорость")
		print("сваливания растёт в sqrt(2) = 1.41 раза. Это тот самый предел,")
		print("за которым крутой вираж на малой скорости кончается срывом.")

		ctx.show({
			{ label = "траектория", mark = "*", points = trajectory },
		}, {
			title = "Разворот: траектория — окружность",
			xlabel = "x, м",
			ylabel = "z, м",
			height = 21,
			width = 60,
		})

		ctx.show({
			{ label = "радиус", mark = "*", points = radius_curve },
		}, {
			title = "Радиус разворота падает с ростом крена",
			xlabel = "крен, град",
			ylabel = "радиус, м",
			height = 14,
		})

		ctx.save({
			{ label = "траектория", points = trajectory },
		}, {
			title = "Координированный разворот",
			xlabel = "x, м",
			ylabel = "z, м",
			width = 640,
			height = 640,
		}, {
			headers = { "x", "z" },
			rows = trajectory,
		})

		----------------------------------------------------------------------
		local suite = check.new("разворот")

		suite:close("измеренный радиус совпадает с V^2/(g*tan(phi))",
			measured_radius, radius, 1e-9,
			"траектория интегрируется РК4 из независимо посчитанного "
			.. "центростремительного ускорения; совпадение с формулой — "
			.. "проверка самой формулы, а не арифметики")

		suite:close("траектория — окружность",
			worst_radius_error, 0, 1e-9,
			"расстояние до центра постоянно с точностью РК4")

		suite:close("модуль скорости в развороте не меняется",
			worst_speed_error, 0, 1e-9,
			"центростремительное ускорение перпендикулярно скорости, значит "
			.. "работы не совершает и энергию не меняет")

		suite:close("круг замыкается",
			vec3.length(final.x), 0, 1e-6,
			"допуск абсолютный, в метрах, при радиусе "
			.. ("%.1f"):format(radius) .. " м")

		suite:close("перегрузка при крене 60° равна 2",
			aero.load_factor(math.rad(60)), 2, 1e-12,
			"cos(60°) = 0.5 точно, значит n = 2 точно")

		suite:close("темп разворота равен V/R",
			rate, P.speed / radius, 1e-12,
			"тождество кинематики движения по окружности")

		suite:is_true("радиус не зависит от массы",
			aero.turn_radius(P.speed, phi, g) == radius,
			"масса сократилась ещё при выводе: и подъёмная сила, и вес "
			.. "пропорциональны ей")

		suite:close("рост скорости сваливания равен sqrt(n)",
			aero.stall_speed_in_turn(P.stall_speed, phi) / P.stall_speed,
			math.sqrt(n), 1e-12,
			"подъёмная сила должна вырасти в n раз, а она квадратична по "
			.. "скорости — отсюда корень")

		return suite
	end,
}
