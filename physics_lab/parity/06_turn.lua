-- the Axis · physics lab · соответствие 06
-- Разворот через крен: выполняется настоящий behaviours/air.lua.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local mod = require("parity.mod")
local aero = require("lab.aero")
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
	id = "П6",
	name = "parity_turn",
	title = "Соответствие: разворот через крен",

	question = [[
Поворачивает ли машина потому, что накренилась, — или курс по-прежнему
меняется сам по себе от нажатой клавиши?

До этой итерации в behaviours/air.lua стояло
    yaw = yaw - move_x * TURN_SPEED * dtime * authority
то есть машина разворачивалась на месте, как танк, и крен был к этому
непричастен.]],

	model = [[
Подъёмная сила перпендикулярна плоскости крыльев. В крене phi она
наклоняется вместе с ними [nasa_banking_turns]:

    вертикаль:    L*cos(phi) = m*g
    горизонталь:  L*sin(phi) = m*V^2 / R

Делим второе на первое — масса и подъёмная сила сокращаются:

    R = V^2 / (g*tan(phi))                                   [м]
    omega = V/R = g*tan(phi)/V                               [рад/с]
    n = L/(m*g) = 1/cos(phi)                                 [—]

Проверяются три вещи.

1. ТОЖДЕСТВО. Темп разворота в моде обязан равняться L*sin(phi)/(m*V) при
   той подъёмной силе, которую даёт уравнение из П5. Это прямая проверка,
   что курс — следствие силы, а не отдельная величина.

2. УСТАНОВИВШИЙСЯ ВИРАЖ. Если подъёмной силы ровно столько, чтобы держать
   высоту (L*cos(phi) = m*g), темп обязан равняться g*tan(phi)/V, радиус
   V^2/(g*tan(phi)), а перегрузка 1/cos(phi). Ни одна из этих величин не
   зависит от массы: тяжёлая и лёгкая машины при том же крене и ходе
   описывают одну окружность.

3. ПРОСАДКА. При том же угле атаки крен отнимает у вертикали косинус:
   машина в вираже проседает, пока пилот не подтянет ручку. Раньше крен был
   картинкой и на высоту не влиял вовсе.

ЭЛЕРОНЫ. Крен создаётся моментом от отклонения элеронов и уравновешивается
демпфированием, поэтому ручка задаёт не угол крена, а СКОРОСТЬ вращения по
крену (эксперимент 08):

    p_ss = M / |L_p|,   tau = I_xx / |L_p|]],

	simplifications = [[
1. Разворот считается координированным: скольжения нет, вектор скорости
   лежит в плоскости симметрии. Настоящий некоординированный разворот требует
   боковой аэродинамики и киля, которых у постройки пока нет.
2. Руля направления в воздухе нет: A и D работают элеронами. Развернуть
   машину, не накреняя её, нельзя — как на настоящем самолёте без педалей.
3. По крену машина нейтральна: отпущенные элероны не выравнивают её. У
   настоящего самолёта это делает поперечное V крыла через скольжение, а
   скольжения здесь нет по пункту 1.
4. Курс интегрируется явно, поэтому от частоты кадров он зависит — но лишь
   первым порядком, и это измеряется.]],

	references = { R.nasa_banking_turns, R.faa_phak },

	params = {
		fuselage = { value = 7, note = "длина фюзеляжа испытательной машины, блоков" },
		span = { value = 3, note = "размах каждого крыла, блоков" },
		speed = { value = 20.0, note = "скорость полёта в опыте, м/с" },
		bank_deg = { value = 30.0, note = "угол крена в опыте, градусы" },
	},

	run = function(P, ctx)
		local suite = check.new("соответствие: разворот через крен")

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

		local GRAVITY = constant("GRAVITY", "local GRAVITY = ([%d%.]+)")
		local AIR_DENSITY = constant("AIR_DENSITY", "local AIR_DENSITY = ([%d%.]+)")
		local CD_BLUFF = constant("CD_BLUFF", "local CD_BLUFF = ([%d%.]+)")
		local WING_LIFT = tonumber((mod.source("api/lift.lua") or "")
			:match("contraption%.WING_LIFT = ([%d%.]+)")) or 0
		local ROLL_COMMAND = math.rad(constant("ROLL_COMMAND",
			"local ROLL_COMMAND = math%.rad%(([%d%.]+)%)"))

		------------------------------------------------------------------
		-- Постройка
		------------------------------------------------------------------
		local function aircraft_parts(options)
			local parts = {}
			local fuselage = options.fuselage
			local offset = (fuselage - 1) / 2
			local extra = options.ballast or 0

			for index = 0, fuselage - 1 do
				parts[#parts + 1] = { name = "axis_contraption:frame",
					position = { x = 0, y = 0, z = index - offset } }
			end

			parts[#parts + 1] = { name = "axis_contraption:seat",
				position = { x = 0, y = 1, z = 0 } }
			parts[#parts + 1] = { name = "axis_contraption:engine",
				position = { x = 0, y = 0, z = offset + 1 } }

			for index = 1, options.span do
				parts[#parts + 1] = { name = "axis_contraption:wing",
					position = { x = -index, y = 0, z = -1 } }
				parts[#parts + 1] = { name = "axis_contraption:wing",
					position = { x = index, y = 0, z = -1 } }
			end

			-- Балласт для проверки независимости разворота от массы: ставится
			-- симметрично и на ту же строку, чтобы не менять ни центровку, ни
			-- площади
			for index = 1, extra do
				parts[#parts + 1] = { name = "axis_contraption:engine",
					position = { x = 0, y = -index, z = 0 } }
			end

			return parts
		end

		local function build(options)
			local rig = {
				parts = aircraft_parts(options),
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
		local base = { fuselage = P.fuselage, span = P.span }

		--- Ставит машину в заданный режим и делает один очень короткий шаг.
		--- Возвращает темп разворота и вертикальное ускорение.
		local function probe(options, speed, bank, pitch, move_x)
			local rig = build(options)

			rig.velocity.x = 0
			rig.velocity.z = speed
			rig.velocity.y = 0
			rig.roll = bank
			rig.pitch = pitch or 0
			rig.yaw = 0

			local step = 1e-6

			mod.call(loaded, air.control, rig, step, {
				move_x = move_x or 0, move_y = 0, up = false, down = false,
			})

			return {
				turn_rate = rig.yaw / step,
				climb_rate = rig.velocity.y / step,
				roll_torque_rate = rig.roll_rate / step,
				rig = rig,
			}
		end

		--- Подъёмная сила по модели, независимо от мода: крыло — плоскость, и
		--- сила линейна по скорости вдоль неё.
		local function lift_of(rig, speed)
			return WING_LIFT * AIR_DENSITY * rig.wing_area * speed
		end

		local sample = build(base)
		local bank = math.rad(P.bank_deg)

		print()
		print(("Машина: масса %.2f, крыло %d м^2, размах %d")
			:format(sample.mass, sample.wing_area, sample.wing_span))

		------------------------------------------------------------------
		-- 1. Тождество: темп разворота есть L*sin(phi)/(m*V)
		------------------------------------------------------------------
		print()
		print("Темп разворота против L*sin(phi)/(m*V):")
		print(text.row {
			{ "крен, °", 10 }, { "мод, рад/с", 14 }, { "модель, рад/с", 15 },
			{ "ошибка", 12 },
		})

		local identity_error = 0

		for _, degrees in ipairs({ 0, 10, 20, 30, 45, 60 }) do
			local phi = math.rad(degrees)
			local measured = probe(base, P.speed, phi).turn_rate
			local lift = lift_of(sample, P.speed)
			local expected = lift * math.sin(phi) / (sample.mass * P.speed)

			local scale = math.max(math.abs(expected), 1e-9)

			identity_error = math.max(identity_error,
				math.abs(measured - expected) / scale)

			print(text.row {
				{ ("%d"):format(degrees), 10 },
				{ ("%.9f"):format(measured), 14 },
				{ ("%.9f"):format(expected), 15 },
				{ ("%.3e"):format(math.abs(measured - expected)), 12 },
			})
		end

		------------------------------------------------------------------
		-- 2. Установившийся вираж
		------------------------------------------------------------------
		-- Когда подъёмной силы ровно хватает на вертикаль (L*cos(phi) = m*g),
		-- темп обязан совпасть с классическим g*tan(phi)/V. Крыло здесь несёт вес
		-- на своей скорости, и она находится делением: сила линейна.
		print()
		print("Установившийся вираж на постоянной высоте:")
		print(text.row {
			{ "крен, °", 9 }, { "скорость", 12 }, { "мод, °/с", 12 },
			{ "g*tan/V, °/с", 14 }, { "R, м", 10 }, { "перегрузка", 12 },
		})

		local turn_error = 0

		local function trim_speed(rig, phi)
			return rig.mass * GRAVITY
				/ (math.cos(phi) * WING_LIFT * AIR_DENSITY * rig.wing_area)
		end

		for _, degrees in ipairs({ 10, 20, 30, 45 }) do
			local phi = math.rad(degrees)
			local speed = trim_speed(sample, phi)

			local measured = probe(base, speed, phi).turn_rate
			local expected = GRAVITY * math.tan(phi) / speed

			turn_error = math.max(turn_error,
				math.abs(measured - expected) / expected)

			print(text.row {
				{ ("%d"):format(degrees), 9 },
				{ ("%.2f"):format(speed), 12 },
				{ ("%.4f"):format(math.deg(measured)), 12 },
				{ ("%.4f"):format(math.deg(expected)), 14 },
				{ ("%.1f"):format(speed * speed / (GRAVITY * math.tan(phi))), 10 },
				{ ("%.3f"):format(1 / math.cos(phi)), 12 },
			})
		end

		------------------------------------------------------------------
		-- 3. Радиус не зависит от массы
		------------------------------------------------------------------
		local heavy_options = { fuselage = P.fuselage, span = P.span, ballast = 3 }
		local heavy = build(heavy_options)

		local light_speed = trim_speed(sample, bank)
		local heavy_speed = trim_speed(heavy, bank)

		local light_radius = light_speed / probe(base, light_speed, bank).turn_rate
		local heavy_radius = heavy_speed
			/ probe(heavy_options, heavy_speed, bank).turn_rate

		print()
		print(("Балласт: масса %.2f → %.2f, потребная скорость %.2f → %.2f м/с")
			:format(sample.mass, heavy.mass, light_speed, heavy_speed))
		print(("  радиус разворота %.2f → %.2f м")
			:format(light_radius, heavy_radius))
		print("  Тяжёлой машине нужен больший ход, но окружность та же: массы в")
		print("  R = V^2/(g*tan(phi)) нет вовсе.")

		------------------------------------------------------------------
		-- 4. Крен от ручки
		------------------------------------------------------------------
		-- Ручка задаёт автомату цель, и корпус приходит к ней; отпущенная ручка
		-- возвращает машину в горизонт.
		local function hold(move_x, seconds, start_roll)
			local rig = build(base)

			rig.roll = start_roll or 0

			mod.call(loaded, function()
				for _ = 1, math.floor(seconds * 60) do
					rig.velocity.x = 0
					rig.velocity.z = light_speed
					rig.velocity.y = 0

					air.control(rig, 1 / 60, { move_x = move_x, move_y = 0,
						up = false, down = false })
				end
			end)

			return rig
		end

		local rolled = hold(1, 3)
		local levelled = hold(0, 3, math.rad(40))

		print()
		print(("Ручка вбок 3 с: крен %.2f° при заказанных %.0f°")
			:format(math.deg(rolled.roll), math.deg(ROLL_COMMAND)))
		print(("Отпущенная ручка: крен с 40° сошёл до %.2f°")
			:format(math.deg(levelled.roll)))

		------------------------------------------------------------------
		-- 6. В воздухе курс не меняется без крена
		------------------------------------------------------------------
		local straight = probe(base, P.speed, 0, 0, 1)

		print()
		print(("Ручка вбок при нулевом крене: темп разворота %.3e рад/с")
			:format(straight.turn_rate))
		print("Развернуться, не накреняясь, нельзя: руля направления в воздухе")
		print("нет, A и D работают элеронами.")

		-- А на земле — можно: там курс задаёт колесо
		local ground = build(base)

		ground.velocity.z = 10
		ground.on_ground = true

		mod.call(loaded, air.control, ground, 0.1,
			{ move_x = 1, move_y = 0, up = false, down = false })

		print(("На земле та же ручка поворачивает: курс %.4f°")
			:format(math.deg(ground.yaw)))

		------------------------------------------------------------------
		-- 7. Область внедрения
		------------------------------------------------------------------
		local leftovers = {}

		for _, name in ipairs({ "TURN_SPEED", "RUDDER_SPEED", "DRIFT_PER_NODE" }) do
			if air_source:find("local " .. name .. "%s*=") then
				leftovers[#leftovers + 1] = name
			end
		end

		local uses_bank = air_source:find("sin_roll", 1, true) ~= nil
		local uses_aileron = air_source:find("AILERON", 1, true) ~= nil

		print()
		print("Область внедрения:")
		print(("  курс выводится из крена: %s")
			:format(uses_bank and "да" or "НЕТ"))
		print(("  крен создаётся элеронами: %s")
			:format(uses_aileron and "да" or "НЕТ"))
		print(("  прежние ручки на поворот: %s")
			:format(#leftovers == 0 and "нет" or table.concat(leftovers, ", ")))
		print()
		print("Очередь: киля у постройки нет, поэтому нет ни путевой")
		print("устойчивости, ни скольжения (эксперимент 09). Калибровка масс")
		print("природных блоков — итерация 7.")

		------------------------------------------------------------------
		suite:close("темп разворота равен L*sin(phi)/(m*V)",
			identity_error, 0, 1e-9,
			"прямое тождество: курс меняется ровно от горизонтальной составляющей "
			.. "подъёмной силы. Сама сила считается здесь независимо, по формуле "
			.. "крыла-плоскости")

		suite:close("в установившемся вираже темп равен g*tan(phi)/V",
			turn_error, 0, 1e-9,
			"классическое соотношение получается делением горизонтали на "
			.. "вертикаль, когда подъёмной силы ровно хватает на высоту. Скорость "
			.. "для этого берётся прямо: сила линейна по ней")

		suite:close("радиус разворота не зависит от массы",
			heavy_radius, light_radius, 1e-6,
			"в R = V^2/(g*tan(phi)) массы нет вовсе. Тяжёлой машине нужен больший "
			.. "ход, чтобы держаться в вираже, но окружность она описывает ту же")

		suite:is_true("ручка доводит крен до заказанного",
			math.abs(math.abs(rolled.roll) - ROLL_COMMAND) < math.rad(6),
			"автомат приводит корпус к цели, которую задала ручка: "
			.. ("%.1f° при заказанных %.0f°"):format(math.deg(rolled.roll),
				math.deg(ROLL_COMMAND)))

		suite:is_true("отпущенная ручка возвращает машину в горизонт",
			math.abs(levelled.roll) < math.rad(3),
			"цель автомата становится нулевой, и крен сходит на нет: с 40° до "
			.. ("%.1f° за три секунды"):format(math.deg(levelled.roll)))

		suite:close("без крена курс в воздухе не меняется",
			straight.turn_rate, 0, 1e-12,
			"руля направления в воздухе нет: развернуться можно только "
			.. "накренившись. Ненулевой темп означал бы, что где-то остался "
			.. "прямой поворот курса")

		suite:is_true("на земле курс всё же задаётся колесом",
			math.abs(ground.yaw) > 1e-6,
			"крена на земле нет — его держит опора, — поэтому рулить там "
			.. "нечем, кроме колеса. Без этого машина не смогла бы даже "
			.. "развернуться перед разбегом")

		suite:is_true("прямого поворота курса больше нет",
			uses_bank and uses_aileron and #leftovers == 0,
			"поиск по исходнику behaviours/air.lua: должны появиться разворот "
			.. "от крена и элероны, а TURN_SPEED с прежними ручками исчезнуть")

		suite:is_true("константы модели прочитаны из исходника мода",
			#missing == 0,
			"стенд не хранит копию чисел мода. Не найдено: "
			.. (#missing > 0 and table.concat(missing, ", ") or "ничего"))

		return suite
	end,
}
