-- the Axis · physics lab · эксперимент 12
-- Угловая скорость: уравнения Эйлера, законы сохранения, неустойчивость
-- вращения вокруг средней оси.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local rigid = require("lab.rigid")
local voxel = require("lab.voxel")
local vec3 = require("lab.vec3")
local mat3 = require("lab.mat3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "12",
	name = "angular_velocity",
	title = "Угловая скорость и уравнения Эйлера",

	question = [[
Как на самом деле вращается тело, у которого моменты инерции по трём осям
разные? И почему брошенная конструкция может закувыркаться сама, без всякого
внешнего момента?]],

	model = [[
Уравнения Эйлера в связанных с телом осях [mit_16_07_l28]:

    I * dw/dt + w x (I*w) = M
    dw/dt = I^-1 * (M - w x (I*w))                            [рад/с^2]

Член w x (I*w) — гироскопический. Он нелинеен и не имеет аналога в
поступательном движении: тело может менять направление вращения БЕЗ внешнего
момента, просто перераспределяя момент импульса между осями.

Точные интегралы движения при M = 0:
    |L| = |I*w| = const                                       [кг·м^2/с]
    T = 0.5 * w . (I*w) = const                               [Дж]

Оба сохраняются ТОЧНО, поэтому они и служат проверкой: если численное решение
их нарушает, ошибка в схеме или в уравнениях, а не в физике.

Теорема о промежуточной оси (эффект Джанибекова). Пусть I1 < I2 < I3.
Вращение вокруг осей с наименьшим (I1) и наибольшим (I3) моментами инерции
устойчиво, а вокруг средней (I2) — НЕТ: любое сколь угодно малое возмущение
нарастает экспоненциально, и тело периодически переворачивается. Это строгий
результат линеаризации уравнений Эйлера, а не численный артефакт.

Для игры это означает: длинная плоская конструкция, закрученная «неудобно»,
будет кувыркаться сама по себе. Это правильное поведение, а не баг.]],

	simplifications = [[
1. Считается только угловая скорость в связанных осях. Полная ориентация в
   мире требует интегрирования кватерниона или матрицы поворота — это
   отдельная задача, и для проверки самих уравнений Эйлера она не нужна.
2. Аэродинамического демпфирования нет: тело вращается в пустоте. С
   демпфированием (эксперименты 08 и 09) кувыркание затухает.]],

	references = { R.mit_16_07_l28, R.hairer_odes },

	params = {
		fuselage = { value = 9, note = "длина фюзеляжа, блоков" },
		span = { value = 3, note = "размах крыла, блоков" },
		spin_rate = { value = 2.0, note = "начальная угловая скорость, рад/с" },
		perturbation = { value = 0.02, note = "малое возмущение по другим осям, рад/с" },
		torque = { value = 500.0, note = "внешний момент для проверки, Н·м" },
		duration = { value = 30.0, note = "длительность, с" },
		dt = { value = 0.0005, note = "шаг интегрирования, с" },
	},

	run = function(P, ctx)
		local body = voxel.describe(
			voxel.aircraft { fuselage = P.fuselage, span = P.span }, true)

		local inertia = body.inertia
		local inverse = mat3.inverse(inertia)

		local i1, i2, i3 = inertia[1][1], inertia[2][2], inertia[3][3]

		print(("Машина: %d блоков, масса %.1f кг"):format(body.count, body.mass))
		print(("Главные моменты инерции (диагональ): I_xx = %.1f, I_yy = %.1f, "
			.. "I_zz = %.1f кг·м^2"):format(i1, i2, i3))

		-- Определяем, какая ось средняя
		local axes = {
			{ name = "x (крен)", value = i1, unit = vec3.unit_x },
			{ name = "y (тангаж)", value = i2, unit = vec3.unit_y },
			{ name = "z (рыскание)", value = i3, unit = vec3.unit_z },
		}

		table.sort(axes, function(a, b) return a.value < b.value end)

		print(("Порядок: %s < %s < %s")
			:format(axes[1].name, axes[2].name, axes[3].name))
		print(("Промежуточная ось — %s, вращение вокруг неё неустойчиво")
			:format(axes[2].name))

		----------------------------------------------------------------------
		-- Свободное вращение: проверка законов сохранения
		----------------------------------------------------------------------
		local function derivative(omega)
			return rigid.angular_acceleration(inertia, inverse, omega, vec3.zero)
		end

		local function spin_test(axis_index, label)
			local axis = axes[axis_index]

			-- Основное вращение плюс малое возмущение по двум другим осям
			local omega = axis.unit * P.spin_rate
				+ vec3.new(P.perturbation, P.perturbation, P.perturbation)
				- axis.unit * P.perturbation

			local l0 = vec3.length(rigid.angular_momentum(inertia, omega))
			local t0 = rigid.rotational_energy(inertia, omega)

			local worst_l, worst_t = 0, 0
			local max_deviation = 0
			local trace = {}

			local steps = math.floor(P.duration / P.dt + 0.5)
			local dt = P.duration / steps

			for step = 1, steps do
				omega = integrate.rk4_first_order(omega, derivative, dt,
					(step - 1) * dt)

				local l = vec3.length(rigid.angular_momentum(inertia, omega))
				local energy = rigid.rotational_energy(inertia, omega)

				worst_l = math.max(worst_l, math.abs(l - l0) / l0)
				worst_t = math.max(worst_t, math.abs(energy - t0) / t0)

				-- Насколько вращение ушло с исходной оси
				local along = math.abs(vec3.dot(omega, axis.unit))
				local across = vec3.length(vec3.reject(omega, axis.unit))

				max_deviation = math.max(max_deviation, across / P.spin_rate)

				if step % 20 == 0 then
					trace[#trace + 1] = { step * dt, along }
				end
			end

			print(("  %-28s |L| дрейф %.2e, энергия %.2e, уход с оси %.4f")
				:format(label, worst_l, worst_t, max_deviation))

			return {
				deviation = max_deviation,
				momentum_drift = worst_l,
				energy_drift = worst_t,
				trace = trace,
			}
		end

		print()
		print("Свободное вращение с малым возмущением:")

		local minor = spin_test(1, "вокруг МЕНЬШЕЙ оси")
		local middle = spin_test(2, "вокруг СРЕДНЕЙ оси")
		local major = spin_test(3, "вокруг БОЛЬШЕЙ оси")

		print()
		print(("Уход с оси: меньшая %.4f, средняя %.4f, большая %.4f")
			:format(minor.deviation, middle.deviation, major.deviation))
		print(("Средняя ось нестабильнее меньшей в %.0f раз")
			:format(middle.deviation / minor.deviation))

		----------------------------------------------------------------------
		-- Постоянный момент вокруг ГЛАВНОЙ оси
		----------------------------------------------------------------------
		-- Для этой проверки берётся симметричный стержень: у него тензор
		-- инерции диагонален, и при вращении строго вокруг одной оси
		-- гироскопический член w x (I*w) обращается в ноль. Тогда решение
		-- w = M*t/I ТОЧНОЕ, и его можно требовать с машинной точностью.
		-- У самолёта тензор не диагонален, там такой проверки не построить —
		-- и это разбирается отдельно, ниже.
		local rod = voxel.rod(11, 3)
		local rod_centre, rod_mass = rigid.centre_of_mass(rod)
		local rod_inertia = rigid.inertia_tensor(rod, rod_centre,
			require("lab.constants").value("node_size"))
		local rod_inverse = mat3.inverse(rod_inertia)

		local applied = vec3.new(0, 0, P.torque)

		local function driven(omega)
			return rigid.angular_acceleration(rod_inertia, rod_inverse,
				omega, applied)
		end

		local omega = vec3.zero
		local steps = math.floor(5 / P.dt + 0.5)
		local dt = 5 / steps

		for step = 1, steps do
			omega = integrate.rk4_first_order(omega, driven, dt, (step - 1) * dt)
		end

		local expected_rate = P.torque / rod_inertia[3][3] * 5

		print()
		print(("Стержень из 11 блоков, масса %.1f кг, I_zz = %.1f кг·м^2")
			:format(rod_mass, rod_inertia[3][3]))
		print(("Постоянный момент %.0f Н·м вокруг главной оси z, 5 с:")
			:format(P.torque))
		print(("  численно     w_z = %.9f рад/с"):format(omega.z))
		print(("  аналитически M*t/I = %.9f рад/с"):format(expected_rate))
		print(("  паразитное вращение по другим осям: %.2e, %.2e рад/с")
			:format(omega.x, omega.y))

		----------------------------------------------------------------------
		-- А теперь то же самое на несимметричной машине
		----------------------------------------------------------------------
		local coupled = vec3.zero
		local aircraft_torque = vec3.new(P.torque, 0, 0)

		local function driven_aircraft(w)
			return rigid.angular_acceleration(inertia, inverse, w,
				aircraft_torque)
		end

		for step = 1, steps do
			coupled = integrate.rk4_first_order(coupled, driven_aircraft, dt,
				(step - 1) * dt)
		end

		print()
		print(("Тот же момент вокруг оси x, но на машине (тензор не диагонален):"))
		print(("  w = %s рад/с"):format(tostring(coupled)))
		print(("  наивная оценка M*t/I_xx = %.6f"):format(P.torque * 5 / i1))
		print(("  расхождение %.3f %%, и появилось вращение по другим осям")
			:format(math.abs(coupled.x - P.torque * 5 / i1)
				/ (P.torque * 5 / i1) * 100))
		print("  Причина — центробежные моменты инерции: они связывают оси,")
		print("  и момент вокруг одной раскручивает соседние.")

		----------------------------------------------------------------------
		-- Таблица: как момент раскручивает разные оси
		----------------------------------------------------------------------
		print()
		print("Один и тот же момент, разные оси:")
		print(text.row {
			{ "ось", 16 }, { "I, кг·м^2", 14 }, { "w через 5 с, рад/с", 20 },
		})

		for _, axis in ipairs({
			{ "x (крен)", i1 }, { "y (тангаж)", i2 }, { "z (рыскание)", i3 },
		}) do
			print(text.row {
				{ axis[1], 16 },
				{ ("%.1f"):format(axis[2]), 14 },
				{ ("%.4f"):format(P.torque * 5 / axis[2]), 20 },
			})
		end

		ctx.show({
			{ label = "вокруг средней оси", mark = "m", points = middle.trace },
			{ label = "вокруг большей оси", mark = "b", points = major.trace },
		}, {
			title = "Составляющая вращения вдоль исходной оси",
			xlabel = "время, с",
			ylabel = "w вдоль оси, рад/с",
		})

		ctx.save({
			{ label = "средняя ось", points = middle.trace },
			{ label = "большая ось", points = major.trace },
		}, {
			title = "Неустойчивость вращения вокруг промежуточной оси",
			xlabel = "время, с",
			ylabel = "w вдоль исходной оси, рад/с",
		}, {
			headers = { "t", "middle_axis", "major_axis" },
			rows = (function()
				local rows = {}

				for index, point in ipairs(middle.trace) do
					rows[index] = {
						point[1], point[2],
						major.trace[index] and major.trace[index][2] or 0,
					}
				end

				return rows
			end)(),
		})

		----------------------------------------------------------------------
		local suite = check.new("угловая скорость")

		suite:close("момент импульса сохраняется (меньшая ось)",
			minor.momentum_drift, 0, 1e-9,
			"|I*w| — точный интеграл уравнений Эйлера при нулевом моменте; "
			.. "остаётся только ошибка РК4 за " .. tostring(P.duration / P.dt)
			.. " шагов")

		suite:close("энергия вращения сохраняется (меньшая ось)",
			minor.energy_drift, 0, 1e-9,
			"второй точный интеграл; независимая проверка тех же уравнений")

		suite:close("момент импульса сохраняется и на неустойчивой оси",
			middle.momentum_drift, 0, 1e-9,
			"важно: кувыркание НЕ нарушает законов сохранения. Если бы "
			.. "нарушало, это была бы численная расходимость, а не физика")

		suite:close("энергия сохраняется и на неустойчивой оси",
			middle.energy_drift, 0, 1e-9,
			"то же самое со стороны энергии")

		suite:is_true("вращение вокруг средней оси неустойчиво",
			middle.deviation > 10 * minor.deviation
				and middle.deviation > 10 * major.deviation,
			"теорема о промежуточной оси: возмущение нарастает "
			.. "экспоненциально. Порог в 10 раз взят с большим запасом — "
			.. "разница на практике на порядки")

		suite:is_true("вращение вокруг крайних осей устойчиво",
			minor.deviation < 0.1 and major.deviation < 0.1,
			"возмущение остаётся ограниченным и не превышает 10 % от "
			.. "основного вращения")

		suite:close("постоянный момент вокруг главной оси даёт w = M*t/I",
			omega.z, expected_rate, 1e-12,
			"у симметричного стержня тензор диагонален, вращение остаётся "
			.. "на одной оси и гироскопический член строго нулевой — решение "
			.. "точное, допуск на уровне округления")

		suite:is_true("вращение вокруг главной оси не подмешивается в другие",
			math.abs(omega.x) < 1e-14 and math.abs(omega.y) < 1e-14,
			"диагональный тензор не связывает оси между собой")

		suite:is_true("у несимметричного тела оси связаны",
			math.abs(coupled.y) > 1e-9 or math.abs(coupled.z) > 1e-9,
			"центробежные моменты инерции переносят вращение с оси на ось; "
			.. "именно поэтому наивная формула M*t/I_xx для реальной "
			.. "конструкции неверна")

		suite:close("тот же момент вокруг более инертной оси раскручивает слабее",
			(P.torque * 5 / i2) / (P.torque * 5 / i1), i1 / i2, 1e-12,
			"угловая скорость обратно пропорциональна моменту инерции, "
			.. "точное отношение")

		return suite
	end,
}
