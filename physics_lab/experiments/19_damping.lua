-- the Axis · physics lab · эксперимент 19
-- Затухание: линейное против квадратичного, критическое демпфирование.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "19",
	name = "damping",
	title = "Затухание и демпфирование",

	question = [[
Чем линейное торможение отличается от квадратичного, и почему это не вопрос
вкуса? И какое демпфирование считать «правильным», когда нужно вернуть
что-то в исходное положение побыстрее и без раскачки?]],

	model = [[
ЛИНЕЙНОЕ торможение (вязкое трение, закон Стокса):
    m*dv/dt = -c*v
    v(t) = v0*exp(-t/tau),   tau = m/c                        [с]
    путь до остановки s = v0*tau                              [м] — КОНЕЧЕН

КВАДРАТИЧНОЕ торможение (сопротивление воздуха, эксперимент 03):
    m*dv/dt = -k*v^2,   k = 0.5*Cd*rho*A
    v(t) = v0 / (1 + v0*k*t/m)                                [м/с]
    s(t) = (m/k)*ln(1 + v0*k*t/m)                             [м] — РАСТЁТ БЕЗ ГРАНИЦЫ

Разница качественная, а не количественная. При линейном торможении тело
проходит конечный путь и практически останавливается. При квадратичном
скорость падает лишь как 1/t, а путь растёт логарифмически — тело никогда не
останавливается совсем и уезжает сколь угодно далеко, если ждать достаточно
долго. Для игры это означает: машина, тормозимая квадратичным сопротивлением,
будет долго ползти. Останов требует отдельного механизма (трение о землю).

Какой закон физически верен, определяется числом Рейнольдса: линейный при
Re << 1 (пылинка в масле), квадратичный при Re порядка 10^4...10^6 (всё, что
крупнее сантиметра и быстрее сантиметра в секунду). Для воксельной машины —
только квадратичный.

ДЕМПФИРОВАНИЕ пружины:
    m*d2x/dt2 = -k*x - c*dx/dt
    w = sqrt(k/m),   zeta = c / (2*sqrt(k*m))                 [—]

    zeta < 1  недодемпфировано: перелёт и колебания
    zeta = 1  критическое: возврат без перелёта, самый быстрый
    zeta > 1  передемпфировано: без перелёта, но медленнее

Величина перелёта при zeta < 1 считается точно:
    перелёт = exp(-pi*zeta / sqrt(1 - zeta^2))                [доля]

Критическое демпфирование — не «золотая середина», а точка, где два
собственных значения сливаются. Именно оно даёт самый быстрый возврат без
перелёта, и это доказуемо, а не эмпирика.]],

	simplifications = [[
Линейное торможение в игре иногда всё же полезно — например, чтобы машина
уверенно останавливалась. Но тогда это надо называть своим именем: не
«сопротивление воздуха», а искусственное торможение, введённое ради
управляемости.]],

	references = { R.nasa_drag_equation, R.hairer_odes },

	params = {
		mass = { value = 1000.0, note = "масса, кг" },
		speed = { value = 20.0, note = "начальная скорость, м/с" },
		linear_c = { value = 200.0, note = "коэффициент линейного торможения, кг/с" },
		quadratic_k = { value = 10.0, note = "коэффициент квадратичного торможения, кг/м" },
		duration = { value = 30.0, note = "длительность, с" },
		dt = { value = 0.001, note = "шаг интегрирования, с" },
		omega = { value = 3.0, note = "собственная частота пружины, рад/с" },
	},

	run = function(P, ctx)
		local m = P.mass
		local tau = m / P.linear_c

		print(("Линейное торможение: tau = m/c = %.4f с, путь до остановки "
			.. "v0*tau = %.4f м"):format(tau, P.speed * tau))

		local quad_scale = m / (P.quadratic_k * P.speed)

		print(("Квадратичное: характерное время m/(k*v0) = %.4f с, путь "
			.. "растёт как ln"):format(quad_scale))

		----------------------------------------------------------------------
		-- Два закона рядом
		----------------------------------------------------------------------
		local function linear_v(t) return P.speed * math.exp(-t / tau) end
		local function linear_s(t) return P.speed * tau * (1 - math.exp(-t / tau)) end

		local function quad_v(t)
			return P.speed / (1 + P.speed * P.quadratic_k * t / m)
		end

		local function quad_s(t)
			return (m / P.quadratic_k)
				* math.log(1 + P.speed * P.quadratic_k * t / m)
		end

		local linear_accel = function(_, v)
			return vec3.new(-P.linear_c * v.x / m, 0, 0)
		end

		local quad_accel = function(_, v)
			return vec3.new(-P.quadratic_k * v.x * math.abs(v.x) / m, 0, 0)
		end

		local worst_linear, worst_quad = 0, 0
		local linear_curve, quad_curve = {}, {}

		local linear_final = integrate.simulate {
			method = "rk4",
			accel = linear_accel,
			x0 = vec3.zero,
			v0 = vec3.new(P.speed, 0, 0),
			dt = P.dt,
			duration = P.duration,
			sample = function(t, x, v)
				linear_curve[#linear_curve + 1] = { t, v.x }

				if t > 0 then
					worst_linear = math.max(worst_linear,
						math.abs(v.x - linear_v(t)) / P.speed)
				end
			end,
		}

		local quad_final = integrate.simulate {
			method = "rk4",
			accel = quad_accel,
			x0 = vec3.zero,
			v0 = vec3.new(P.speed, 0, 0),
			dt = P.dt,
			duration = P.duration,
			sample = function(t, x, v)
				quad_curve[#quad_curve + 1] = { t, v.x }

				if t > 0 then
					worst_quad = math.max(worst_quad,
						math.abs(v.x - quad_v(t)) / P.speed)
				end
			end,
		}

		print()
		print(text.row {
			{ "время, с", 12 }, { "линейно v", 14 }, { "линейно s", 14 },
			{ "квадратично v", 16 }, { "квадратично s", 16 },
		})

		for _, t in ipairs({ 1, 5, 10, 30, 100, 1000, 10000 }) do
			print(text.row {
				{ tostring(t), 12 },
				{ ("%.6g"):format(linear_v(t)), 14 },
				{ ("%.4f"):format(linear_s(t)), 14 },
				{ ("%.6g"):format(quad_v(t)), 16 },
				{ ("%.4f"):format(quad_s(t)), 16 },
			})
		end

		print()
		print(("Линейное торможение: путь сходится к %.4f м и дальше не растёт.")
			:format(P.speed * tau))
		print("Квадратичное: путь растёт логарифмически и предела не имеет.")
		print("Скорость при этом падает как 1/t, а не экспоненциально.")

		----------------------------------------------------------------------
		-- Демпфирование пружины
		----------------------------------------------------------------------
		local w = P.omega

		print()
		print(("Пружина с собственной частотой w = %.2f рад/с:"):format(w))
		print()
		print(text.row {
			{ "zeta", 10 }, { "режим", 24 }, { "перелёт", 14 },
			{ "формула", 14 }, { "время до 2 %", 16 },
		})

		local overshoot_error = 0
		local settle_times = {}
		local overshoot_curve = {}
		local traces = {}

		for _, zeta in ipairs({ 0.1, 0.3, 0.5, 0.7, 1.0, 1.5, 2.5 }) do
			local accel = function(x, v)
				return vec3.new(-w * w * x.x - 2 * zeta * w * v.x, 0, 0)
			end

			local peak = 0
			local settle = nil
			local trace = {}

			integrate.simulate {
				method = "rk4",
				accel = accel,
				x0 = vec3.new(1, 0, 0),
				v0 = vec3.zero,
				dt = P.dt,
				duration = 12,
				sample = function(t, x)
					-- Перелёт — это заход за ноль (цель) в отрицательную сторону
					peak = math.max(peak, -x.x)

					if #trace < 3000 then
						trace[#trace + 1] = { t, x.x }
					end

					if math.abs(x.x) > 0.02 then
						settle = t
					end
				end,
			}

			local predicted = zeta < 1
				and math.exp(-math.pi * zeta / math.sqrt(1 - zeta * zeta))
				or 0

			if zeta < 1 then
				overshoot_error = math.max(overshoot_error,
					math.abs(peak - predicted) / predicted)
			end

			settle_times[zeta] = settle or 0
			overshoot_curve[#overshoot_curve + 1] = { zeta, peak }
			traces[#traces + 1] = {
				label = "zeta = " .. tostring(zeta),
				mark = tostring(zeta):sub(1, 1) == "1" and "c" or "z",
				points = trace,
			}

			print(text.row {
				{ ("%.1f"):format(zeta), 10 },
				{ zeta < 1 and "недодемпфировано"
					or (zeta == 1 and "критическое" or "передемпфировано"), 24 },
				{ ("%.6f"):format(peak), 14 },
				{ ("%.6f"):format(predicted), 14 },
				{ ("%.4f"):format(settle or 0), 16 },
			})
		end

		print()
		print(("Критическое демпфирование (zeta = 1) возвращает в ноль за "
			.. "%.4f с без перелёта."):format(settle_times[1.0]))
		print(("Передемпфированное (zeta = 2.5) — за %.4f с, то есть МЕДЛЕННЕЕ.")
			:format(settle_times[2.5]))
		print("«Побольше демпфирования» не значит «быстрее успокоится».")

		ctx.show({
			{ label = "линейное", mark = "l", points = linear_curve },
			{ label = "квадратичное", mark = "q", points = quad_curve },
		}, {
			title = "Затухание скорости: экспонента против 1/t",
			xlabel = "время, с",
			ylabel = "скорость, м/с",
		})

		ctx.show({
			{ label = "перелёт", mark = "*", points = overshoot_curve },
		}, {
			title = "Перелёт в зависимости от коэффициента затухания",
			xlabel = "zeta",
			ylabel = "перелёт, доля",
			height = 14,
		})

		ctx.save({
			{ label = "линейное", points = linear_curve },
			{ label = "квадратичное", points = quad_curve },
		}, {
			title = "Линейное и квадратичное торможение",
			xlabel = "время, с",
			ylabel = "скорость, м/с",
		}, {
			headers = { "t", "linear_v", "quadratic_v" },
			rows = (function()
				local rows = {}

				for index, point in ipairs(linear_curve) do
					rows[index] = { point[1], point[2], quad_curve[index][2] }
				end

				return rows
			end)(),
		})

		----------------------------------------------------------------------
		local suite = check.new("затухание")

		suite:close("линейное торможение даёт экспоненту",
			worst_linear, 0, 1e-9,
			"v = v0*exp(-t/tau) — точное решение линейного уравнения; "
			.. "остаётся только ошибка РК4")

		suite:close("квадратичное торможение даёт 1/(1 + v0*k*t/m)",
			worst_quad, 0, 1e-9,
			"точное решение уравнения с квадратом скорости, полученное "
			.. "разделением переменных")

		-- Предел достигается только асимптотически, поэтому сверяется
		-- недобор, а не само значение.
		suite:close("недобор пути до предела v0*tau равен exp(-T/tau)",
			(P.speed * tau - linear_final.x.x) / (P.speed * tau),
			math.exp(-P.duration / tau), 1e-9,
			"за " .. ("%.1f"):format(P.duration / tau) .. " постоянных "
			.. "времени остаётся exp(-T/tau) = "
			.. ("%.4f"):format(math.exp(-P.duration / tau))
			.. " от полного пути")

		suite:close("путь при квадратичном торможении растёт как логарифм",
			quad_final.x.x, quad_s(P.duration), 1e-9,
			"сравнение с замкнутым решением (m/k)*ln(1 + v0*k*t/m)")

		suite:is_true("квадратичное торможение не останавливает тело",
			quad_s(10000) > quad_s(1000) * 1.05,
			"путь продолжает расти даже через часы: логарифм не имеет "
			.. "предела. Именно поэтому останов в игре требует отдельного "
			.. "механизма")

		suite:close("перелёт равен exp(-pi*zeta/sqrt(1-zeta^2))",
			overshoot_error, 0, 1e-5,
			"классический результат теории колебаний, проверяется сразу на "
			.. "четырёх значениях zeta. Допуск задан не на глаз: пик ищется "
			.. "по выборке с шагом dt, вблизи экстремума кривая квадратична, "
			.. "поэтому промах по значению порядка (w*dt)^2/2 = "
			.. ("%.1e"):format(0.5 * (w * P.dt) ^ 2))

		suite:is_true("при критическом демпфировании перелёта нет",
			overshoot_curve[5][2] < 1e-6,
			"при zeta = 1 решение вида (A + B*t)*exp(-w*t) не пересекает "
			.. "ноль ни разу")

		suite:is_true("критическое демпфирование быстрее передемпфированного",
			settle_times[1.0] < settle_times[1.5]
				and settle_times[1.5] < settle_times[2.5],
			"доказуемое свойство: при zeta > 1 медленный корень "
			.. "-w*(zeta - sqrt(zeta^2-1)) стремится к нулю, и возврат "
			.. "затягивается")

		suite:is_true("при малом zeta перелёт большой",
			overshoot_curve[1][2] > 0.5,
			"при zeta = 0.1 перелёт превышает 70 % — так ведёт себя почти "
			.. "незадемпфированная система")

		return suite
	end,
}
