-- the Axis · physics lab · соответствие 05
-- Крыло как плоскость: выполняются настоящие api/lift.lua и behaviours/air.lua.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local mod = require("parity.mod")
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
	id = "П5",
	name = "parity_lift",
	title = "Соответствие: крыло как плоскость",

	question = [[
Держится ли машина в воздухе крылом — и остаётся ли при этом управляемой?

Модель по уравнению NASA была честной, но летать по ней оказалось тяжело:
приходилось постоянно держать ручку, следить за углом атаки и не сваливаться.
Крыло заменено на плоскость с нормалью, как в моде Sable для Create.]],

	model = [[
Крыло — плоскость с нормалью, направленной вверх по корпусу:

    подъёмная сила   L =  K_lift  * rho * S * |скорость вдоль плоскости|
    поперечная сила  P = -K_plate * rho * S * (скорость вдоль нормали)

Обе линейны по скорости, а не квадратичны, поэтому коэффициенты имеют
размерность скорости. Отношение K_plate/K_lift = 1.58, как у Sable (0.75
против 0.475): поперёк крыло тормозит сильнее, чем тянет вдоль, и именно это
гасит просадку без всякого автопилота.

Проверяемые следствия:

  * величина подъёмной силы НЕ зависит от наклона корпуса — поворачивается
    только её направление, и это и есть всё управление высотой;
  * удвоение скорости даёт удвоение силы, а не учетверение;
  * крыло, идущее ровно поперёк потока, не тянет вовсе;
  * сорваться нельзя ни при каком наклоне: сила никуда не пропадает.

АВТОМАТ СТАБИЛИЗАЦИИ. Ручка задаёт целевой угол, автомат приводит к нему
корпус: жёсткость I*w^2 и демпфирование 2*zeta*I*w при zeta = 1. Отпустил
ручку — цель нулевая. Проверяется, что корпус приходит к цели и не качается.]],

	simplifications = [[
1. Угла атаки, срыва, скорости сваливания и индуктивного сопротивления в
   модели нет вовсе. Планирование по поляре ушло вместе с ними — это цена
   простого управления.
2. Все крылья считаются одной плоскостью с общей нормалью вверх по корпусу.
   Крыло, поставленное набок, работает как обычное.
3. Наклон ограничен упором: за 60 градусов по тангажу и 75 по крену корпус не
   идёт. Без упора момент крыла у неудачной постройки способен поставить
   машину на попа.]],

	references = { R.nasa_lift_equation, R.faa_phak },

	params = {
		fuselage = { value = 7, note = "длина фюзеляжа испытательной машины, блоков" },
		span = { value = 3, note = "размах каждого крыла, блоков" },
		duration = { value = 6.0, note = "моделируемое время, с" },
	},

	run = function(P, ctx)
		local suite = check.new("соответствие: крыло как плоскость")

		local loaded, reason = mod.load({
			"api/registry.lua", "api/smoothing.lua", "api/inertia.lua",
			"api/drag.lua", "api/lift.lua", "api/pointing.lua", "api/mass.lua",
			"api/structure.lua", "behaviours/air.lua",
		}, {
			rotate = function(offset, yaw)
				local sin_yaw, cos_yaw = math.sin(yaw), math.cos(yaw)

				return {
					x = offset.x * cos_yaw - offset.z * sin_yaw,
					y = offset.y,
					z = offset.x * sin_yaw + offset.z * cos_yaw,
				}
			end,
		})

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
		local lift_source = mod.source("api/lift.lua") or ""
		local missing = {}

		local function constant(source, name, pattern)
			local value = tonumber(source:match(pattern))

			if not value then
				missing[#missing + 1] = name
				return 0
			end

			return value
		end

		local GRAVITY = constant(air_source, "GRAVITY", "local GRAVITY = ([%d%.]+)")
		local AIR_DENSITY = constant(air_source, "AIR_DENSITY",
			"local AIR_DENSITY = ([%d%.]+)")
		local WING_LIFT = constant(lift_source, "WING_LIFT",
			"contraption%.WING_LIFT = ([%d%.]+)")
		local PLATE_RATIO = constant(lift_source, "WING_PLATE",
			"contraption%.WING_PLATE = [%d%.]+ %* ([%d%.]+)")
		local STABILISER = constant(air_source, "STABILISER_FREQUENCY",
			"local STABILISER_FREQUENCY = ([%d%.]+)")
		local PITCH_COMMAND = math.rad(constant(air_source, "PITCH_COMMAND",
			"local PITCH_COMMAND = math%.rad%(([%d%.]+)%)"))

		local WING_PLATE = WING_LIFT * PLATE_RATIO

		print()
		print(("Коэффициенты: подъёмная сила %.2f, поперечная %.2f "
			.. "(отношение %.2f), автомат %.1f рад/с")
			:format(WING_LIFT, WING_PLATE, PLATE_RATIO, STABILISER))

		------------------------------------------------------------------
		-- 1. Примитив против формулы
		------------------------------------------------------------------
		local force_error = 0

		for _, flow in ipairs({
			{ x = 0, y = 0, z = 10 }, { x = 3, y = -2, z = 8 },
			{ x = 0, y = 5, z = 0 }, { x = -6, y = 1.5, z = -4 },
		}) do
			for _, area in ipairs({ 1, 4, 6, 12 }) do
				local lift, plate = mod.call(loaded, loaded.wing_force, flow,
					area, AIR_DENSITY)

				local along = math.sqrt(flow.x * flow.x + flow.z * flow.z)

				force_error = math.max(force_error,
					math.abs(lift - WING_LIFT * AIR_DENSITY * area * along),
					math.abs(plate + WING_PLATE * AIR_DENSITY * area * flow.y))
			end
		end

		print(("Сила крыла против формулы: %.3e"):format(force_error))

		local single = mod.call(loaded, loaded.wing_force,
			{ x = 0, y = 0, z = 10 }, 6, AIR_DENSITY)
		local doubled = mod.call(loaded, loaded.wing_force,
			{ x = 0, y = 0, z = 20 }, 6, AIR_DENSITY)
		local wider = mod.call(loaded, loaded.wing_force,
			{ x = 0, y = 0, z = 10 }, 12, AIR_DENSITY)
		local edge = mod.call(loaded, loaded.wing_force,
			{ x = 0, y = 7, z = 0 }, 6, AIR_DENSITY)

		print(("Удвоение скорости: %.2f → %.2f (отношение %.3f)")
			:format(single, doubled, doubled / single))
		print(("Удвоение площади:  %.2f → %.2f (отношение %.3f)")
			:format(single, wider, wider / single))

		------------------------------------------------------------------
		-- 2. Испытательная машина
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
			parts[#parts + 1] = { name = "axis_contraption:engine",
				position = { x = 0, y = 0, z = offset + 1 } }

			for index = 1, options.span do
				parts[#parts + 1] = { name = "axis_contraption:wing",
					position = { x = -index, y = 0, z = -1 } }
				parts[#parts + 1] = { name = "axis_contraption:wing",
					position = { x = index, y = 0, z = -1 } }
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
		local machine = build(base)

		-- Скорость, на которой крыло несёт вес. Сила линейна по скорости,
		-- поэтому она находится делением, а не корнем.
		local carry = machine.mass * GRAVITY
			/ (WING_LIFT * AIR_DENSITY * machine.wing_area)

		print()
		print(("Машина: масса %.2f, крыло %d м^2, размах %d")
			:format(machine.mass, machine.wing_area, machine.wing_span))
		print(("  висит на %.2f м/с; ниже снижается, выше набирает высоту")
			:format(carry))

		------------------------------------------------------------------
		-- 3. Наклон поворачивает силу, а не меняет её
		------------------------------------------------------------------
		local function probe(pitch, roll, speed)
			local rig = build(base)

			rig.pitch, rig.roll = pitch, roll
			rig.velocity.z = speed

			local step = 1e-6

			mod.call(loaded, air.control, rig, step,
				{ move_x = 0, move_y = 0, up = false, down = false })

			return rig.velocity.y / step + GRAVITY
		end

		local level = probe(0, 0, 15)
		local banked = probe(0, math.rad(30), 15)

		print()
		print("Вертикальная составляющая подъёмной силы:")
		print(text.row {
			{ "положение", 22 }, { "ускорение, м/с^2", 18 },
			{ "доля от ровного", 18 },
		})

		for _, case in ipairs({ { "ровно", level }, { "крен 30°", banked } }) do
			print(text.row {
				{ case[1], 22 },
				{ ("%.4f"):format(case[2]), 18 },
				{ ("%.4f"):format(case[2] / level), 18 },
			})
		end

		print()
		print("Сама сила не изменилась: повернулось направление. Косинус крена —")
		print("это и есть то, чем машина проседает в вираже.")

		------------------------------------------------------------------
		-- 4. Полёт
		------------------------------------------------------------------
		local function fly(duration, fps, up, down)
			local rig = build(base)

			rig.velocity.z = carry * 1.5

			local steps = math.floor(duration * fps + 0.5)
			local dt = 1 / fps
			local controls = { move_x = 0, move_y = 1, up = up or false,
				down = down or false }

			mod.call(loaded, function()
				for _ = 1, steps do
					air.control(rig, dt, controls)
				end
			end)

			return rig
		end

		local cruise = fly(P.duration, 60)
		local climbing = fly(P.duration, 60, true)
		local diving = fly(P.duration, 60, false, true)

		print()
		print(("Через %.0f с полного газа:"):format(P.duration))
		print(("  ручку не трогая: тангаж %.2f°, крен %.2f°, вертикаль %.2f м/с")
			:format(math.deg(-cruise.pitch), math.deg(cruise.roll),
				cruise.velocity.y))
		print(("  ручка на себя:   тангаж %.2f°, вертикаль %.2f м/с")
			:format(math.deg(-climbing.pitch), climbing.velocity.y))
		print(("  ручка от себя:   тангаж %.2f°, вертикаль %.2f м/с")
			:format(math.deg(-diving.pitch), diving.velocity.y))
		print("Вертикальный ход упирается в предел, поэтому ручка читается по")
		print("углу: он и есть то, чем игрок управляет.")

		------------------------------------------------------------------
		-- 5. Автомат стабилизации
		------------------------------------------------------------------
		local disturbed = build(base)

		disturbed.pitch = math.rad(40)
		disturbed.velocity.z = carry * 1.5

		local worst_overshoot = 0

		mod.call(loaded, function()
			for step = 1, 60 * 4 do
				air.control(disturbed, 1 / 60,
					{ move_x = 0, move_y = 0, up = false, down = false })

				if step > 30 then
					worst_overshoot = math.max(worst_overshoot,
						math.max(0, -disturbed.pitch))
				end
			end
		end)

		local stalled = probe(math.rad(60), 0, 15)

		print()
		print(("Корпус, сбитый на 40°, через 4 с: тангаж %.3f°, перелёт %.3f°")
			:format(math.deg(disturbed.pitch), math.deg(worst_overshoot)))
		print(("На упоре 60° подъёмная сила ещё %.0f %% от ровного полёта")
			:format(stalled / level * 100))

		------------------------------------------------------------------
		-- 6. Область внедрения
		------------------------------------------------------------------
		local leftovers = {}

		for _, name in ipairs({ "ALPHA_STALL", "WING_INCIDENCE",
				"ELEVATOR_FRACTION", "AILERON_FRACTION" }) do
			if air_source:find("local " .. name .. "%s*=") then
				leftovers[#leftovers + 1] = name
			end
		end

		local uses_plane = air_source:find("wing_force", 1, true) ~= nil
		local uses_stabiliser = air_source:find("STABILISER_FREQUENCY", 1, true)
			~= nil
		local no_alpha = not lift_source:find("lift_coefficient", 1, true)

		print()
		print("Область внедрения:")
		print(("  крыло считается плоскостью с нормалью: %s")
			:format(uses_plane and "да" or "НЕТ"))
		print(("  автомат стабилизации есть: %s")
			:format(uses_stabiliser and "да" or "НЕТ"))
		print(("  угол атаки и срыв убраны: %s")
			:format(no_alpha and "да" or "НЕТ"))
		print(("  прежние числа остались: %s")
			:format(#leftovers == 0 and "нет" or table.concat(leftovers, ", ")))

		------------------------------------------------------------------
		suite:close("сила крыла совпадает с формулой",
			force_error, 0, 1e-12,
			"мод и проверка считают одно выражение; коэффициенты прочитаны из "
			.. "исходника api/lift.lua, а не записаны здесь копией")

		suite:close("удвоение скорости удваивает подъёмную силу",
			doubled / single, 2, 1e-12,
			"сила линейна по скорости — в этом и состоит замена квадратичной "
			.. "модели. При квадратичной вышло бы четыре")

		suite:close("удвоение площади удваивает подъёмную силу",
			wider / single, 2, 1e-12,
			"площадь входит множителем; больше крыла — лучше несёт, и это "
			.. "единственное, чем постройка влияет на подъёмную силу")

		suite:close("крыло, идущее ровно поперёк потока, не тянет",
			edge, 0, 1e-12,
			"подъёмная сила считается от скорости ВДОЛЬ плоскости крыла; когда "
			.. "поток бьёт строго в брюхо, вдоль ничего не течёт")

		suite:close("в крене вертикали остаётся косинус",
			banked / level, math.cos(math.rad(30)), 1e-6,
			"сила не изменилась, повернулось направление. Отсюда и просадка в "
			.. "вираже, и перегрузка 1/cos — то же самое, что было в честной "
			.. "модели")

		suite:is_true("машина висит на разумной скорости",
			carry > 4 and carry < 15,
			"скорость несения обратно пропорциональна площади крыла; у "
			.. "испытательной машины она "
			.. ("%.1f м/с при потолке около 22"):format(carry))

		suite:is_true("без ручки машина летит ровно",
			math.abs(cruise.pitch) < math.rad(25)
				and math.abs(cruise.roll) < math.rad(5),
			"автомат держит корпус у горизонта, а момент крыла лишь смещает "
			.. "равновесие: " .. ("тангаж %.1f°, крен %.1f°")
				:format(math.deg(-cruise.pitch), math.deg(cruise.roll)))

		suite:is_true("ручка поднимает и опускает нос",
			climbing.pitch < cruise.pitch and diving.pitch > cruise.pitch,
			"цель автомата смещается на "
			.. ("%.0f°"):format(math.deg(PITCH_COMMAND))
			.. " в ту сторону, куда взята ручка. Сравнивается именно угол: "
			.. "вертикальный ход упирается в предел и на нём обе команды "
			.. "выглядели бы одинаково. "
			.. ("На себя %.1f°, ровно %.1f°, от себя %.1f°")
				:format(math.deg(-climbing.pitch), math.deg(-cruise.pitch),
					math.deg(-diving.pitch)))

		suite:is_true("ручка от себя переводит машину в снижение",
			diving.velocity.y < cruise.velocity.y,
			"нос вниз — вертикальная составляющая подъёмной силы падает, и "
			.. ("машина идёт вниз: %.2f против %.2f м/с")
				:format(diving.velocity.y, cruise.velocity.y))

		suite:is_true("сбитый корпус возвращается к горизонту",
			math.abs(disturbed.pitch) < math.rad(25),
			"автомат приводит корпус к цели за время порядка "
			.. ("1/%.1f"):format(STABILISER) .. " секунды. Остаток — это "
			.. "равновесие под моментом крыла, а не незатухшее колебание: "
			.. ("%.1f°"):format(math.deg(disturbed.pitch)))

		suite:close("автомат не перелетает через цель",
			worst_overshoot, 0, 1e-9,
			"затухание критическое, поэтому корпус подходит к цели с одной "
			.. "стороны. Перелёт означал бы качание, от которого и уходили")

		suite:is_true("свалиться нельзя ни при каком наклоне",
			stalled > 0,
			"подъёмная сила никуда не пропадает: она считается от скорости "
			.. "вдоль крыла, а не от угла атаки. На упоре по тангажу остаётся "
			.. ("%.0f %% от ровного полёта"):format(stalled / level * 100))

		suite:is_true("крыло считается плоскостью, а не профилем",
			uses_plane and uses_stabiliser and no_alpha and #leftovers == 0,
			"поиск по исходникам: должны появиться wing_force и автомат "
			.. "стабилизации, а угол атаки со срывом исчезнуть")

		suite:is_true("константы модели прочитаны из исходника мода",
			#missing == 0,
			"стенд не хранит копию чисел мода. Не найдено: "
			.. (#missing > 0 and table.concat(missing, ", ") or "ничего"))

		return suite
	end,
}
