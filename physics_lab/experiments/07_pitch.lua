-- the Axis · physics lab · эксперимент 07
-- Тангаж: продольная устойчивость и короткопериодическое колебание.

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
	id = "07",
	name = "pitch",
	title = "Тангаж и продольная устойчивость",

	question = [[
Почему самолёт сам возвращает нос в исходное положение, а брусок — нет? И
почему в моде тяжёлый хвост задирался вверх?

Ответ на второй вопрос выясняется здесь окончательно: собственный вес не
создаёт момента вокруг центра масс, потому что приложен ровно в нём (плечо
равно нулю). Наклон создаёт только несимметрия ВНЕШНИХ сил — подъёмной силы
крыла и оперения.]],

	model = [[
Момент вокруг центра масс:
    tau = r x F                                              [Н·м]
Собственный вес приложен в центре масс, r = 0, значит вклад веса в момент
строго нулевой. Это не приближение, а следствие определения центра масс.

Продольная устойчивость. Пусть нос отклонился на угол atk от равновесия.
Крыло на расстоянии x_w от центра масс и оперение на расстоянии l_t дают
приращения подъёмной силы:
    dL_w = q * S_w * Cl_alpha * atk,   dL_t = q * S_t * Cl_alpha * atk
Момент (нос вверх положителен, оперение позади центра масс):
    M_atk = q * (S_w * Cl_alpha * x_w  -  S_t * Cl_alpha * l_t)   [Н·м/рад]

Тело устойчиво, когда M_atk < 0: отклонение носа вверх создаёт момент вниз.
Это и есть требование «центр масс впереди нейтральной точки»
[etkin_dynamics]. Запас устойчивости:
    SM = (x_np - x_cg) / c                                   [—]

Демпфирование. При вращении с угловой скоростью w оперение движется вниз со
скоростью w*l_t, что даёт местный угол атаки w*l_t/V и силу против вращения:
    M_w = -q * S_t * Cl_alpha * l_t^2 / V                     [Н·м·с/рад]
Размерность: [Па]·[м^2]·[м^2]/[м/с] = [Н·м·с]. Сходится.

Итого линейное уравнение второго порядка:
    I_yy * d2(atk)/dt2 = M_atk*atk + M_w*d(atk)/dt

Стандартная форма даёт собственную частоту и коэффициент затухания:
    w_n = sqrt(-M_atk / I_yy)                                [рад/с]
    zeta = -M_w / (2*sqrt(-M_atk * I_yy))                    [—]
    период колебаний T_d = 2*pi / (w_n*sqrt(1 - zeta^2))     [с]

Эти три числа считаются заранее и потом СРАВНИВАЮТСЯ с измеренными по
результату численного решения. Совпадение периода и логарифмического
декремента — и есть проверка.]],

	simplifications = [[
1. Это короткопериодическое колебание при постоянной скорости. Настоящая
   продольная динамика имеет ещё второй, длиннопериодический режим (фугоид),
   где обмениваются высота и скорость. Он здесь не моделируется: у него
   период в десятки секунд, и в игровом масштабе он не читается.
2. Линеаризация вокруг малого угла. За срывом всё ломается — см. эксперимент 06.
3. Оперение считается плоской пластиной без скоса потока от крыла.]],

	references = { R.etkin_dynamics, R.mit_16_07_l28, R.anderson_aero },

	params = {
		fuselage = { value = 9, note = "длина фюзеляжа, блоков" },
		span = { value = 3, note = "размах крыла, блоков" },
		speed = { value = 25.0, note = "скорость полёта, м/с" },
		rho = { value = 1.225, note = "плотность воздуха, кг/м^3" },
		tail_area = { value = 2.0, note = "площадь оперения, м^2" },
		tail_arm = { value = 4.0, note = "плечо оперения от центра масс, м" },
		wing_offset = { value = -0.2, note = "смещение крыла от центра масс, м" },
		initial_pitch_deg = { value = 8.0, note = "начальное отклонение носа, град" },
		duration = { value = 12.0, note = "длительность, с" },
		dt = { value = 0.001, note = "шаг интегрирования, с" },
	},

	run = function(P, ctx)
		local body = voxel.describe(
			voxel.aircraft { fuselage = P.fuselage, span = P.span }, true)

		local inertia_yy = body.inertia[2][2]
		local wing_area = voxel.wing_area(body)
		local cl_alpha = C.value("cl_alpha_thin_airfoil")

		local q = 0.5 * P.rho * P.speed * P.speed

		print(("Масса %.1f кг, I_yy = %.1f кг·м^2"):format(body.mass, inertia_yy))
		print(("Скоростной напор q = %.2f Па, площадь крыла %.2f м^2")
			:format(q, wing_area))

		----------------------------------------------------------------------
		-- Проверка: вес не создаёт момента
		----------------------------------------------------------------------
		local weight_force = vec3.new(0, -body.mass * C.value("gravity"), 0)
		local weight_torque = vec3.cross(vec3.zero, weight_force)

		print()
		print(("Момент собственного веса вокруг центра масс: %s Н·м")
			:format(tostring(weight_torque)))

		----------------------------------------------------------------------
		-- Производные устойчивости
		----------------------------------------------------------------------
		local m_alpha = q * cl_alpha
			* (wing_area * P.wing_offset - P.tail_area * P.tail_arm)

		local m_omega = -q * P.tail_area * cl_alpha
			* P.tail_arm * P.tail_arm / P.speed

		print()
		print(("M_atk = %.2f Н·м/рад   (отрицательное — устойчиво)"):format(m_alpha))
		print(("M_w   = %.2f Н·м·с/рад (демпфирование)"):format(m_omega))

		if m_alpha >= 0 then
			print("ВНИМАНИЕ: конфигурация неустойчива, колебаний не будет")
		end

		local omega_n = math.sqrt(-m_alpha / inertia_yy)
		local zeta = -m_omega / (2 * math.sqrt(-m_alpha * inertia_yy))
		local omega_d = omega_n * math.sqrt(math.max(0, 1 - zeta * zeta))
		local period = 2 * math.pi / omega_d

		print()
		print(("Собственная частота w_n = %.4f рад/с (%.4f Гц)")
			:format(omega_n, omega_n / (2 * math.pi)))
		print(("Коэффициент затухания zeta = %.4f"):format(zeta))
		print(("Период затухающих колебаний = %.4f с"):format(period))
		print(("Время затухания до 5 %% = %.3f с"):format(3 / (zeta * omega_n)))

		----------------------------------------------------------------------
		-- Численное решение
		----------------------------------------------------------------------
		local accel = function(x, v)
			-- x.x — угол тангажа, v.x — угловая скорость
			return vec3.new((m_alpha * x.x + m_omega * v.x) / inertia_yy, 0, 0)
		end

		local trace = {}
		local peaks = {}
		local previous_angle, previous_rate

		integrate.simulate {
			method = "rk4",
			accel = accel,
			x0 = vec3.new(math.rad(P.initial_pitch_deg), 0, 0),
			v0 = vec3.zero,
			dt = P.dt,
			duration = P.duration,
			sample = function(t, x, v)
				trace[#trace + 1] = { t, math.deg(x.x) }

				-- Экстремум там, где угловая скорость меняет знак
				if previous_rate and previous_rate > 0 and v.x <= 0 then
					peaks[#peaks + 1] = { t, previous_angle }
				end

				previous_angle, previous_rate = x.x, v.x
			end,
		}

		print()
		print(("Найдено максимумов: %d"):format(#peaks))

		local measured_period, measured_zeta

		if #peaks >= 2 then
			measured_period = peaks[2][1] - peaks[1][1]

			-- Логарифмический декремент: delta = ln(A1/A2),
			-- zeta = delta / sqrt(4*pi^2 + delta^2)
			local decrement = math.log(peaks[1][2] / peaks[2][2])
			measured_zeta = decrement
				/ math.sqrt(4 * math.pi * math.pi + decrement * decrement)

			print(("Измеренный период     = %.4f с (расчётный %.4f)")
				:format(measured_period, period))
			print(("Логарифмический декремент = %.4f"):format(decrement))
			print(("Измеренное затухание zeta = %.4f (расчётное %.4f)")
				:format(measured_zeta, zeta))
		end

		----------------------------------------------------------------------
		-- Что даёт смещение центра масс назад
		----------------------------------------------------------------------
		print()
		print("Смещение центра масс назад съедает устойчивость:")

		for _, shift in ipairs({ -0.5, 0.0, 0.5, 1.0, 1.5, 2.0 }) do
			local ma = q * cl_alpha
				* (wing_area * (P.wing_offset + shift)
					- P.tail_area * (P.tail_arm - shift))

			print(("  центр масс сдвинут на %+.1f м: M_atk = %+9.2f Н·м/рад — %s")
				:format(shift, ma, ma < 0 and "устойчиво" or "НЕУСТОЙЧИВО"))
		end

		ctx.show({
			{ label = "тангаж", mark = "*", points = trace },
		}, {
			title = "Затухающее колебание по тангажу",
			xlabel = "время, с",
			ylabel = "угол, град",
		})

		ctx.save({
			{ label = "тангаж, град", points = trace },
		}, {
			title = "Короткопериодическое колебание по тангажу",
			xlabel = "время, с",
			ylabel = "угол, град",
		}, {
			headers = { "t", "pitch_deg" },
			rows = trace,
		})

		----------------------------------------------------------------------
		local suite = check.new("тангаж")

		suite:is_true("вес не создаёт момента вокруг центра масс",
			vec3.length(weight_torque) == 0,
			"плечо равно нулю по определению центра масс; именно эта ошибка "
			.. "в моде заставляла тяжёлый хвост подниматься")

		suite:is_true("конфигурация продольно устойчива",
			m_alpha < 0,
			"момент от оперения перевешивает момент от крыла, значит "
			.. "отклонение носа гасится")

		if measured_period then
			suite:close("измеренный период совпадает с расчётным",
				measured_period, period, 0.01,
				"экстремумы находятся по смене знака угловой скорости с "
				.. "шагом выборки dt = " .. tostring(P.dt) .. " с, отсюда "
				.. "погрешность до dt на каждый максимум")

			suite:close("измеренное затухание совпадает с расчётным",
				measured_zeta, zeta, 0.02,
				"логарифмический декремент считается по двум соседним "
				.. "максимумам, найденным с точностью dt; при малом zeta "
				.. "отношение амплитуд близко к единице и чувствительно "
				.. "к этой погрешности")
		end

		suite:is_true("демпфирование отрицательно",
			m_omega < 0,
			"оперение при вращении создаёт силу ПРОТИВ вращения; "
			.. "положительное значение означало бы раскачку")

		suite:close("частота растёт как корень из жёсткости",
			math.sqrt(-2 * m_alpha / inertia_yy) / omega_n,
			math.sqrt(2), 1e-12,
			"w_n = sqrt(-M_atk/I), удвоение M_atk даёт множитель sqrt(2) — "
			.. "точное отношение")

		return suite
	end,
}
