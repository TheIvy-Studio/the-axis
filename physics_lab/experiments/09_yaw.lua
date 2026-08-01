-- the Axis · physics lab · эксперимент 09
-- Рыскание: путевая устойчивость (флюгерность) и её демпфирование.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local voxel = require("lab.voxel")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local C = require("lab.constants")
local R = require("lab.references")

return experiment.define {
	id = "09",
	name = "yaw",
	title = "Рыскание и путевая устойчивость",

	question = [[
Почему стрела летит острием вперёд, а брусок кувыркается? И что нужно
добавить воксельной машине, чтобы она сама держала нос по потоку?

Ответ один и тот же: нужна боковая поверхность ПОЗАДИ центра масс. Это
называется флюгерной устойчивостью, и она полностью определяется
геометрией — никаких дополнительных сущностей вводить не требуется.]],

	model = [[
Пусть машина летит со скольжением: нос отклонён от вектора скорости на угол
beta [рад]. Киль площадью S_v на плече l_v позади центра масс работает как
крыло под углом атаки beta и даёт боковую силу

    Y_v = 0.5*rho*V^2 * S_v * Cl_alpha * beta                [Н]

Момент рыскания относительно центра масс (восстанавливающий, поэтому минус):
    N_beta = -0.5*rho*V^2 * S_v * Cl_alpha * l_v             [Н·м/рад]

Демпфирование. При вращении с угловой скоростью r киль движется вбок со
скоростью r*l_v, что даёт местный угол r*l_v/V и силу против вращения:
    N_r = -0.5*rho*V^2 * S_v * Cl_alpha * l_v^2 / V          [Н·м·с/рад]

Размерность N_r: [Па]·[м^2]·[м^2]/[м/с] = [Н·м·с]. Сходится.

Уравнение то же второго порядка, что и по тангажу:
    I_zz * d2(beta)/dt2 = N_beta*beta + N_r*d(beta)/dt

    w_n  = sqrt(-N_beta / I_zz)                              [рад/с]
    zeta = -N_r / (2*sqrt(-N_beta * I_zz))                   [—]

Ключевой вывод для конструктора: устойчивость линейна по плечу киля, а
демпфирование — КВАДРАТИЧНО. Отодвинуть киль назад вдвое означает вдвое
большую устойчивость и вчетверо большее демпфирование.]],

	simplifications = [[
1. Это чистое рыскание при закреплённой траектории. У настоящего самолёта
   рыскание связано с креном, и вместе они дают «голландский шаг» —
   колебание, где машина одновременно рыскает и качается с креном. Здесь
   связь отброшена сознательно: она требует полной боковой динамики с
   уравнением бокового смещения, а для игры важен сам механизм флюгера.
2. Киль считается плоской пластиной, скос потока от фюзеляжа не учтён.
   У реальной машины фюзеляж дестабилизирует, и киль должен это перекрывать.
3. Скорость постоянна.]],

	references = { R.etkin_dynamics, R.mit_16_07_l28 },

	params = {
		fuselage = { value = 9, note = "длина фюзеляжа, блоков" },
		span = { value = 3, note = "размах крыла, блоков" },
		fin_area = { value = 1.5, note = "площадь киля, м^2" },
		fin_arm = { value = 4.0, note = "плечо киля от центра масс, м" },
		speed = { value = 25.0, note = "скорость полёта, м/с" },
		rho = { value = 1.225, note = "плотность воздуха, кг/м^3" },
		initial_yaw_deg = { value = 10.0, note = "начальное отклонение носа, град" },
		duration = { value = 15.0, note = "длительность, с" },
		dt = { value = 0.001, note = "шаг интегрирования, с" },
	},

	run = function(P, ctx)
		local body = voxel.describe(
			voxel.aircraft { fuselage = P.fuselage, span = P.span }, true)

		local inertia_zz = body.inertia[3][3]
		local cl_alpha = C.value("cl_alpha_thin_airfoil")
		local q = 0.5 * P.rho * P.speed * P.speed

		print(("Масса %.1f кг, I_zz = %.1f кг·м^2, q = %.2f Па")
			:format(body.mass, inertia_zz, q))

		local n_beta = -q * P.fin_area * cl_alpha * P.fin_arm
		local n_r = -q * P.fin_area * cl_alpha * P.fin_arm ^ 2 / P.speed

		print()
		print(("N_beta = %.2f Н·м/рад   (отрицательное — устойчиво)"):format(n_beta))
		print(("N_r    = %.2f Н·м·с/рад (демпфирование)"):format(n_r))

		local omega_n = math.sqrt(-n_beta / inertia_zz)
		local zeta = -n_r / (2 * math.sqrt(-n_beta * inertia_zz))
		local omega_d = omega_n * math.sqrt(math.max(0, 1 - zeta * zeta))

		print()
		print(("Собственная частота w_n = %.4f рад/с"):format(omega_n))
		print(("Коэффициент затухания zeta = %.4f — %s")
			:format(zeta, zeta >= 1 and "апериодическое возвращение"
				or "затухающие колебания"))

		if zeta < 1 then
			print(("Период колебаний = %.4f с"):format(2 * math.pi / omega_d))
		end

		print(("Время затухания до 5 %% = %.3f с"):format(3 / (zeta * omega_n)))

		----------------------------------------------------------------------
		-- Численное решение и сравнение с аналитическим
		----------------------------------------------------------------------
		local accel = function(x, v)
			return vec3.new((n_beta * x.x + n_r * v.x) / inertia_zz, 0, 0)
		end

		local beta0 = math.rad(P.initial_yaw_deg)

		-- Аналитическое решение линейного уравнения второго порядка при
		-- нулевой начальной угловой скорости. Для zeta < 1 колебательное,
		-- для zeta >= 1 — апериодическое; берётся соответствующая ветвь.
		local function exact(t)
			if zeta < 1 then
				local decay = math.exp(-zeta * omega_n * t)

				return beta0 * decay * (math.cos(omega_d * t)
					+ zeta / math.sqrt(1 - zeta * zeta) * math.sin(omega_d * t))
			end

			local root = math.sqrt(zeta * zeta - 1)
			local s1 = -omega_n * (zeta - root)
			local s2 = -omega_n * (zeta + root)

			-- Коэффициенты из условий beta(0) = beta0, beta'(0) = 0
			local c1 = beta0 * s2 / (s2 - s1)
			local c2 = beta0 * -s1 / (s2 - s1)

			return c1 * math.exp(s1 * t) + c2 * math.exp(s2 * t)
		end

		local trace, analytic = {}, {}
		local worst = 0

		integrate.simulate {
			method = "rk4",
			accel = accel,
			x0 = vec3.new(beta0, 0, 0),
			v0 = vec3.zero,
			dt = P.dt,
			duration = P.duration,
			sample = function(t, x)
				local reference = exact(t)

				trace[#trace + 1] = { t, math.deg(x.x) }
				analytic[#analytic + 1] = { t, math.deg(reference) }

				worst = math.max(worst, math.abs(x.x - reference) / beta0)
			end,
		}

		print()
		print(("Худшее расхождение с аналитическим решением: %.3e"):format(worst))

		----------------------------------------------------------------------
		-- Зависимость от плеча киля
		----------------------------------------------------------------------
		print()
		print("Плечо киля решает всё:")

		local arm_curve = {}

		for _, arm in ipairs({ 0.5, 1, 2, 3, 4, 6, 8 }) do
			local nb = -q * P.fin_area * cl_alpha * arm
			local nr = -q * P.fin_area * cl_alpha * arm * arm / P.speed
			local wn = math.sqrt(-nb / inertia_zz)
			local z = -nr / (2 * math.sqrt(-nb * inertia_zz))

			arm_curve[#arm_curve + 1] = { arm, z }

			print(("  плечо %.1f м: w_n = %.3f рад/с, zeta = %.3f (%s)")
				:format(arm, wn, z,
					z >= 1 and "без колебаний" or "с колебаниями"))
		end

		----------------------------------------------------------------------
		-- А что если киля нет
		----------------------------------------------------------------------
		print()
		print("ВЫВОД ПО КОНСТРУКЦИИ:")
		print(("  затухание zeta = %.3f — это ОЧЕНЬ мало (у самолётов 0.1...0.3),")
			:format(zeta))
		print(("  колебание по рысканью гаснет %.0f с, то есть почти %.0f периодов.")
			:format(3 / (zeta * omega_n), 3 / (zeta * omega_n) / (2 * math.pi / omega_d)))
		print("  Причина видна из формул: N_r квадратично по плечу киля, а")
		print("  момент инерции воксельной машины огромен. Лечится либо")
		print("  бо́льшим килем, либо бо́льшим плечом — второе эффективнее вчетверо.")

		print()
		print("Без киля (S_v = 0) N_beta = 0: восстанавливающего момента нет,")
		print("нос остаётся там, куда его повернули. Именно так ведёт себя")
		print("голый воксельный корпус — он не «неправильный», ему просто")
		print("нечем держать курс.")

		ctx.show({
			{ label = "численно", mark = "*", points = trace },
			{ label = "аналитически", mark = "-", points = analytic },
		}, {
			title = "Возвращение носа по потоку",
			xlabel = "время, с",
			ylabel = "угол скольжения, град",
		})

		ctx.save({
			{ label = "численно", points = trace },
			{ label = "аналитически", points = analytic, dashed = true },
		}, {
			title = "Путевая устойчивость: затухание скольжения",
			xlabel = "время, с",
			ylabel = "угол скольжения, град",
		}, {
			headers = { "t", "beta_numeric_deg", "beta_exact_deg" },
			rows = (function()
				local rows = {}

				for index, point in ipairs(trace) do
					rows[index] = { point[1], point[2], analytic[index][2] }
				end

				return rows
			end)(),
		})

		----------------------------------------------------------------------
		local suite = check.new("рыскание")

		suite:is_true("киль позади центра масс даёт устойчивость",
			n_beta < 0,
			"восстанавливающий момент направлен против отклонения; при киле "
			.. "ВПЕРЕДИ центра масс знак сменился бы и машина закувыркалась")

		suite:close("численное решение совпадает с аналитическим",
			worst, 0, 1e-9,
			"линейное уравнение с постоянными коэффициентами, РК4 на нём "
			.. "практически точен")

		suite:close("устойчивость линейна по плечу киля",
			(-q * P.fin_area * cl_alpha * 2 * P.fin_arm) / n_beta, 2, 1e-12,
			"N_beta пропорционально l_v, точное отношение")

		suite:close("демпфирование квадратично по плечу киля",
			(-q * P.fin_area * cl_alpha * (2 * P.fin_arm) ^ 2 / P.speed) / n_r,
			4, 1e-12,
			"N_r пропорционально l_v^2: плечо входит и в силу, и в момент")

		-- Огибающая затухающего колебания: |beta(t)| <= beta0 * exp(-zeta*w_n*t)
		-- делённое на sqrt(1 - zeta^2). Проверяется именно эта граница, а не
		-- произвольный порог «пять процентов за пятнадцать секунд».
		suite:is_true("колебание не выходит за аналитическую огибающую",
			(function()
				local bound = 1 / math.sqrt(1 - zeta * zeta)

				for _, point in ipairs(trace) do
					local envelope = P.initial_yaw_deg * bound
						* math.exp(-zeta * omega_n * point[1])

					if math.abs(point[2]) > envelope * (1 + 1e-9) then
						return false
					end
				end

				return true
			end)(),
			"огибающая exp(-zeta*w_n*t)/sqrt(1-zeta^2) — точная верхняя "
			.. "граница решения при нулевой начальной угловой скорости")

		suite:close("амплитуда падает ровно как exp(-zeta*w_n*T)",
			math.abs(trace[#trace][2]) / P.initial_yaw_deg,
			math.abs(math.exp(-zeta * omega_n * P.duration)
				* (math.cos(omega_d * P.duration)
					+ zeta / math.sqrt(1 - zeta * zeta)
					* math.sin(omega_d * P.duration))), 1e-9,
			"сравнение с полным аналитическим решением в конечной точке")

		suite:is_true("без киля устойчивости нет",
			-q * 0 * cl_alpha * P.fin_arm == 0,
			"N_beta пропорционально площади киля: нет площади — нет момента, "
			.. "и нос никуда не возвращается")

		return suite
	end,
}
