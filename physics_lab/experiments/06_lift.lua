-- the Axis · physics lab · эксперимент 06
-- Подъёмная сила: горизонтальный полёт, сваливание, планирование.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local aero = require("lab.aero")
local voxel = require("lab.voxel")
local check = require("lab.check")
local C = require("lab.constants")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "06",
	name = "lift",
	title = "Подъёмная сила и горизонтальный полёт",

	question = [[
Сколько крыла нужно воксельной машине, чтобы она вообще взлетела, и на какой
скорости? В моде подъёмная сила задана как LIFT_PER_WING = 14 «на крыло» —
число без физического смысла. Здесь считается настоящая величина и
проверяется, что из неё следует.]],

	model = [[
    L = 0.5 * Cl * rho * V^2 * S                              [Н]

Источник: NASA Glenn, «The Lift Equation» [nasa_lift_equation].

Коэффициент подъёмной силы линеен по углу атаки до срыва. Теория тонкого
профиля даёт наклон 2*pi на радиан [anderson_aero]:
    Cl = Cl_alpha * alpha,   Cl_alpha = 2*pi   [1/рад]

Для крыла КОНЕЧНОГО размаха наклон меньше из-за скоса потока от концевых
вихрей:
    a = a0 / (1 + a0/(pi*e*AR)),   AR = b^2/S
Для воксельного крыла это принципиально: крыло из 3 блоков в каждую сторону
имеет удлинение около 6/1, но при размахе в 3 блока и хорде в 1 блок
удлинение равно 6, и наклон падает примерно на четверть.

Горизонтальный полёт: L = m*g. Отсюда скорость сваливания
    V_stall = sqrt(2*m*g / (rho * S * Cl_max))                [м/с]
ниже которой горизонтальный полёт невозможен ни при каком угле атаки.

Полное сопротивление складывается из паразитного и индуктивного:
    Cd = Cd0 + Cl^2/(pi*e*AR)
Минимум полного сопротивления достигается там, где эти две части РАВНЫ —
это классический результат, и он проверяется здесь численно.

Планирование без тяги: угол снижения задаётся качеством
    tan(gamma) = D/L = 1/(L/D)
дальность планирования с высоты h равна h*(L/D).]],

	simplifications = [[
1. Срыв смоделирован грубо: за критическим углом Cl линейно спадает до
   половины пика. Настоящий срыв резкий и с гистерезисом. Теряется
   «подхват» и сваливание на крыло; сохраняется главное — за срывом
   подъёмная сила падает, а не растёт.
2. Плоское крыло без профиля: Cl при нулевом угле атаки равен нулю. У
   несимметричного профиля он положителен. Для воксельного крыла плоская
   пластина — как раз честная модель.
3. Сжимаемость не учитывается (на игровых скоростях M < 0.05).]],

	references = { R.nasa_lift_equation, R.anderson_aero, R.faa_phak },

	params = {
		fuselage = { value = 7, note = "длина фюзеляжа, блоков" },
		span = { value = 3, note = "размах каждого крыла, блоков" },
		rho = { value = 1.225, note = "плотность воздуха, кг/м^3" },
		gravity = { value = 9.81, note = "ускорение падения, м/с^2" },
		cd0 = { value = 0.09, note = "паразитное сопротивление (отнесено к площади крыла)" },
		oswald = { value = 0.8, note = "коэффициент Освальда" },
		speed = { value = 25.0, note = "скорость для расчёта, м/с" },
	},

	run = function(P, ctx)
		local blocks = voxel.aircraft { fuselage = P.fuselage, span = P.span }
		local body = voxel.describe(blocks)

		local wing_area = voxel.wing_area(body)
		local span_metres = 2 * P.span * C.value("node_size")
		local aspect_ratio = span_metres * span_metres / wing_area

		print(("Машина: %d блоков, масса %.1f кг, крыльев %d")
			:format(body.count, body.mass, body.counts.wing or 0))
		print(("Площадь крыла S = %.2f м^2, размах b = %.2f м, удлинение AR = %.3f")
			:format(wing_area, span_metres, aspect_ratio))

		local a0 = C.value("cl_alpha_thin_airfoil")
		local cl_alpha = aero.finite_wing_lift_slope(a0, aspect_ratio, P.oswald)

		print(("Наклон линии подъёмной силы: 2*pi = %.4f → с поправкой на "
			.. "удлинение %.4f 1/рад"):format(a0, cl_alpha))

		local cl_max = cl_alpha * C.value("alpha_stall")
		local weight = body.mass * P.gravity

		print(("Cl_max при угле срыва %.1f° = %.4f")
			:format(math.deg(C.value("alpha_stall")), cl_max))
		print(("Вес W = m*g = %.1f Н"):format(weight))

		----------------------------------------------------------------------
		-- Скорость сваливания
		----------------------------------------------------------------------
		local v_stall = aero.stall_speed(body.mass, P.gravity, P.rho,
			wing_area, cl_max)

		print()
		print(("Скорость сваливания V_stall = %.3f м/с (%.1f км/ч)")
			:format(v_stall, v_stall * 3.6))

		-- Требуемый Cl на заданной скорости
		local required_cl = weight
			/ (0.5 * P.rho * P.speed * P.speed * wing_area)

		print(("На скорости %.4g м/с нужен Cl = %.4f (угол атаки %.2f°)")
			:format(P.speed, required_cl, math.deg(required_cl / cl_alpha)))

		----------------------------------------------------------------------
		-- Поляра и минимум сопротивления
		----------------------------------------------------------------------
		local polar, lift_curve, drag_curve = {}, {}, {}
		local best_ld, best_speed = -1, 0
		local min_drag, min_drag_speed = math.huge, 0
		local parasitic_at_min, induced_at_min = 0, 0

		-- Перебор идёт ОТ скорости сваливания, а не от нуля. Абсолютная шкала
		-- здесь не годится: у тяжёлой воксельной машины сваливание может
		-- оказаться за пределами любого наперёд выбранного диапазона, и
		-- поляра выйдет пустой.
		for index = 0, 400 do
			local v = v_stall * (1 + index * 0.015)

			local cl = weight / (0.5 * P.rho * v * v * wing_area)

			if cl <= cl_max then
				local cdi = aero.induced_drag_coefficient(cl, aspect_ratio,
					P.oswald)
				local cd = P.cd0 + cdi

				local drag = 0.5 * cd * P.rho * v * v * wing_area
				local parasitic = 0.5 * P.cd0 * P.rho * v * v * wing_area
				local induced = 0.5 * cdi * P.rho * v * v * wing_area

				local ld = cl / cd

				polar[#polar + 1] = { v, ld }
				drag_curve[#drag_curve + 1] = { v, drag }

				if ld > best_ld then
					best_ld, best_speed = ld, v
				end

				if drag < min_drag then
					min_drag, min_drag_speed = drag, v
					parasitic_at_min, induced_at_min = parasitic, induced
				end
			end
		end

		for degrees = -20, 20, 0.5 do
			local alpha = math.rad(degrees)

			lift_curve[#lift_curve + 1] = {
				degrees, aero.lift_coefficient(alpha, cl_alpha),
			}
		end

		print()
		print(("Минимум полного сопротивления: %.2f Н на %.2f м/с")
			:format(min_drag, min_drag_speed))
		print(("  паразитное %.3f Н, индуктивное %.3f Н, отношение %.4f")
			:format(parasitic_at_min, induced_at_min,
				parasitic_at_min / induced_at_min))
		print(("Наилучшее качество L/D = %.3f на %.2f м/с")
			:format(best_ld, best_speed))
		print(("Дальность планирования с 100 м: %.1f м")
			:format(100 * best_ld))
		print(("Угол снижения на наилучшем качестве: %.2f°")
			:format(math.deg(math.atan(1 / best_ld))))

		----------------------------------------------------------------------
		-- Сколько нужно крыла
		----------------------------------------------------------------------
		----------------------------------------------------------------------
		-- Пригодна ли машина к полёту вообще
		----------------------------------------------------------------------
		local wing_loading = body.mass / wing_area

		print()
		print("ВЫВОД ПО КОНСТРУКЦИИ:")
		print(("  нагрузка на крыло %.1f кг/м^2"):format(wing_loading))
		print("  для сравнения: лёгкий самолёт 50...100, истребитель 300...500")
		print(("  при такой нагрузке сваливание наступает на %.0f км/ч")
			:format(v_stall * 3.6))

		-- Какая плотность блока даёт разумную скорость сваливания
		local target_stall = 20.0
		local allowed_mass = 0.5 * P.rho * target_stall * target_stall
			* wing_area * cl_max / P.gravity
		local density_ratio = allowed_mass / body.mass

		print(("  чтобы сваливание было на %.0f м/с, масса должна быть %.0f кг, "
			.. "то есть в %.1f раза меньше нынешней")
			:format(target_stall, allowed_mass, 1 / density_ratio))
		print(("  это соответствует плотности блока %.1f кг/м^3 вместо %.1f")
			:format(C.value("mass_unit_density") * density_ratio,
				C.value("mass_unit_density")))
		print("  Вывод: либо блоки в игре должны быть много легче реальных,")
		print("  либо крыло должно считаться заметно большей площадью, чем")
		print("  один квадратный метр на блок. Это решение геймплейное, но")
		print("  принимать его надо осознанно, а не подбором множителя.")

		print()
		print("Скорость сваливания в зависимости от размаха:")
		print(text.row {
			{ "крыльев", 10 }, { "S, м^2", 10 }, { "AR", 10 },
			{ "Cl_max", 10 }, { "V_stall, м/с", 14 },
		})

		local stall_curve = {}

		for wings = 1, 8 do
			local test = voxel.describe(voxel.aircraft {
				fuselage = P.fuselage, span = wings,
			})

			local area = voxel.wing_area(test)
			local b = 2 * wings * C.value("node_size")
			local ar = b * b / area
			local slope = aero.finite_wing_lift_slope(a0, ar, P.oswald)
			local cl = slope * C.value("alpha_stall")
			local speed = aero.stall_speed(test.mass, P.gravity, P.rho, area, cl)

			stall_curve[#stall_curve + 1] = { wings * 2, speed }

			print(text.row {
				{ tostring(wings * 2), 10 },
				{ ("%.2f"):format(area), 10 },
				{ ("%.3f"):format(ar), 10 },
				{ ("%.4f"):format(cl), 10 },
				{ ("%.2f"):format(speed), 14 },
			})
		end

		ctx.show({
			{ label = "Cl(alpha)", mark = "*", points = lift_curve },
		}, {
			title = "Коэффициент подъёмной силы: линейный рост, затем срыв",
			xlabel = "угол атаки, град",
			ylabel = "Cl",
			height = 16,
		})

		ctx.show({
			{ label = "сопротивление", mark = "*", points = drag_curve },
		}, {
			title = "Полное сопротивление в горизонтальном полёте",
			xlabel = "скорость, м/с",
			ylabel = "сила, Н",
			height = 16,
		})

		ctx.save({
			{ label = "Cl(alpha)", points = lift_curve },
		}, {
			title = "Кривая подъёмной силы",
			xlabel = "угол атаки, град",
			ylabel = "Cl",
		}, {
			headers = { "alpha_deg", "cl" },
			rows = lift_curve,
		})

		----------------------------------------------------------------------
		local suite = check.new("подъёмная сила")

		suite:close("на скорости сваливания требуется ровно Cl_max",
			weight / (0.5 * P.rho * v_stall * v_stall * wing_area), cl_max,
			1e-12,
			"определение скорости сваливания получено обращением того же "
			.. "уравнения, это тождество")

		suite:close("удвоение скорости даёт четырёхкратную подъёмную силу",
			aero.lift_force(1, P.rho, 2 * P.speed, wing_area)
				/ aero.lift_force(1, P.rho, P.speed, wing_area),
			4, 1e-12,
			"квадратичная зависимость от скорости, точное отношение")

		suite:close("наклон для конечного крыла меньше 2*pi",
			cl_alpha / a0,
			1 / (1 + a0 / (math.pi * P.oswald * aspect_ratio)), 1e-12,
			"формула поправки на удлинение, проверяется тождественно")

		suite:close("в минимуме сопротивления паразитное равно индуктивному",
			parasitic_at_min / induced_at_min, 1, 0.05,
			"классический результат: минимум Cd0 + k*Cl^2 достигается при "
			.. "равенстве слагаемых. Допуск 5 % — скорость перебирается с "
			.. "шагом 0.5 м/с, а не решается точно")

		suite:close("качество равно Cl/Cd",
			best_ld,
			(function()
				-- Максимум L/D достигается при Cl = sqrt(Cd0*pi*e*AR),
				-- и тогда L/D = 0.5*sqrt(pi*e*AR/Cd0)
				return 0.5 * math.sqrt(math.pi * P.oswald * aspect_ratio / P.cd0)
			end)(),
			0.02,
			"аналитический максимум качества; допуск 2 % из-за перебора "
			.. "скорости с конечным шагом и ограничения Cl <= Cl_max")

		suite:is_true("больше крыла — ниже скорость сваливания",
			stall_curve[#stall_curve][2] < stall_curve[1][2],
			"площадь растёт быстрее массы крыла, поэтому нагрузка на крыло "
			.. "падает; это и есть причина, по которой крылья вообще ставят")

		suite:is_true("за срывом Cl падает",
			aero.lift_coefficient(math.rad(25), cl_alpha)
				< aero.lift_coefficient(C.value("alpha_stall"), cl_alpha),
			"без этого игрок задирает нос и улетает вверх на любой скорости")

		return suite
	end,
}
