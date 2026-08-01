-- the Axis · physics lab · эксперимент 02
-- Тяжесть: свободное падение и баллистическая траектория без сопротивления.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local R = require("lab.references")

return experiment.define {
	id = "02",
	name = "gravity",
	title = "Тяжесть и баллистика",

	question = [[
Как ведёт себя тело под действием одной только тяжести и совпадает ли это с
формулами баллистики? Отдельно: та самая «дуга», которой не было у машины в
моде — она берётся не из специального кода, а сама собой, если горизонтальная
скорость не гасится.]],

	model = [[
    a = (0, -g, 0),   g = 9.81 м/с^2 (значение движка Luanti)

Горизонталь и вертикаль независимы: тяжесть не имеет горизонтальной
составляющей, поэтому

    x(t) = v0*cos(theta)*t                                   [м]
    y(t) = v0*sin(theta)*t - g*t^2/2                         [м]

Отсюда стандартные результаты баллистики (без сопротивления):

    время полёта   T = 2*v0*sin(theta)/g                     [с]
    дальность      R = v0^2 * sin(2*theta) / g               [м]
    высота апогея  H = v0^2 * sin^2(theta) / (2*g)            [м]

Максимум дальности — при theta = 45 градусов, потому что sin(2*theta)
достигает единицы. Траектория — парабола: выразив t через x и подставив,
получаем y квадратичной функцией от x.

Стандартное g0 = 9.80665 м/с^2 закреплено определением [si_brochure], но
Luanti использует 9.81, и в расчётах надо брать именно игровое значение,
иначе конструкция и игрок падают по-разному.]],

	simplifications = [[
Нет сопротивления воздуха. Это осознанно: сюда добавляется только тяжесть,
чтобы отделить её вклад от аэродинамики (эксперименты 03 и 04). С
сопротивлением траектория перестаёт быть параболой — она становится
несимметричной, нисходящая ветвь круче восходящей, а дальность падает.
Для тела с малой парусностью на игровых скоростях разница мала, для
воксельной машины — огромна.]],

	references = { R.si_brochure, R.nasa_falling_object },

	params = {
		gravity = { value = 9.81, note = "ускорение падения, м/с^2 (значение Luanti)" },
		speed = { value = 30.0, note = "начальная скорость, м/с" },
		angle_deg = { value = 45.0, note = "угол броска, градусы" },
		drop_height = { value = 100.0, note = "высота свободного падения, м" },
		dt = { value = 0.001, note = "шаг интегрирования, с" },
	},

	run = function(P, ctx)
		local g = P.gravity
		local theta = math.rad(P.angle_deg)

		----------------------------------------------------------------------
		-- Свободное падение
		----------------------------------------------------------------------
		local fall_time = math.sqrt(2 * P.drop_height / g)
		local impact_speed = g * fall_time

		print("Свободное падение:")
		print(("  высота %.4g м → время %.6f с, скорость удара %.6f м/с")
			:format(P.drop_height, fall_time, impact_speed))
		print(("  проверка через энергию: v = sqrt(2*g*h) = %.6f м/с")
			:format(math.sqrt(2 * g * P.drop_height)))

		local accel = function() return vec3.new(0, -g, 0) end

		local fall_state = integrate.simulate {
			-- РК4 воспроизводит параболу точно, поэтому проверяется именно
			-- кинематика, а не ошибка усечения схемы (она измерена в 01).
			method = "rk4",
			accel = accel,
			x0 = vec3.new(0, P.drop_height, 0),
			v0 = vec3.zero,
			dt = P.dt,
			duration = fall_time,
		}

		----------------------------------------------------------------------
		-- Баллистика
		----------------------------------------------------------------------
		local flight_time = 2 * P.speed * math.sin(theta) / g
		local range = P.speed * P.speed * math.sin(2 * theta) / g
		local apex = P.speed * P.speed * math.sin(theta) ^ 2 / (2 * g)

		print()
		print(("Бросок %.4g м/с под %.4g°:"):format(P.speed, P.angle_deg))
		print(("  время полёта T = 2*v0*sin(th)/g       = %.6f с"):format(flight_time))
		print(("  дальность    R = v0^2*sin(2*th)/g     = %.6f м"):format(range))
		print(("  апогей       H = v0^2*sin^2(th)/(2g)  = %.6f м"):format(apex))

		local trajectory = {}
		local measured_apex = -math.huge

		local ballistic = integrate.simulate {
			method = "rk4",
			accel = accel,
			x0 = vec3.zero,
			v0 = vec3.new(P.speed * math.cos(theta), P.speed * math.sin(theta), 0),
			dt = P.dt,
			duration = flight_time,
			sample = function(_, x)
				trajectory[#trajectory + 1] = { x.x, x.y }
				measured_apex = math.max(measured_apex, x.y)
			end,
		}

		----------------------------------------------------------------------
		-- Зависимость дальности от угла
		----------------------------------------------------------------------
		local range_curve = {}
		local best_angle, best_range = 0, -1

		for degrees = 0, 90 do
			local a = math.rad(degrees)
			local r = P.speed * P.speed * math.sin(2 * a) / g

			range_curve[#range_curve + 1] = { degrees, r }

			if r > best_range then
				best_range, best_angle = r, degrees
			end
		end

		print(("  максимум дальности достигается при %d° (ожидается 45°)")
			:format(best_angle))

		ctx.show({ { label = "траектория", mark = "*", points = trajectory } }, {
			title = "Баллистическая траектория (парабола)",
			xlabel = "дальность, м",
			ylabel = "высота, м",
		})

		ctx.show({ { label = "дальность", mark = "*", points = range_curve } }, {
			title = "Дальность в зависимости от угла броска",
			xlabel = "угол, град",
			ylabel = "дальность, м",
			height = 14,
		})

		ctx.save({
			{ label = "траектория", points = trajectory },
		}, {
			title = "Баллистика без сопротивления",
			xlabel = "дальность, м",
			ylabel = "высота, м",
		}, {
			headers = { "x", "y" },
			rows = trajectory,
		})

		----------------------------------------------------------------------
		local suite = check.new("тяжесть и баллистика")

		suite:close("скорость удара при падении",
			-fall_state.v.y, impact_speed, 1e-9,
			"скорость линейна по времени, РК4 воспроизводит её точно; "
			.. "остаётся только двоичное округление")

		suite:close("высота в момент удара близка к нулю",
			fall_state.x.y, 0, 1e-9,
			"допуск абсолютный: парабола воспроизводится РК4 точно, шаг "
			.. "подогнан под длительность, остаётся только округление")

		suite:close("дальность броска",
			ballistic.x.x, range, 1e-9,
			"РК4 точен на многочленах до 4-й степени, а траектория — парабола")

		suite:close("высота возврата к земле",
			ballistic.x.y, 0, 1e-9,
			"та же причина: РК4 воспроизводит параболу без ошибки усечения")

		suite:close("апогей",
			measured_apex, apex, 1e-4,
			"апогей ловится по выборке с шагом dt, поэтому промах по времени "
			.. "до dt/2 даёт ошибку порядка g*dt^2/8")

		suite:close("угол максимальной дальности",
			best_angle, 45, 1e-12,
			"sin(2*theta) максимален при theta = 45°, это точное утверждение")

		suite:is_true("горизонтальная скорость не меняется",
			math.abs(ballistic.v.x - P.speed * math.cos(theta)) < 1e-9,
			"у тяжести нет горизонтальной составляющей; именно поэтому "
			.. "падающая машина летит по дуге, а не сваливается колом")

		return suite
	end,
}
