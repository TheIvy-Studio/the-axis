-- the Axis · physics lab · эксперимент 04
-- Падение и подъём с сопротивлением воздуха. Предельная скорость.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local aero = require("lab.aero")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local R = require("lab.references")

return experiment.define {
	id = "04",
	name = "air_resistance",
	title = "Сопротивление воздуха и предельная скорость",

	question = [[
Тело падает и разгоняется, сопротивление растёт как квадрат скорости и рано
или поздно уравновешивает вес. Где именно это происходит, по какому закону
разгон выходит на полку и совпадает ли численное решение с замкнутым?

Это ключевой эксперимент для мода: он даёт правильную форму падения
конструкции.]],

	model = [[
Баланс сил при падении [nasa_falling_object], дословно:
    F = W - D ;  a = (W - D)/m ;  D = Cd*(r*V^2*A)/2 ;  W = m*g

Обозначим k = 0.5*Cd*rho*A  [кг/м], тогда

    m * dv/dt = m*g - k*v^2                                  (вниз положительно)

Установившееся движение (dv/dt = 0) даёт предельную скорость
    V_t = sqrt(m*g/k) = sqrt(2*m*g/(Cd*rho*A))               [м/с]
что дословно совпадает с формулой NASA [nasa_flight_equations_drag].

Уравнение разделяется. Для падения из состояния покоя:
    v(t) = V_t * tanh(g*t / V_t)                             [м/с]
    y(t) = (V_t^2/g) * ln(cosh(g*t / V_t))                   [м]

Форму через tanh страницы NASA не приводят, поэтому она здесь не
постулируется, а ПРОВЕРЯЕТСЯ двумя независимыми способами:
  1) подстановкой в исходное уравнение (невязка должна быть машинным нулём);
  2) сравнением с РК4 на мелком шаге.

Для подъёма (движение вверх, сопротивление тоже вниз) NASA даёт замкнутое
решение дословно:
    V/V_t = (V_0 - V_t*tan(g*t/V_t)) / (V_t + V_0*tan(g*t/V_t))
    y = (V_t^2 / 2g) * ln((V_0^2 + V_t^2)/(V^2 + V_t^2))
Оба выражения проверяются против численного решения.

Смена tanh на tan при смене знака движения не случайность: на подъёме
сопротивление и тяжесть складываются, и знак в уравнении меняется, а вместе
с ним гиперболические функции переходят в тригонометрические.]],

	simplifications = [[
Плотность воздуха постоянна. На высотах в сотни метров это даёт ошибку
предельной скорости меньше 2 % (rho падает как exp(-h/8434)). Для реального
затяжного прыжка с 4 км так считать уже нельзя.
Cd постоянен — см. эксперимент 03.]],

	references = { R.nasa_falling_object, R.nasa_flight_equations_drag },

	params = {
		mass = { value = 1000.0, note = "масса, кг (машина ~2000 блоков дерева)" },
		gravity = { value = 9.81, note = "ускорение падения, м/с^2" },
		cd = { value = 1.05, note = "коэффициент сопротивления" },
		rho = { value = 1.225, note = "плотность воздуха, кг/м^3" },
		area = { value = 9.0, note = "площадь миделя, м^2" },
		duration = { value = 30.0, note = "длительность падения, с" },
		dt = { value = 0.001, note = "шаг интегрирования, с" },
		launch_speed = { value = 60.0, note = "начальная скорость броска вверх, м/с" },
	},

	run = function(P, ctx)
		local g = P.gravity
		local k = 0.5 * P.cd * P.rho * P.area
		local vt = aero.terminal_velocity(P.mass, g, P.cd, P.rho, P.area)

		print(("k = 0.5*Cd*rho*A          = %.6f кг/м"):format(k))
		print(("V_t = sqrt(m*g/k)         = %.6f м/с"):format(math.sqrt(P.mass * g / k)))
		print(("V_t = sqrt(2mg/(Cd*rho*A))= %.6f м/с   (формула NASA)"):format(vt))
		print(("характерное время V_t/g   = %.6f с"):format(vt / g))

		----------------------------------------------------------------------
		-- Замкнутое решение для падения
		----------------------------------------------------------------------
		local function exact_v(t) return vt * math.tanh(g * t / vt) end

		local function exact_y(t)
			-- ln(cosh(z)) считается напрямую только при малых z: cosh(z)
			-- переполняется уже при z ≈ 710. Устойчивая форма:
			-- ln(cosh z) = z + ln(1 + exp(-2z)) - ln 2
			local z = g * t / vt

			if z < 20 then
				return (vt * vt / g) * math.log(math.cosh(z))
			end

			-- ln(cosh z) = z + ln(1 + exp(-2z)) - ln 2
			return (vt * vt / g)
				* (z + math.log(1 + math.exp(-2 * z)) - math.log(2))
		end

		----------------------------------------------------------------------
		-- Невязка: подставляем решение обратно в уравнение
		----------------------------------------------------------------------
		local worst_residual = 0

		for step = 1, 200 do
			local t = P.duration * step / 200
			local v = exact_v(t)

			-- Численная производная центральной разностью
			local h = 1e-5
			local dv_dt = (exact_v(t + h) - exact_v(t - h)) / (2 * h)
			local expected = g - k * v * v / P.mass

			-- Нормируем на g, а не на само значение: у предельной скорости
			-- правая часть стремится к нулю, и относительная ошибка там
			-- потеряла бы смысл.
			worst_residual = math.max(worst_residual,
				math.abs(dv_dt - expected) / g)
		end

		print()
		print(("Невязка подстановки v(t) = V_t*tanh(g*t/V_t) в уравнение: %.3e")
			:format(worst_residual))

		----------------------------------------------------------------------
		-- Численное решение падения
		----------------------------------------------------------------------
		local accel = function(_, v)
			-- Сопротивление всегда против движения, поэтому знак берётся от
			-- скорости, а не «минус всегда». Без этого тело, летящее вверх,
			-- получало бы разгоняющее сопротивление.
			local speed = v.y
			local drag = k * speed * math.abs(speed) / P.mass

			return vec3.new(0, -g - drag, 0)
		end

		local numeric, analytic_v, error_curve = {}, {}, {}
		local worst_error = 0

		local final = integrate.simulate {
			method = "rk4",
			accel = accel,
			x0 = vec3.zero,
			v0 = vec3.zero,
			dt = P.dt,
			duration = P.duration,
			sample = function(t, x, v)
				local speed = -v.y
				local exact = exact_v(t)

				numeric[#numeric + 1] = { t, speed }
				analytic_v[#analytic_v + 1] = { t, exact }

				if t > 0 then
					local relative = math.abs(speed - exact) / math.max(exact, 1e-9)
					error_curve[#error_curve + 1] = { t, relative }
					worst_error = math.max(worst_error, relative)
				end
			end,
		}

		print(("Худшее относительное расхождение РК4 и tanh-решения: %.3e")
			:format(worst_error))
		print()
		print(("При t = %.4g с: скорость %.6f м/с (%.2f %% от предельной), путь %.4f м")
			:format(P.duration, -final.v.y, -final.v.y / vt * 100, -final.x.y))
		print(("Замкнутое решение:  скорость %.6f м/с, путь %.4f м")
			:format(exact_v(P.duration), exact_y(P.duration)))

		-- Сколько нужно, чтобы набрать долю предельной скорости
		print()

		for _, fraction in ipairs({ 0.5, 0.9, 0.99 }) do
			-- t = (V_t/g) * artanh(fraction)
			local artanh = 0.5 * math.log((1 + fraction) / (1 - fraction))

			print(("  %.0f %% предельной скорости достигается за %.3f с (падение %.1f м)")
				:format(fraction * 100, vt / g * artanh, exact_y(vt / g * artanh)))
		end

		----------------------------------------------------------------------
		-- Подъём: формулы NASA
		----------------------------------------------------------------------
		local v0 = P.launch_speed
		local rise_time = (vt / g) * math.atan(v0 / vt)

		local function nasa_ascent_v(t)
			local tangent = math.tan(g * t / vt)

			return vt * (v0 - vt * tangent) / (vt + v0 * tangent)
		end

		local function nasa_ascent_y(v)
			return (vt * vt / (2 * g))
				* math.log((v0 * v0 + vt * vt) / (v * v + vt * vt))
		end

		local ascent_numeric, ascent_analytic = {}, {}
		local worst_ascent = 0

		integrate.simulate {
			method = "rk4",
			accel = accel,
			x0 = vec3.zero,
			v0 = vec3.new(0, v0, 0),
			dt = P.dt,
			duration = rise_time,
			sample = function(t, x, v)
				local exact = nasa_ascent_v(t)

				ascent_numeric[#ascent_numeric + 1] = { t, v.y }
				ascent_analytic[#ascent_analytic + 1] = { t, exact }

				if t > 0 then
					worst_ascent = math.max(worst_ascent,
						math.abs(v.y - exact) / math.max(math.abs(exact), 1))
				end
			end,
		}

		local peak_numeric = ascent_numeric[#ascent_numeric]

		print()
		print(("Подъём с начальной скоростью %.4g м/с:"):format(v0))
		print(("  время до вершины (V_t/g)*atan(V_0/V_t) = %.6f с"):format(rise_time))
		print(("  высота по формуле NASA                 = %.6f м")
			:format(nasa_ascent_y(0)))
		print(("  высота без сопротивления V_0^2/(2g)    = %.6f м")
			:format(v0 * v0 / (2 * g)))
		print(("  худшее расхождение с численным решением: %.3e"):format(worst_ascent))
		print(("  скорость на вершине по численному решению: %.3e м/с")
			:format(peak_numeric[2]))

		----------------------------------------------------------------------
		ctx.show({
			{ label = "РК4", mark = "*", points = numeric },
			{ label = "V_t*tanh(g*t/V_t)", mark = "-", points = analytic_v },
		}, {
			title = "Разгон при падении выходит на предельную скорость",
			xlabel = "время, с",
			ylabel = "скорость, м/с",
		})

		ctx.save({
			{ label = "численно (РК4)", points = numeric },
			{ label = "замкнутое решение", points = analytic_v, dashed = true },
		}, {
			title = "Падение с квадратичным сопротивлением",
			xlabel = "время, с",
			ylabel = "скорость, м/с",
		}, {
			headers = { "t", "v_numeric", "v_exact" },
			rows = (function()
				local rows = {}

				for index, point in ipairs(numeric) do
					rows[index] = { point[1], point[2], analytic_v[index][2] }
				end

				return rows
			end)(),
		})

		----------------------------------------------------------------------
		local suite = check.new("сопротивление воздуха")

		suite:close("две записи предельной скорости совпадают",
			vt, math.sqrt(P.mass * g / k), 1e-12,
			"sqrt(m*g/k) и sqrt(2mg/(Cd*rho*A)) — одно и то же после "
			.. "подстановки k; расхождение только от округления")

		suite:close("решение через tanh удовлетворяет уравнению",
			worst_residual, 0, 1e-6,
			"невязка нормирована на g и считается центральной разностью с "
			.. "шагом 1e-5: её собственная точность ограничена вычитанием "
			.. "близких чисел, это примерно eps/h = 2e-11")

		suite:close("РК4 совпадает с замкнутым решением",
			worst_error, 0, 1e-8,
			"глобальная ошибка РК4 порядка dt^4 = 1e-12, реально ограничена "
			.. "накоплением округления на 30000 шагах")

		-- Скорость НЕ равна предельной за конечное время: она подходит к ней
		-- как tanh. Проверяем именно остаток — так утверждение осмысленно.
		suite:close("недобор до предельной скорости равен 1 - tanh(g*T/V_t)",
			(vt + final.v.y) / vt, 1 - math.tanh(g * P.duration / vt), 1e-6,
			"аналитическое значение недобора при t = " .. tostring(P.duration)
			.. " с; допуск покрывает ошибку РК4 на 30000 шагах")

		suite:close("путь совпадает с (V_t^2/g)*ln(cosh(g*t/V_t))",
			-final.x.y, exact_y(P.duration), 1e-8,
			"та же точность РК4, накопленная по положению")

		suite:close("формула подъёма NASA совпадает с численным решением",
			worst_ascent, 0, 1e-7,
			"расхождение нормировано на масштаб скорости; проверяется именно "
			.. "дословная формула с сайта NASA")

		suite:close("на вершине подъёма скорость нулевая",
			peak_numeric[2], 0, 1e-6,
			"допуск абсолютный: шаг подогнан под аналитическое время вершины, "
			.. "поэтому остаётся только ошибка РК4")

		suite:is_true("высота подъёма меньше, чем без сопротивления",
			nasa_ascent_y(0) < v0 * v0 / (2 * g),
			"сопротивление на подъёме складывается с тяжестью, значит "
			.. "тормозит сильнее и тело не долетает до баллистической высоты")

		return suite
	end,
}
