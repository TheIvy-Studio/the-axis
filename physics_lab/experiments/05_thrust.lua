-- the Axis · physics lab · эксперимент 05
-- Тяга: разгон, максимальная скорость, потребная мощность.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local aero = require("lab.aero")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local R = require("lab.references")

return experiment.define {
	id = "05",
	name = "thrust",
	title = "Тяга и максимальная скорость",

	question = [[
Двигатель даёт постоянную тягу, сопротивление растёт как квадрат скорости.
Где машина упрётся в потолок скорости и как быстро она к нему выйдет?

Практический смысл: в моде тяга задана числом THRUST_PER_ENGINE, а потолок
скорости — отдельной константой MAX_SPEED. Это неправильно по сути: потолок
не независим, он ВЫВОДИТСЯ из тяги и сопротивления. Две независимые ручки на
одну величину — верный способ получить машину, которая либо не разгоняется,
либо упирается в невидимую стену.]],

	model = [[
    m * dv/dt = T - k*v^2,    k = 0.5*Cd*rho*A                [Н]

Установившаяся скорость (dv/dt = 0):
    V_max = sqrt(T/k) = sqrt(2*T / (Cd*rho*A))                [м/с]

Замкнутое решение разгона с нуля (уравнение разделяется, интеграл даёт
артангенс гиперболический):
    v(t) = V_max * tanh(t / tau),   tau = m*V_max / T          [с]

Проверка размерности tau: [кг]·[м/с]/[Н] = [кг·м/с]/[кг·м/с^2] = [с]. Сходится.

Отсюда сразу три полезных следствия:
  * потолок скорости растёт как КОРЕНЬ из тяги: вчетверо больше двигателей —
    вдвое быстрее, не вчетверо;
  * потребная мощность P = T*V на потолке растёт как V^3;
  * время выхода на 99 % потолка равно tau*artanh(0.99) = 2.6*tau.]],

	simplifications = [[
1. Тяга постоянна и не зависит от скорости. У настоящего винта тяга падает с
   ростом скорости (винт «раскручивается» относительно набегающего потока),
   у реактивного двигателя — почти постоянна. Для игры постоянная тяга
   разумна, но реальный винтовой самолёт разгоняется хуже, чем показывает
   эта модель.
2. Движение прямолинейное и горизонтальное: нет ни подъёмной силы, ни
   индуктивного сопротивления. С ними потолок будет ниже (см. эксперимент 06).]],

	references = { R.nasa_drag_equation, R.nasa_flight_equations_drag },

	params = {
		mass = { value = 1500.0, note = "масса машины, кг" },
		thrust = { value = 6000.0, note = "суммарная тяга, Н" },
		cd = { value = 1.05, note = "коэффициент сопротивления" },
		rho = { value = 1.225, note = "плотность воздуха, кг/м^3" },
		area = { value = 9.0, note = "площадь миделя, м^2" },
		duration = { value = 40.0, note = "длительность разгона, с" },
		dt = { value = 0.002, note = "шаг интегрирования, с" },
	},

	run = function(P, ctx)
		local k = 0.5 * P.cd * P.rho * P.area
		local v_max = math.sqrt(P.thrust / k)
		local tau = P.mass * v_max / P.thrust

		print(("k = 0.5*Cd*rho*A            = %.6f кг/м"):format(k))
		print(("V_max = sqrt(T/k)           = %.6f м/с  (%.1f км/ч)")
			:format(v_max, v_max * 3.6))
		print(("tau = m*V_max/T             = %.6f с"):format(tau))
		print(("мощность на потолке P = T*V = %.1f Вт (%.1f л.с.)")
			:format(P.thrust * v_max, P.thrust * v_max / 735.5))
		print(("начальное ускорение T/m     = %.4f м/с^2"):format(P.thrust / P.mass))

		local function exact_v(t) return v_max * math.tanh(t / tau) end

		local accel = function(_, v)
			local speed = v.x
			local drag = k * speed * math.abs(speed)

			return vec3.new((P.thrust - drag) / P.mass, 0, 0)
		end

		local numeric, analytic = {}, {}
		local worst = 0

		local final = integrate.simulate {
			method = "rk4",
			accel = accel,
			x0 = vec3.zero,
			v0 = vec3.zero,
			dt = P.dt,
			duration = P.duration,
			sample = function(t, x, v)
				local exact = exact_v(t)

				numeric[#numeric + 1] = { t, v.x }
				analytic[#analytic + 1] = { t, exact }

				if t > 0.1 then
					worst = math.max(worst, math.abs(v.x - exact) / exact)
				end
			end,
		}

		print()
		print(("Худшее относительное расхождение с tanh-решением: %.3e"):format(worst))
		print()

		for _, fraction in ipairs({ 0.5, 0.9, 0.99 }) do
			local artanh = 0.5 * math.log((1 + fraction) / (1 - fraction))

			print(("  %.0f %% потолка (%.2f м/с) набирается за %.3f с")
				:format(fraction * 100, fraction * v_max, tau * artanh))
		end

		----------------------------------------------------------------------
		-- Как потолок зависит от тяги
		----------------------------------------------------------------------
		local thrust_curve = {}

		for index = 1, 40 do
			local thrust = P.thrust * index / 10
			thrust_curve[#thrust_curve + 1] = { thrust, math.sqrt(thrust / k) }
		end

		print()
		print("Потолок скорости растёт как корень из тяги:")

		for _, factor in ipairs({ 1, 2, 4, 9 }) do
			print(("  тяга x%-2d → потолок x%.4f (ожидается x%.4f)")
				:format(factor, math.sqrt(P.thrust * factor / k) / v_max,
					math.sqrt(factor)))
		end

		ctx.show({
			{ label = "РК4", mark = "*", points = numeric },
			{ label = "V_max*tanh(t/tau)", mark = "-", points = analytic },
		}, {
			title = "Разгон под постоянной тягой",
			xlabel = "время, с",
			ylabel = "скорость, м/с",
		})

		ctx.show({
			{ label = "потолок", mark = "*", points = thrust_curve },
		}, {
			title = "Потолок скорости в зависимости от тяги (корневая зависимость)",
			xlabel = "тяга, Н",
			ylabel = "V_max, м/с",
			height = 14,
		})

		ctx.save({
			{ label = "численно", points = numeric },
			{ label = "замкнутое решение", points = analytic, dashed = true },
		}, {
			title = "Разгон под постоянной тягой",
			xlabel = "время, с",
			ylabel = "скорость, м/с",
		}, {
			headers = { "t", "v_numeric", "v_exact" },
			rows = (function()
				local rows = {}

				for index, point in ipairs(numeric) do
					rows[index] = { point[1], point[2], analytic[index][2] }
				end

				return rows
			end)(),
		})

		----------------------------------------------------------------------
		local suite = check.new("тяга")

		suite:close("на потолке тяга равна сопротивлению",
			aero.drag_force(P.cd, P.rho, v_max, P.area), P.thrust, 1e-12,
			"определение потолка: dv/dt = 0 означает T = D, это тождество")

		suite:close("численное решение сходится к замкнутому",
			worst, 0, 1e-9,
			"РК4 с шагом 2 мс на гладкой задаче даёт ошибку далеко ниже "
			.. "накопленного округления за 20000 шагов")

		-- Потолок достигается только асимптотически, поэтому проверяется
		-- остаток, а не равенство.
		suite:close("недобор до потолка равен 1 - tanh(T/tau)",
			(v_max - final.v.x) / v_max,
			1 - math.tanh(P.duration / tau), 1e-8,
			"аналитический остаток при t = " .. tostring(P.duration)
			.. " с; за " .. ("%.1f"):format(P.duration / tau)
			.. " постоянных времени он равен "
			.. ("%.2e"):format(1 - math.tanh(P.duration / tau)))

		suite:close("четырёхкратная тяга даёт двукратный потолок",
			math.sqrt(P.thrust * 4 / k) / v_max, 2, 1e-12,
			"следствие корневой зависимости, точное отношение")

		suite:close("время до 99 % потолка равно 2.6*tau",
			tau * 0.5 * math.log(1.99 / 0.01) / tau,
			0.5 * math.log(199), 1e-12,
			"artanh(0.99) = 2.6467, это чистая арифметика")

		suite:is_true("начальное ускорение равно T/m",
			math.abs(accel(vec3.zero, vec3.zero).x - P.thrust / P.mass) < 1e-12,
			"при нулевой скорости сопротивления нет, остаётся второй закон "
			.. "Ньютона в чистом виде")

		return suite
	end,
}
