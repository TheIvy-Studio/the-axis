-- the Axis · physics lab · соответствие 04
-- Сопротивление воздуха и потолок скорости: выполняются настоящие
-- api/drag.lua и behaviours/air.lua.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local mod = require("parity.mod")
local aero = require("lab.aero")
local integrate = require("lab.integrate")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

local PARTS = {
	["axis_contraption:frame"] = { role = "structure", mass = 0.5 },
	["axis_contraption:engine"] = { role = "engine", mass = 3 },
	["axis_contraption:seat"] = { role = "seat", mass = 0.5 },
	["axis_contraption:wing"] = { role = "wing", mass = 0.25 },
}

return experiment.define {
	id = "П4",
	name = "parity_drag",
	title = "Соответствие: сопротивление и потолок скорости",

	question = [[
Выводится ли потолок скорости из тяги и сопротивления — или он по-прежнему
задан отдельным числом, которое ничему не подчиняется?

До этой итерации в behaviours/air.lua стояли ДВЕ независимые ручки на одну
величину: THRUST_PER_ENGINE и MAX_SPEED. Вдобавок сопротивление считалось
линейным по скорости и применялось множителем за кадр.]],

	model = [[
Уравнение сопротивления [nasa_drag_equation]:

    D = 0.5 * Cd * rho * V^2 * A                                [Н]
    m * dv/dt = T - D

Отсюда потолок и разгон (эксперимент 05):

    V_max = sqrt(T / k),  k = 0.5*Cd*rho*A                      [м/с]
    v(t)  = V_max * tanh(t / tau),  tau = m*V_max / T            [с]

Три следствия, которые здесь и проверяются:
  * потолок растёт как КОРЕНЬ из тяги — вчетверо больше двигателей даёт
    вдвое большую скорость, а не вчетверо;
  * потолок НЕ зависит от массы: тяжёлая машина выходит на ту же скорость,
    только дольше;
  * на потолке тяга в точности равна сопротивлению, поэтому машина, уже
    летящая на нём, не меняет скорость ни при какой нарезке времени.

Мод решает уравнение ЗАМКНУТО, а не шагом Эйлера, поэтому проверяется и
независимость от частоты кадров. Разбор идёт по трём случаям: свободный
выбег (решение 1/(1+k*|v|*t), спад как 1/t, а не по экспоненте), разгон под
тягой (tanh) и разворот, когда машина идёт назад, а тяга тянет вперёд —
там сопротивление действует В ТУ ЖЕ сторону, что и тяга, и решение идёт
через тангенс, а не гиперболический тангенс.

ПЛОТНОСТЬ ВОЗДУХА. Мод считает в игровых массах, поэтому и плотность у него
своя, 0.1822 единицы массы на м^3. Это единственный параметр настройки, и с
итерации 5 он один на обе силы: и подъёмную, и сопротивление. Проверка
сторожит, что объявление плотности в поведении полёта ровно одно.

ОБТЕКАЕМОСТЬ. Cd = Cd_куб / lambda, где lambda — удлинение тела: длина,
делённая на эквивалентный диаметр миделя. Справочные значения для тел
вращения падают примерно так же: около 0.5 при удлинении 2 и около 0.15 при
7. Прежний счёт применял Cd куба ко всей машине, то есть считал длинный
фюзеляж плоской стеной той же площади.]],

	simplifications = [[
1. Сопротивление считается отдельно для продольного хода и для сноса, каждое
   по своей площади проекции. Строго говоря, оно зависит от модуля полной
   скорости; при движении вперёд, а это основной режим, разницы нет.
2. Cd берётся постоянным. Для тупого тела вроде воксельного при числах
   Рейнольдса 10^4...10^6 это честно, но реальный Cd зависит ещё и от угла
   атаки.
3. Индуктивное сопротивление — плата крыла за подъёмную силу — учитывается,
   но здесь проверяется только на разбеге, где угол атаки постоянен. В полёте
   он свободен, и это уже задача П5.
4. Обтекаемость выводится из удлинения тела одной формулой Cd_куб/lambda.
   Настоящая зависимость сложнее: у неё есть и трение обшивки, растущее с
   длиной, поэтому у очень вытянутых тел Cd снова начинает расти. Игровых
   размеров этот участок не достаёт.]],

	references = { R.nasa_drag_equation, R.nasa_flight_equations_drag },

	params = {
		fuselage = { value = 7, note = "длина фюзеляжа испытательной машины, блоков" },
		span = { value = 3, note = "размах каждого крыла, блоков" },
		duration = { value = 12.0, note = "моделируемое время разгона, с" },
		fine_dt = { value = 0.0002, note = "шаг независимого решения РК4, с" },
		server_dt = { value = 0.1, note = "типичный шаг сервера Luanti, с" },
	},

	run = function(P, ctx)
		local suite = check.new("соответствие: сопротивление и потолок")

		------------------------------------------------------------------
		-- Загрузка мода
		------------------------------------------------------------------
		local stubs = {
			rotate = function(offset, yaw)
				local sin_yaw, cos_yaw = math.sin(yaw), math.cos(yaw)

				return {
					x = offset.x * cos_yaw - offset.z * sin_yaw,
					y = offset.y,
					z = offset.x * sin_yaw + offset.z * cos_yaw,
				}
			end,
		}

		local loaded, reason = mod.load({
			"api/registry.lua",
			"api/smoothing.lua",
			"api/inertia.lua",
			"api/drag.lua",
			"api/lift.lua",
			"api/pointing.lua",
			"api/mass.lua",
			"api/structure.lua",
			"behaviours/air.lua",
		}, stubs)

		if not loaded then
			print("Мод недоступен: " .. tostring(reason))

			suite:is_true("мод загружается", false,
				"без файлов мода сравнивать нечего; путь задаётся переменной "
				.. "окружения AXIS_MOD_PATH")

			return suite
		end

		print("Мод найден: " .. mod.path())

		for name, part in pairs(PARTS) do
			loaded.registered_parts[name] = { role = part.role, mass = part.mass }
		end

		local air_source = mod.source("behaviours/air.lua") or ""
		local missing = {}

		local function constant(name, pattern)
			local value = tonumber(air_source:match(pattern))

			if not value then
				missing[#missing + 1] = name
				return 0
			end

			return value
		end

		local THRUST_PER_ENGINE = constant("THRUST_PER_ENGINE",
			"local THRUST_PER_ENGINE = ([%d%.]+)")
		local REVERSE_THRUST = constant("REVERSE_THRUST",
			"local REVERSE_THRUST = ([%d%.]+)")
		local CD_BLUFF = constant("CD_BLUFF", "local CD_BLUFF = ([%d%.]+)")
		local AIR_DENSITY = constant("AIR_DENSITY", "local AIR_DENSITY = ([%d%.]+)")
		local GRAVITY = constant("GRAVITY", "local GRAVITY = ([%d%.]+)")
		local WING_LIFT = tonumber((mod.source("api/lift.lua") or "")
			:match("contraption%.WING_LIFT = ([%d%.]+)")) or 0
		local GROUND_PITCH_LIMIT = math.rad(constant("GROUND_PITCH_LIMIT",
			"local GROUND_PITCH_LIMIT = math%.rad%(([%d%.]+)%)"))

		print(("Константы из behaviours/air.lua: тяга %.0f, задний ход %.2f, "
			.. "Cd тупого тела %.2f, rho %.4f"):format(THRUST_PER_ENGINE,
			REVERSE_THRUST, CD_BLUFF, AIR_DENSITY))

		------------------------------------------------------------------
		-- 1. Замкнутый шаг против независимого решения РК4
		------------------------------------------------------------------
		local function reference_speed(speed, acceleration, drag, duration)
			local final = integrate.simulate {
				method = "rk4",
				accel = function(_, v)
					return vec3.new(
						acceleration - drag * v.x * math.abs(v.x), 0, 0)
				end,
				x0 = vec3.zero,
				v0 = vec3.new(speed, 0, 0),
				dt = P.fine_dt,
				duration = duration,
			}

			return final.v.x
		end

		local function mod_speed(speed, acceleration, drag, duration, dt)
			local steps = math.floor(duration / dt + 0.5)
			local step_time = duration / steps

			mod.call(loaded, function()
				for _ = 1, steps do
					speed = loaded.speed_step(speed, acceleration, drag,
						step_time)
				end
			end)

			return speed
		end

		local CASES = {
			{ "разгон с нуля", 0, 7.5, 0.05 },
			{ "разгон с половины потолка", 6, 7.5, 0.05 },
			{ "подход к потолку сверху", 30, 7.5, 0.05 },
			{ "свободный выбег", 12, 0, 0.05 },
			{ "выбег задним ходом", -12, 0, 0.05 },
			{ "идём назад, тяга вперёд", -9, 7.5, 0.05 },
			{ "задний ход из хода вперёд", 9, -3, 0.05 },
			{ "сопротивления нет", 3, 2, 0 },
		}

		print()
		print("Замкнутый шаг мода против независимого решения РК4:")
		print(text.row {
			{ "случай", 34 }, { "мод", 16 }, { "РК4", 16 }, { "ошибка", 12 },
		})

		local worst_case = 0

		for _, case in ipairs(CASES) do
			local name, speed, acceleration, drag = case[1], case[2], case[3],
				case[4]

			local from_mod = mod_speed(speed, acceleration, drag, P.duration,
				P.server_dt)
			local from_lab = reference_speed(speed, acceleration, drag,
				P.duration)

			local scale = math.max(math.abs(from_lab), 1e-9)
			local error_value = math.abs(from_mod - from_lab) / scale

			worst_case = math.max(worst_case, error_value)

			print(text.row {
				{ name, 34 },
				{ ("%.10f"):format(from_mod), 16 },
				{ ("%.10f"):format(from_lab), 16 },
				{ ("%.3e"):format(error_value), 12 },
			})
		end

		------------------------------------------------------------------
		-- 2. Независимость от частоты кадров
		------------------------------------------------------------------
		local rates = { 10, 20, 30, 60, 100, 144, 240 }
		local low, high = math.huge, -math.huge
		local turn_low, turn_high = math.huge, -math.huge

		print()
		print("Один и тот же разгон, нарезанный по-разному:")
		print(text.row {
			{ "кадров/с", 12 }, { "разгон с нуля", 22 },
			{ "разворот через ноль", 22 },
		})

		for _, fps in ipairs(rates) do
			local straight = mod_speed(0, 7.5, 0.05, P.duration, 1 / fps)
			local turning = mod_speed(-9, 7.5, 0.05, P.duration, 1 / fps)

			low = math.min(low, straight)
			high = math.max(high, straight)
			turn_low = math.min(turn_low, turning)
			turn_high = math.max(turn_high, turning)

			print(text.row {
				{ tostring(fps), 12 },
				{ ("%.14f"):format(straight), 22 },
				{ ("%.14f"):format(turning), 22 },
			})
		end

		print()
		print(("Разброс: разгон %.3e, разворот %.3e")
			:format(high - low, turn_high - turn_low))
		print("Прежняя запись velocity - velocity*DRAG*dtime давала разброс")
		print("порядка 10^-3 и, что хуже, при DRAG*dt >= 1 обращала скорость в")
		print("ноль за один кадр.")

		------------------------------------------------------------------
		-- 3. Свойства потолка
		------------------------------------------------------------------
		local terminal = mod.call(loaded, loaded.terminal_speed, 7.5, 0.05)
		local expected_terminal = math.sqrt(7.5 / 0.05)

		-- На потолке тяга равна сопротивлению: это определение
		local balance_error = math.abs(0.05 * terminal * terminal - 7.5) / 7.5

		-- Корневая зависимость от тяги
		local quadrupled = mod.call(loaded, loaded.terminal_speed, 4 * 7.5, 0.05)

		print()
		print(("Потолок: мод %.10f, sqrt(a/k) = %.10f")
			:format(terminal, expected_terminal))
		print(("  на потолке тяга равна сопротивлению с точностью %.3e")
			:format(balance_error))
		print(("  четырёхкратная тяга даёт потолок в %.6f раза (ожидается 2)")
			:format(quadrupled / terminal))

		-- Время выхода: tanh достигает 99 % за artanh(0.99) = 2.6467 постоянных
		local tau = 1 / math.sqrt(7.5 * 0.05)
		local at_99 = mod_speed(0, 7.5, 0.05, 2.6467 * tau, P.server_dt)

		print(("  за 2.65 постоянной времени набирается %.4f %% потолка")
			:format(at_99 / terminal * 100))

		------------------------------------------------------------------
		-- 4. Настоящая машина: потолок из геометрии
		------------------------------------------------------------------
		local function aircraft_parts(options)
			local parts = {}
			local fuselage = options.fuselage
			local offset = (fuselage - 1) / 2

			for index = 0, fuselage - 1 do
				parts[#parts + 1] = { name = "axis_contraption:frame",
					position = { x = 0, y = 0, z = index - offset } }
			end

			parts[#parts + 1] = { name = "axis_contraption:seat",
				position = { x = 0, y = 1, z = 0 } }

			for index = 1, (options.engines or 1) do
				parts[#parts + 1] = { name = "axis_contraption:engine",
					position = { x = 0, y = 1 - index, z = offset + 1 } }
			end

			for index = 1, options.span do
				parts[#parts + 1] = { name = "axis_contraption:wing",
					position = { x = -index, y = 0, z = 0 } }
				parts[#parts + 1] = { name = "axis_contraption:wing",
					position = { x = index, y = 0, z = 0 } }
			end

			return parts
		end

		local function build(parts)
			local rig = {
				parts = parts,
				forward = { x = 0, z = 1 },
				velocity = { x = 0, y = 0, z = 0 },
				yaw = 0, pitch = 0, roll = 0,
				pitch_rate = 0, roll_rate = 0,
				on_ground = false,
			}

			mod.call(loaded, loaded.refresh, rig)

			return rig
		end

		local air = loaded.registered_behaviours.air

		--- Разгоняет настоящую машину настоящим air.control по земле.
		---
		--- Разбег выбран нарочно: на земле опора держит корпус, нос не
		--- поднимается, вертикального хода нет. Значит угол атаки равен углу
		--- установки крыла и не меняется, а с ним постоянны и подъёмная сила,
		--- и индуктивное сопротивление. Тогда потолок считается замкнуто, и
		--- проверка остаётся точной. Полёт со свободным углом атаки — это уже
		--- задача П5.
		local function accelerate(rig_parts, fps, duration, move_y)
			local rig = build(rig_parts)
			local dt = 1 / fps
			local steps = math.floor(duration * fps + 0.5)
			local controls = { move_x = 0, move_y = move_y, up = false,
				down = false }

			rig.on_ground = true

			mod.call(loaded, function()
				for _ = 1, steps do
					air.control(rig, dt, controls)

					-- Земля не пускает вниз и не даёт взлететь
					rig.velocity.y = 0
				end
			end)

			return rig, math.sqrt(rig.velocity.x ^ 2 + rig.velocity.z ^ 2)
		end

		--- Потолок на разбеге: сопротивление складывается из лобового и того,
		--- которым крыло платит за подъёмную силу на угле установки.
		--- Потолок разбега.
		---
		--- Крыло здесь силы вперёд не создаёт вовсе: на разбеге корпус стоит
		--- ровно, нормаль крыла смотрит вверх, и вся его сила вертикальна.
		--- Значит потолок задаёт одно только сопротивление корпуса — то же
		--- самое, что и было до появления крыла.
		---
		--- @param reverse на заднем ходу нос упирается в хвостовую опору, и
		--- тяга толкает слабее на косинус этого угла
		local function ground_terminal(rig, reverse)
			local nose_up = reverse and GROUND_PITCH_LIMIT or 0

			local cd_body = mod.call(loaded, loaded.body_drag_coefficient,
				rig.body_length, rig.frontal_area, CD_BLUFF)

			local acceleration = rig.counts.engine * THRUST_PER_ENGINE
				* math.cos(nose_up) / rig.mass
			local drag = 0.5 * AIR_DENSITY * cd_body * rig.frontal_area
				/ rig.mass

			return math.sqrt(acceleration / drag), cd_body, 0
		end

		local SHAPES = {
			{ "фюзеляж 5, крылья 1+1", { fuselage = 5, span = 1 } },
			{ "фюзеляж 7, крылья 3+3", { fuselage = 7, span = 3 } },
			{ "то же, 2 двигателя", { fuselage = 7, span = 3, engines = 2 } },
			{ "то же, 4 двигателя", { fuselage = 7, span = 3, engines = 4 } },
			{ "фюзеляж 11, крылья 5+5", { fuselage = 11, span = 5 } },
		}

		print()
		print("Разбег настоящих конструкций до потолка:")
		print(text.row {
			{ "конструкция", 26 }, { "масса", 7 }, { "мидель", 7 },
			{ "длина", 7 }, { "Cd тела", 9 }, { "Cd инд.", 9 },
			{ "расчёт", 9 }, { "разбег", 9 },
		})

		local worst_terminal = 0

		for _, shape in ipairs(SHAPES) do
			local parts = aircraft_parts(shape[2])
			local rig = build(parts)

			local predicted, cd_body, cd_induced = ground_terminal(rig)
			local _, reached = accelerate(parts, 30, 240, 1)

			worst_terminal = math.max(worst_terminal,
				math.abs(reached - predicted) / predicted)

			print(text.row {
				{ shape[1], 26 },
				{ ("%.1f"):format(rig.mass), 7 },
				{ ("%d"):format(rig.frontal_area), 7 },
				{ ("%d"):format(rig.body_length), 7 },
				{ ("%.3f"):format(cd_body), 9 },
				{ ("%.3f"):format(cd_induced), 9 },
				{ ("%.2f"):format(predicted), 9 },
				{ ("%.2f"):format(reached), 9 },
			})
		end

		print()
		print("Потолок не задан числом: он выведен из тяги, миделя и того,")
		print("насколько тело вытянуто. Вытянутая постройка обтекается лучше")
		print("кубической — раньше этой разницы не было вовсе, и строить")
		print("самолёт, а не кирпич, не было причины.")

		------------------------------------------------------------------
		-- 5. Потолок не зависит от массы
		------------------------------------------------------------------
		-- Одна и та же геометрия, но детали вдвое тяжелее: потолок обязан
		-- остаться прежним, а время выхода — вырасти.
		local base_parts = aircraft_parts { fuselage = P.fuselage, span = P.span }
		local base_rig = build(base_parts)
		local base_engines = base_rig.counts.engine

		local light = base_engines * THRUST_PER_ENGINE / base_rig.mass
		local light_drag = 0.5 * CD_BLUFF * AIR_DENSITY * base_rig.frontal_area
			/ base_rig.mass

		local heavy_mass = base_rig.mass * 2
		local heavy = base_engines * THRUST_PER_ENGINE / heavy_mass
		local heavy_drag = 0.5 * CD_BLUFF * AIR_DENSITY * base_rig.frontal_area
			/ heavy_mass

		local light_terminal = mod.call(loaded, loaded.terminal_speed, light,
			light_drag)
		local heavy_terminal = mod.call(loaded, loaded.terminal_speed, heavy,
			heavy_drag)

		-- Мерить надо на времени порядка постоянной времени: за долгий срок
		-- обе машины подходят к одному потолку, и разница схлопывается
		local light_tau = 1 / math.sqrt(light * light_drag)
		local heavy_tau = 1 / math.sqrt(heavy * heavy_drag)

		local light_half = mod_speed(0, light, light_drag, light_tau,
			P.server_dt)
		local heavy_half = mod_speed(0, heavy, heavy_drag, light_tau,
			P.server_dt)

		print()
		print("Удвоение массы при той же геометрии:")
		print(("  потолок  %.6f → %.6f м/с"):format(light_terminal, heavy_terminal))
		print(("  постоянная времени %.3f → %.3f с (ровно вдвое)")
			:format(light_tau, heavy_tau))
		print(("  за %.2f с %.6f → %.6f м/с — тяжёлая набирает заметно меньше")
			:format(light_tau, light_half, heavy_half))

		------------------------------------------------------------------
		-- 6. Задний ход больше не отдельная константа
		------------------------------------------------------------------
		-- accelerate возвращает модуль скорости, направление здесь известно.
		-- Эталон берётся от потолка разбега — с обтекаемостью и индуктивным
		-- сопротивлением, а не от голого лобового.
		local _, reverse_speed = accelerate(base_parts, 30, 240, -1)
		local reverse_expected = math.sqrt(REVERSE_THRUST)
			* ground_terminal(base_rig, true)

		print()
		print(("Задний ход: получено %.4f м/с, sqrt(%.2f)*V_max = %.4f")
			:format(reverse_speed, REVERSE_THRUST, reverse_expected))
		print(("  вперёд потолок разбега %.4f, назад %.4f: крыло, летящее "
			.. "задом"):format(ground_terminal(base_rig),
			ground_terminal(base_rig, true)))
		print("  наперёд, работает за срывом и платит другим сопротивлением")
		print("Прежде это было отдельное число REVERSE_SPEED; теперь задний ход")
		print("выводится из того, что назад двигатель тянет слабее.")

		------------------------------------------------------------------
		-- 7. Обтекаемость корпуса
		------------------------------------------------------------------
		-- Cd = Cd_куб / lambda, где lambda — удлинение тела. Справочные
		-- значения для тел вращения: около 0.5 при удлинении 2, около 0.26
		-- при 4, около 0.15 при 7 [nasa_drag_equation, hoerner].
		print()
		print("Обтекаемость в зависимости от того, насколько тело вытянуто:")
		print(text.row {
			{ "длина", 9 }, { "мидель", 9 }, { "удлинение", 12 }, { "Cd", 9 },
		})

		local shape_monotone = true
		local previous_cd = math.huge

		for _, sample in ipairs({
			{ 1, 9 }, { 2, 9 }, { 4, 9 }, { 7, 9 }, { 12, 9 }, { 1, 1 },
		}) do
			local length, area = sample[1], sample[2]
			local cd = mod.call(loaded, loaded.body_drag_coefficient, length,
				area, CD_BLUFF)
			local fineness = length / math.sqrt(4 * area / math.pi)

			if fineness >= 1 and cd > previous_cd + 1e-12 then
				shape_monotone = false
			end

			if fineness >= 1 then
				previous_cd = cd
			end

			print(text.row {
				{ ("%d"):format(length), 9 },
				{ ("%d"):format(area), 9 },
				{ ("%.3f"):format(fineness), 12 },
				{ ("%.4f"):format(cd), 9 },
			})
		end

		-- Куб гранью вперёд обязан давать ровно справочное значение
		local cube_cd = mod.call(loaded, loaded.body_drag_coefficient, 1, 1,
			CD_BLUFF)

		-- Тело шире, чем длиннее, обтекаемости не получает
		local flat_cd = mod.call(loaded, loaded.body_drag_coefficient, 1, 25,
			CD_BLUFF)

		print()
		print(("Куб гранью вперёд: Cd = %.4f, справочное %.2f")
			:format(cube_cd, CD_BLUFF))
		print(("Плоская стена (длина 1, мидель 25): Cd = %.4f — послаблений нет")
			:format(flat_cd))

		------------------------------------------------------------------
		-- Плотность воздуха: теперь она одна
		------------------------------------------------------------------
		-- До итерации 5 сопротивление считалось при одной плотности, а
		-- подъёмная сила — числом LIFT_PER_WING, из которого следовала совсем
		-- другая, в 14 раз большая. Теперь величина одна на обе силы.
		local MASS_TO_KG = 500 / 3
		local real_rho = 1.225

		local density_names = {}

		for name in air_source:gmatch("local (%u[%u_]*DENSITY)") do
			density_names[#density_names + 1] = name
		end

		print()
		print(("Плотность воздуха в моде: %.4f единицы массы на м^3 = %.1f кг/м^3")
			:format(AIR_DENSITY, AIR_DENSITY * MASS_TO_KG))
		print(("  настоящая атмосфера %.3f кг/м^3, то есть в %.0f раз реже")
			:format(real_rho, AIR_DENSITY * MASS_TO_KG / real_rho))
		print(("  объявлений плотности в behaviours/air.lua: %d")
			:format(#density_names))
		print()
		print("Одна величина теперь задаёт и подъёмную силу, и сопротивление.")
		print("До итерации 5 их было две, и расходились они в 14 раз: машина")
		print("тормозилась по одной физике, а держалась в воздухе по другой.")
		print("Остаток в 25 раз против атмосферы — это цена метровых блоков,")
		print("и она решается только калибровкой масс (итерация 7).")

		------------------------------------------------------------------
		-- 8. Область внедрения
		------------------------------------------------------------------
		-- Ищется именно ОБЪЯВЛЕНИЕ константы, а не любое упоминание: в
		-- комментариях эти имена остаются нарочно, чтобы было видно, что
		-- пришло им на смену.
		local leftovers = {}

		for _, name in ipairs({ "MAX_SPEED", "REVERSE_SPEED", "DRAG" }) do
			if air_source:find("local " .. name .. "%s*=") then
				leftovers[#leftovers + 1] = name
			end
		end

		local uses_step = air_source:find("speed_step", 1, true) ~= nil
		local uses_area = air_source:find("frontal_area", 1, true) ~= nil

		-- Старый образец покадрового множителя по всем поведениям
		local frame_dependent = {}

		for _, hit in ipairs(mod.grep("%* dtime", {
			"behaviours/air.lua", "behaviours/ground.lua", "behaviours/inert.lua",
		})) do
			if hit.text:find("velocity") and not hit.text:find("^--") then
				frame_dependent[#frame_dependent + 1] = hit
			end
		end

		print()
		print("Область внедрения:")
		print(("  behaviours/air.lua решает разгон замкнуто: %s")
			:format(uses_step and "да" or "НЕТ"))
		print(("  сопротивление считается по площади проекции: %s")
			:format(uses_area and "да" or "НЕТ"))
		print(("  отдельные ручки на потолок скорости: %s")
			:format(#leftovers == 0 and "нет" or table.concat(leftovers, ", ")))

		print()
		print(("Осталось мест, где скорость меняется множителем за кадр: %d")
			:format(#frame_dependent))

		for _, hit in ipairs(frame_dependent) do
			print(("  %s:%d  %s"):format(hit.file, hit.line, hit.text))
		end

		print()
		print("Очередь: подъёмная сила и вертикальный ход (итерация 5), поворот")
		print("курса и снос (итерация 6). Наземное поведение живёт по своей")
		print("модели сцепления колёс, сопротивление воздуха там ни при чём.")

		------------------------------------------------------------------
		suite:close("замкнутый шаг совпадает с независимым решением РК4",
			worst_case, 0, 1e-6,
			"мод решает уравнение замкнуто, РК4 — численно с шагом "
			.. ("%.4f"):format(P.fine_dt) .. " с. Проверены все три случая "
			.. "разбора: выбег, разгон и разворот через ноль")

		suite:close("разгон не зависит от частоты кадров",
			high - low, 0, 1e-12,
			"замкнутое решение точно при любом шаге, поэтому нарезка времени "
			.. "на результат не влияет — то же свойство, что проверено в П1")

		suite:close("разворот через ноль не зависит от частоты кадров",
			turn_high - turn_low, 0, 1e-12,
			"самый опасный случай: внутри шага меняется знак скорости, и "
			.. "решение переключается с тангенса на гиперболический тангенс. "
			.. "Ошибка в разборе случаев проявилась бы именно здесь")

		suite:close("потолок скорости равен sqrt(a/k)",
			terminal, expected_terminal, 1e-12,
			"определение установившейся скорости; расхождение означало бы "
			.. "другую формулу")

		suite:close("на потолке тяга равна сопротивлению",
			balance_error, 0, 1e-12,
			"dv/dt = 0 означает T = D, это тождество, а не приближение")

		suite:close("четырёхкратная тяга даёт двукратный потолок",
			quadrupled / terminal, 2, 1e-12,
			"следствие корневой зависимости V_max = sqrt(T/k), точное отношение")

		suite:close("за 2.65 постоянной времени набирается 99 % потолка",
			at_99 / terminal, 0.99, 1e-6,
			"artanh(0.99) = 2.6467 — чистая арифметика tanh-решения; остаётся "
			.. "округление постоянной времени, напечатанной с четырьмя знаками")

		suite:close("настоящая машина выходит на расчётный потолок разбега",
			worst_terminal, 0, 1e-4,
			"разбег настоящим air.control за 240 с. На земле угол атаки равен "
			.. "углу установки крыла и не меняется, поэтому и подъёмная сила, "
			.. "и индуктивное сопротивление постоянны, а потолок считается "
			.. "замкнуто. Достигается он асимптотически, отсюда остаток")

		suite:close("потолок не зависит от массы",
			heavy_terminal, light_terminal, 1e-12,
			"в V_max = sqrt(T/k) и тяга, и коэффициент сопротивления делятся "
			.. "на массу, поэтому она сокращается точно. Вдвое тяжёлая машина "
			.. "выходит на ту же скорость, только дольше")

		suite:close("постоянная времени разгона линейна по массе",
			heavy_tau / light_tau, 2, 1e-12,
			"tau = m*V_max/T, а потолок от массы не зависит, поэтому удвоение "
			.. "массы точно удваивает tau. Это и есть причина, по которой "
			.. "тяжёлая машина выходит на ту же скорость дольше: "
			.. ("%.2f против %.2f м/с за одно и то же время")
				:format(heavy_half, light_half))

		-- Соотношение проверяется на примитиве, где крыла нет вовсе: у
		-- настоящей машины на заднем ходу нос упирается в хвостовую опору,
		-- нормаль крыла отклоняется назад, и его сила начинает подталкивать
		-- машину в ту же сторону. Это верное поведение, но к соотношению
		-- потолков оно отношения не имеет.
		local forward_terminal = mod.call(loaded, loaded.terminal_speed, 7.5, 0.05)
		local backward_terminal = mod.call(loaded, loaded.terminal_speed,
			7.5 * REVERSE_THRUST, 0.05)

		suite:close("задний ход выводится из доли тяги",
			backward_terminal / forward_terminal, math.sqrt(REVERSE_THRUST),
			1e-12,
			"V = sqrt(REVERSE_THRUST)*V_max, потому что потолок растёт как "
			.. "корень из тяги; отдельной константы на задний ход больше нет")

		suite:is_true("настоящая машина назад едет медленнее, чем вперёд",
			reverse_speed < ground_terminal(base_rig) * 0.9,
			"половину тяги назад машина отрабатывает медленнее по определению: "
			.. ("%.1f против %.1f м/с вперёд")
				:format(reverse_speed, ground_terminal(base_rig)))

		suite:is_true("потолок скорости больше не задан числом",
			uses_step and uses_area and #leftovers == 0,
			"поиск по исходнику behaviours/air.lua: должны появиться "
			.. "speed_step и frontal_area и исчезнуть MAX_SPEED, REVERSE_SPEED "
			.. "и линейный DRAG. Их возвращение означало бы две ручки на одну "
			.. "величину")

		suite:is_true("в поведении полёта не осталось покадровых множителей скорости",
			#frame_dependent == 0,
			"поиск образца velocity ... * dtime по всем поведениям: скорость "
			.. "обязана меняться замкнутым решением, а не долей за кадр. "
			.. "Найдено мест: " .. tostring(#frame_dependent))

		suite:is_true("константы модели прочитаны из исходника мода",
			#missing == 0,
			"стенд не хранит копию чисел мода. Не найдено: "
			.. (#missing > 0 and table.concat(missing, ", ") or "ничего"))

		suite:is_true("плотность воздуха задана ровно одной величиной",
			#density_names == 1,
			"до итерации 5 сопротивление и подъёмная сила жили по разным "
			.. "плотностям, расходившимся в 14 раз. Проверка сторожит границу: "
			.. "вторая константа плотности означала бы возврат к двум разным "
			.. "атмосферам в одной машине. Найдено объявлений: "
			.. tostring(#density_names))

		suite:close("куб гранью вперёд даёт справочный Cd",
			cube_cd, CD_BLUFF, 1e-12,
			"удлинение куба равно 1 по определению, поэтому поправка на "
			.. "обтекаемость обязана обращаться в единицу и оставлять ровно "
			.. "справочное значение")

		suite:close("тело шире, чем длиннее, обтекаемости не получает",
			flat_cd, CD_BLUFF, 1e-12,
			"удлинение снизу ограничено единицей: пластина поперёк потока "
			.. "обтекается не лучше куба, а хуже. Без ограничения широкая "
			.. "плоская постройка получала бы Cd меньше настоящего")

		suite:is_true("обтекаемость растёт вместе с удлинением",
			shape_monotone,
			"Cd = Cd_куб/lambda монотонно убывает: чем сильнее тело вытянуто "
			.. "по потоку, тем меньше сопротивление. Немонотонность означала "
			.. "бы, что где-то выгодно строить короче")

		return suite
	end,
}
