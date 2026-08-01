-- the Axis · physics lab · соответствие 03
-- Инерция вращения: выполняются НАСТОЯЩИЕ api/inertia.lua, api/structure.lua
-- и behaviours/air.lua.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local mod = require("parity.mod")
local rigid = require("lab.rigid")
local integrate = require("lab.integrate")
local vec3 = require("lab.vec3")
local mat3 = require("lab.mat3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

--------------------------------------------------------------------------------
-- Детали мода. Массы обязаны совпадать с parts/basic.lua и parts/aircraft.lua,
-- и это проверяется чтением самих файлов, а не доверием к списку.
--------------------------------------------------------------------------------
local PARTS = {
	["axis_contraption:frame"] = { role = "structure", mass = 0.5, source = "frame" },
	["axis_contraption:panel"] = { role = "structure", mass = 0.25, source = "panel" },
	["axis_contraption:engine"] = { role = "engine", mass = 3, source = "engine" },
	["axis_contraption:wheel"] = { role = "wheel", mass = 1, source = "wheel" },
	["axis_contraption:seat"] = { role = "seat", mass = 0.5, source = "seat" },
	["axis_contraption:wing"] = { role = "wing", mass = 0.25, source = "wing" },
}

return experiment.define {
	id = "П3",
	name = "parity_inertia",
	title = "Соответствие: инерция вращения",

	question = [[
Считает ли мод вращение конструкции как динамику твёрдого тела — с моментом
инерции, моментом силы и угловой скоростью, — или по-прежнему подтягивает угол
наклона к заранее назначенному значению?

Проверка загружает настоящие api/inertia.lua, api/structure.lua и
behaviours/air.lua, строит ими конструкцию и выполняет их же покадрово.]],

	model = [[
ТЕНЗОР ИНЕРЦИИ (эксперимент 11, [mit_16_07_l26]):

    I_xx = sum m*(y^2 + z^2)      I_xy = -sum m*x*y
    I_yy = sum m*(x^2 + z^2)      I_xz = -sum m*x*z
    I_zz = sum m*(x^2 + y^2)      I_yz = -sum m*y*z

плюс собственный момент блока m*s^2/6 по каждой диагонали. Эталон для цепочки
блоков — однородный брус m*(L^2 + s^2)/12, и совпадение обязано быть точным.

УРАВНЕНИЯ ЭЙЛЕРА (эксперимент 12, [mit_16_07_l28]):

    dw/dt = I^-1 * (M - w x (I*w))                            [рад/с^2]

При нулевом внешнем моменте |I*w| и 0.5*w.(I*w) — точные интегралы движения.

УГЛОВОЕ ДВИЖЕНИЕ ВОКРУГ ОСИ (эксперименты 07, 08, 19):

    I * th'' = M + k*th + c*th'

k — производная момента по углу (продольная устойчивость, M_alpha),
c — производная момента по угловой скорости (демпфирование, M_q и L_p).
Мод решает это уравнение ЗАМКНУТО, а не шагом Эйлера, поэтому проверяется
три вещи сразу: совпадение с независимым решением РК4, независимость от
частоты кадров и устойчивость при сколь угодно длинном кадре (эксперимент 17
даёт для явной схемы предел w_n*dt < 2; у замкнутого решения предела нет).

ШКАЛА МАСС. Мод считает в игровых массах, а не в килограммах, и для вращения
перевод не нужен: момент подъёмной силы и момент инерции линейны по массе,
поэтому в угловом ускорении множитель сокращается. Это проверяется численно —
та же задача, посчитанная в килограммах, даёт тот же угол.

ЧТО ПРОВЕРЯЕТСЯ ЗДЕСЬ, А ЧТО В ДРУГИХ МЕСТАХ. Эта проверка отвечает за
инерцию вращения и за решение углового уравнения. Аэродинамика полёта —
подъёмная сила, сваливание, планирование — живёт в П5, а сопротивление и
потолок скорости в П4. Разделение по узлам: каждая проверка сторожит свою
итерацию, и расхождение сразу показывает, где искать.]],

	simplifications = [[
1. Линейная часть углового движения решается по осям раздельно, каждая по
   своему диагональному моменту инерции; связь осей остаётся только в
   гироскопическом члене w x (I*w). У постройки, симметричной относительно
   продольной плоскости, центробежные моменты в этих осях и так нули, так что
   потери нет; у перекошенной — это приближение.
2. Рыскание в моде пока задаётся рулём напрямую, а не решается из момента
   (итерация 6), поэтому уравнения Эйлера здесь используются в двух
   компонентах из трёх.
3. Проверяется угловое движение, а не полёт целиком: коэффициенты уравнения
   задаются здесь напрямую, а не берутся из аэродинамики. Что мод считает их
   верно, показывает П5.]],

	references = { R.mit_16_07_l26, R.mit_16_07_l28, R.etkin_dynamics },

	params = {
		rod_blocks = { value = 11, note = "длина эталонного стержня, блоков" },
		fuselage = { value = 7, note = "длина фюзеляжа испытательной машины, блоков" },
		span = { value = 3, note = "размах каждого крыла, блоков" },
		duration = { value = 3.0, note = "моделируемое время, с" },
		fine_dt = { value = 0.0002, note = "шаг независимого решения РК4, с" },
		server_dt = { value = 0.1, note = "типичный шаг сервера Luanti, с" },
	},

	run = function(P, ctx)
		local suite = check.new("соответствие: инерция вращения")

		------------------------------------------------------------------
		-- Загрузка настоящих файлов мода
		------------------------------------------------------------------
		local stubs = {
			-- Настоящий поворот вокруг вертикали, как в api/geometry.lua
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
			"api/envelope.lua",
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

		local air_source = mod.source("behaviours/air.lua") or ""

		local function air_source_value(pattern)
			return air_source:match(pattern)
		end

		-- Детали объявляются напрямую: register_part зовёт core.register_node,
		-- которого вне сервера нет. Числа сверяются с исходником ниже.
		for name, part in pairs(PARTS) do
			loaded.registered_parts[name] = { role = part.role, mass = part.mass }
		end

		------------------------------------------------------------------
		-- Массы деталей: числа в проверке против исходника мода
		------------------------------------------------------------------
		local basic = mod.source("parts/basic.lua") or ""
		local aircraft = mod.source("parts/aircraft.lua") or ""
		local sources = basic .. "\n" .. aircraft
		local mass_mismatch = {}

		for name, part in pairs(PARTS) do
			local declared = sources:match('register_part%("' .. part.source
				.. '".-mass = ([%d%.]+)')

			if tonumber(declared) ~= part.mass then
				mass_mismatch[#mass_mismatch + 1] = ("%s: в проверке %d, в моде %s")
					:format(name, part.mass, tostring(declared))
			end
		end

		print(("Массы деталей сверены с parts/*.lua: расхождений %d")
			:format(#mass_mismatch))

		for _, line in ipairs(mass_mismatch) do
			print("  " .. line)
		end

		------------------------------------------------------------------
		-- Постройка конструкций
		------------------------------------------------------------------
		--- Список деталей испытательной машины в осях корпуса:
		--- Z — вдоль носа, X — вправо, Y — вверх.
		local function aircraft_parts(options)
			local parts = {}
			local fuselage = options.fuselage
			local offset = (fuselage - 1) / 2
			local station = options.station or 0

			for index = 0, fuselage - 1 do
				parts[#parts + 1] = { name = "axis_contraption:frame",
					position = { x = 0, y = 0, z = index - offset } }
			end

			parts[#parts + 1] = { name = "axis_contraption:engine",
				position = { x = 0, y = 0, z = offset + 1 } }

			parts[#parts + 1] = { name = "axis_contraption:seat",
				position = { x = 0, y = 1, z = 0 } }

			for index = 1, options.left do
				parts[#parts + 1] = { name = "axis_contraption:wing",
					position = { x = -index, y = 0, z = station } }
			end

			for index = 1, options.right do
				parts[#parts + 1] = { name = "axis_contraption:wing",
					position = { x = index, y = 0, z = station } }
			end

			return parts
		end

		--- Прогоняет настоящий contraption.refresh и возвращает конструкцию.
		local function build(parts, forward)
			local rig = {
				parts = parts,
				forward = forward or { x = 0, z = 1 },
				velocity = { x = 0, y = 0, z = 0 },
				yaw = 0, pitch = 0, roll = 0,
				pitch_rate = 0, roll_rate = 0,
				on_ground = false,
			}

			mod.call(loaded, loaded.refresh, rig)

			return rig
		end

		--- Те же детали как точечные массы для lab/rigid.lua.
		local function as_points(parts, mass_scale)
			local points = {}

			for index, part in ipairs(parts) do
				points[index] = {
					position = vec3.new(part.position.x, part.position.y,
						part.position.z),
					mass = PARTS[part.name].mass * (mass_scale or 1),
				}
			end

			return points
		end

		------------------------------------------------------------------
		-- 1. Тензор инерции против эталона лаборатории
		------------------------------------------------------------------
		local rod = {}

		do
			local offset = (P.rod_blocks - 1) / 2

			for index = 0, P.rod_blocks - 1 do
				rod[#rod + 1] = { name = "axis_contraption:frame",
					position = { x = 0, y = 0, z = index - offset } }
			end
		end

		local rod_points = as_points(rod)
		local rod_centre, rod_mass = rigid.centre_of_mass(rod_points)
		local rod_reference = rigid.inertia_tensor(rod_points, rod_centre, 1)
		local rod_from_mod = mod.call(loaded, loaded.inertia_tensor, rod_points,
			rod_centre, 1)

		local function worst_difference(a, b)
			local worst = 0

			for i = 1, 3 do
				for j = 1, 3 do
					worst = math.max(worst, math.abs(a[i][j] - b[i][j]))
				end
			end

			return worst
		end

		local rod_error = worst_difference(rod_from_mod, rod_reference)

		local length = P.rod_blocks
		local solid_box = rod_mass * (length * length + 1) / 12

		print()
		print(("Стержень из %d блоков, игровая масса %.0f:"):format(P.rod_blocks,
			rod_mass))
		print(("  мод:          I_xx = %.6f"):format(rod_from_mod[1][1]))
		print(("  лаборатория:  I_xx = %.6f"):format(rod_reference[1][1]))
		print(("  однородный брус m*(L^2+s^2)/12 = %.6f"):format(solid_box))
		print(("  худшее расхождение по всем девяти элементам: %.3e")
			:format(rod_error))

		------------------------------------------------------------------
		-- 2. Машина: тензор, симметрия, свойства
		------------------------------------------------------------------
		local machine_parts = aircraft_parts {
			fuselage = P.fuselage, left = P.span, right = P.span,
		}

		local machine = build(machine_parts)
		local machine_points = as_points(machine_parts)
		local machine_centre = rigid.centre_of_mass(machine_points)
		local machine_reference = rigid.inertia_tensor(machine_points,
			machine_centre, 1)

		local machine_error = worst_difference(machine.inertia, machine_reference)

		local i_pitch = machine.inertia[1][1]
		local i_yaw = machine.inertia[2][2]
		local i_roll = machine.inertia[3][3]

		print()
		print(("Машина: %d деталей, игровая масса %.0f, поведение %s")
			:format(#machine_parts, machine.mass,
				machine.behaviour and machine.behaviour.name or "нет"))
		print(("  центр масс %s"):format(("(%.4f, %.4f, %.4f)")
			:format(machine.centre.x, machine.centre.y, machine.centre.z)))
		print(("  I тангаж %.2f, рыскание %.2f, крен %.2f (игровая масса·м^2)")
			:format(i_pitch, i_yaw, i_roll))
		print(("  по тангажу машина инертнее, чем по крену, в %.1f раза")
			:format(i_pitch / i_roll))
		print(("  расхождение с лабораторией: %.3e"):format(machine_error))

		-- Симметрия и неравенство треугольника
		local symmetry = 0

		for i = 1, 3 do
			for j = 1, 3 do
				symmetry = math.max(symmetry,
					math.abs(machine.inertia[i][j] - machine.inertia[j][i]))
			end
		end

		------------------------------------------------------------------
		-- 3. Тензор не зависит от того, куда игрок направил нос
		------------------------------------------------------------------
		-- Та же машина, повёрнутая на 90 градусов: нос вдоль +X. Детали
		-- переставлены так, чтобы в осях корпуса постройка была прежней.
		local turned_parts = {}

		for index, part in ipairs(machine_parts) do
			turned_parts[index] = {
				name = part.name,
				position = { x = part.position.z, y = part.position.y,
					z = -part.position.x },
			}
		end

		local turned = build(turned_parts, { x = 1, z = 0 })
		local turned_error = worst_difference(turned.inertia, machine.inertia)

		print()
		print(("Та же машина носом вдоль +X: расхождение тензора %.3e")
			:format(turned_error))
		print("  Крен — это вращение вокруг продольной оси конструкции, а не")
		print("  вокруг мировой Z, поэтому тензор считается в осях носа.")

		------------------------------------------------------------------
		-- 4. Обращение тензора
		------------------------------------------------------------------
		local inverse = machine.inertia_inverse
		local identity_error = 0

		for i = 1, 3 do
			for j = 1, 3 do
				local sum = 0

				for k = 1, 3 do
					sum = sum + machine.inertia[i][k] * inverse[k][j]
				end

				identity_error = math.max(identity_error,
					math.abs(sum - (i == j and 1 or 0)))
			end
		end

		print()
		print(("Обращение тензора: худшее отклонение I*I^-1 от единичной = %.3e")
			:format(identity_error))

		------------------------------------------------------------------
		-- 5. Уравнения Эйлера и законы сохранения
		------------------------------------------------------------------
		-- Несимметричная машина: центробежные моменты не нули, оси связаны.
		local skew_parts = aircraft_parts {
			fuselage = P.fuselage, left = P.span, right = 1, station = -2,
		}

		local skew = build(skew_parts)
		local skew_inertia = mat3.new(skew.inertia)
		local skew_inverse = mat3.inverse(skew_inertia)

		local function mod_acceleration(omega)
			local result = mod.call(loaded, loaded.angular_acceleration,
				skew.inertia, skew.inertia_inverse,
				{ x = omega.x, y = omega.y, z = omega.z },
				{ x = 0, y = 0, z = 0 })

			return vec3.new(result.x, result.y, result.z)
		end

		local function lab_acceleration(omega)
			return rigid.angular_acceleration(skew_inertia, skew_inverse, omega,
				vec3.zero)
		end

		local formula_error = 0

		for _, sample in ipairs({
			vec3.new(1.3, -0.7, 0.4), vec3.new(0, 2.0, -1.1),
			vec3.new(-0.2, 0.05, 3.0),
		}) do
			formula_error = math.max(formula_error,
				vec3.length(mod_acceleration(sample) - lab_acceleration(sample)))
		end

		-- Свободное вращение: |L| и энергия обязаны сохраняться
		local omega = vec3.new(0.05, 2.0, 0.05)
		local l0 = vec3.length(rigid.angular_momentum(skew_inertia, omega))
		local t0 = rigid.rotational_energy(skew_inertia, omega)
		local drift_l, drift_t = 0, 0

		do
			local steps = 20000
			local dt = 10 / steps
			local state = omega

			for step = 1, steps do
				state = integrate.rk4_first_order(state, mod_acceleration, dt,
					(step - 1) * dt)

				drift_l = math.max(drift_l,
					math.abs(vec3.length(rigid.angular_momentum(skew_inertia,
						state)) - l0) / l0)
				drift_t = math.max(drift_t,
					math.abs(rigid.rotational_energy(skew_inertia, state) - t0)
						/ t0)
			end
		end

		print()
		print("Уравнения Эйлера на перекошенной машине (крылья 3 и 1, вынесены назад):")
		print(("  расхождение формулы мода с лабораторией: %.3e"):format(formula_error))
		print(("  центробежный момент I_yz = %.4f — оси связаны")
			:format(skew.inertia[2][3]))
		print(("  за 10 с свободного вращения: дрейф |L| %.2e, энергии %.2e")
			:format(drift_l, drift_t))

		------------------------------------------------------------------
		-- 6. Точный шаг углового движения против независимого РК4
		------------------------------------------------------------------
		--- Независимое решение уравнения I*th'' = M + k*th + c*th'.
		local function reference_motion(inertia_axis, torque, stiffness, damping,
				angle, rate, duration)
			local final = integrate.simulate {
				method = "rk4",
				accel = function(x, v)
					return vec3.new(
						(torque + stiffness * x.x + damping * v.x) / inertia_axis,
						0, 0)
				end,
				x0 = vec3.new(angle, 0, 0),
				v0 = vec3.new(rate, 0, 0),
				dt = P.fine_dt,
				duration = duration,
			}

			return final.x.x, final.v.x
		end

		--- То же самое настоящей функцией мода, нарезкой по dt.
		local function mod_motion(inertia_axis, torque, stiffness, damping,
				angle, rate, duration, dt)
			local steps = math.floor(duration / dt + 0.5)
			local step_time = duration / steps

			mod.call(loaded, function()
				for _ = 1, steps do
					angle, rate = loaded.rotation_step(angle, rate, inertia_axis,
						torque, stiffness, damping, step_time)
				end
			end)

			return angle, rate
		end

		local REGIMES = {
			{
				name = "колебание (крылья позади)",
				inertia = 140, torque = 700, stiffness = -2700, damping = -320,
			},
			{
				name = "апериодический (крылья далеко позади)",
				inertia = 177, torque = 2000, stiffness = -7600, damping = -2350,
			},
			{
				name = "неустойчивый (крылья впереди)",
				inertia = 140, torque = -700, stiffness = 2700, damping = -320,
			},
			{
				name = "крен: жёсткости нет",
				inertia = 34, torque = 500, stiffness = 0, damping = -1870,
			},
			{
				name = "свободное вращение: ни жёсткости, ни демпфирования",
				inertia = 34, torque = 120, stiffness = 0, damping = 0,
			},
		}

		print()
		print("Точный шаг против независимого решения РК4 (шаг "
			.. ("%.4f"):format(P.fine_dt) .. " с):")
		print(text.row {
			{ "режим", 44 }, { "w_n*dt", 10 }, { "zeta", 8 },
			{ "расхождение", 14 },
		})

		local worst_regime = 0

		for _, regime in ipairs(REGIMES) do
			local reference_angle = reference_motion(regime.inertia, regime.torque,
				regime.stiffness, regime.damping, 0.3, -0.4, P.duration)

			local mod_angle = mod_motion(regime.inertia, regime.torque,
				regime.stiffness, regime.damping, 0.3, -0.4, P.duration,
				P.server_dt)

			local scale = math.max(math.abs(reference_angle), 1e-6)
			local error_value = math.abs(mod_angle - reference_angle) / scale

			worst_regime = math.max(worst_regime, error_value)

			local frequency = regime.stiffness < 0
				and math.sqrt(-regime.stiffness / regime.inertia) or 0
			local zeta = frequency > 0
				and -regime.damping
					/ (2 * math.sqrt(-regime.stiffness * regime.inertia)) or 0

			print(text.row {
				{ regime.name, 44 },
				{ ("%.2f"):format(frequency * P.server_dt), 10 },
				{ frequency > 0 and ("%.3f"):format(zeta) or "—", 8 },
				{ ("%.3e"):format(error_value), 14 },
			})
		end

		------------------------------------------------------------------
		-- 7. Независимость от частоты кадров и длинный кадр
		------------------------------------------------------------------
		local rates = { 10, 20, 30, 60, 100, 144, 240 }
		local regime = REGIMES[1]
		local low, high = math.huge, -math.huge

		print()
		print("Один и тот же интервал, нарезанный по-разному:")
		print(text.row { { "кадров/с", 12 }, { "угол через " .. P.duration .. " с", 24 } })

		for _, fps in ipairs(rates) do
			local angle = mod_motion(regime.inertia, regime.torque,
				regime.stiffness, regime.damping, 0.3, -0.4, P.duration, 1 / fps)

			low = math.min(low, angle)
			high = math.max(high, angle)

			print(text.row {
				{ tostring(fps), 12 }, { ("%.14f"):format(angle), 24 },
			})
		end

		-- Длинный кадр: явная схема здесь разошлась бы (эксперимент 17)
		local long_dt = P.duration
		local long_angle = mod_motion(regime.inertia, regime.torque,
			regime.stiffness, regime.damping, 0.3, -0.4, P.duration, long_dt)
		local exact_angle = reference_motion(regime.inertia, regime.torque,
			regime.stiffness, regime.damping, 0.3, -0.4, P.duration)

		local long_frequency = math.sqrt(-regime.stiffness / regime.inertia)

		print()
		print(("Весь интервал одним кадром: dt = %.2f с, w_n*dt = %.2f")
			:format(long_dt, long_frequency * long_dt))
		print(("  мод %.14f, независимое решение %.14f")
			:format(long_angle, exact_angle))
		print("  Явная схема при w_n*dt > 2 расходится (эксперимент 17); у")
		print("  замкнутого решения такого предела нет вовсе.")


		------------------------------------------------------------------
		-- 8. Инерция вращения настоящих построек
		------------------------------------------------------------------
		-- Полёт целиком проверяется отдельно (П5): там своя модель со срывом
		-- и планированием. Здесь важно другое — что инерция вращения зависит
		-- от постройки так, как должна.
		print()
		print("Инерция вращения разных построек:")
		print(text.row {
			{ "конструкция", 30 }, { "масса", 9 }, { "I тангаж", 11 },
			{ "I крен", 11 }, { "отношение", 11 },
		})

		local SHAPES = {
			{ "фюзеляж 5, крылья 1+1", { fuselage = 5, left = 1, right = 1 } },
			{ "фюзеляж 7, крылья 3+3", { fuselage = 7, left = 3, right = 3 } },
			{ "фюзеляж 11, крылья 5+5", { fuselage = 11, left = 5, right = 5 } },
			{ "фюзеляж 21, крылья 3+3", { fuselage = 21, left = 3, right = 3 } },
		}

		local growth = {}

		for _, shape in ipairs(SHAPES) do
			local rig = build(aircraft_parts(shape[2]))
			local axis = rig.inertia[1][1]

			growth[#growth + 1] = { mass = rig.mass, pitch = axis }

			print(text.row {
				{ shape[1], 30 },
				{ ("%.1f"):format(rig.mass), 9 },
				{ ("%.1f"):format(axis), 11 },
				{ ("%.1f"):format(rig.inertia[3][3]), 11 },
				{ ("%.2f"):format(axis / rig.inertia[3][3]), 11 },
			})
		end

		print()
		print("Момент инерции растёт быстрее массы: масса линейна по числу")
		print("деталей, а инерция — примерно как куб длины. Поэтому длинная")
		print("машина вязкая по тангажу, хотя весит ненамного больше.")

		-- Удлинение фюзеляжа втрое при том же крыле
		local short_body = growth[2]
		local long_body = growth[4]

		local mass_growth = long_body.mass / short_body.mass
		local inertia_growth = long_body.pitch / short_body.pitch

		------------------------------------------------------------------
		-- 12. Область внедрения
		------------------------------------------------------------------
		local leftovers = {}

		for _, pattern in ipairs({ "TILT_SMOOTHING", "TILT_PER_NODE" }) do
			if air_source:find(pattern, 1, true) then
				leftovers[#leftovers + 1] = pattern
			end
		end

		local uses_dynamics = air_source:find("rotation_step", 1, true) ~= nil
		local uses_inertia = air_source:find("rig.inertia", 1, true) ~= nil

		print()
		print("Область внедрения:")
		print(("  behaviours/air.lua решает угловое движение: %s")
			:format(uses_dynamics and "да" or "НЕТ"))
		print(("  использует тензор инерции конструкции: %s")
			:format(uses_inertia and "да" or "НЕТ"))
		print(("  подгонка угла наклона осталась: %s")
			:format(#leftovers == 0 and "нет"
				or table.concat(leftovers, ", ")))
		print()
		print("Очередь на следующие итерации: MAX_SPEED (4), LIFT_PER_WING и")
		print("PITCH_LIFT (5), TURN_SPEED и DRIFT_PER_NODE (6). Рыскание всё ещё")
		print("задаётся рулём напрямую, поэтому уравнения Эйлера используются в")
		print("двух компонентах из трёх.")

		------------------------------------------------------------------
		local suite_reason = "мод и лаборатория считают одну и ту же формулу; "
			.. "расхождение выше машинной точности означало бы, что формулы "
			.. "разные"

		suite:close("тензор инерции стержня совпадает с лабораторией",
			rod_error, 0, 1e-12, suite_reason)

		suite:close("цепочка блоков даёт ровно однородный брус m*(L^2+s^2)/12",
			rod_from_mod[1][1], solid_box, 1e-12,
			"цепочка соприкасающихся кубов И ЕСТЬ однородный брус, поэтому "
			.. "совпадение обязано быть точным; расхождение означало бы, что "
			.. "мод потерял собственный момент инерции блока")

		suite:close("тензор машины совпадает с лабораторией",
			machine_error, 0, 1e-12, suite_reason)

		suite:close("тензор симметричен",
			symmetry, 0, 1e-12,
			"симметрия следует прямо из определения; несимметричный тензор "
			.. "означал бы ошибку в коде")

		suite:is_true("выполняется неравенство треугольника для главных моментов",
			i_pitch + i_yaw >= i_roll and i_yaw + i_roll >= i_pitch
				and i_pitch + i_roll >= i_yaw,
			"фундаментальное свойство тензора инерции любого реального тела; "
			.. "его нарушение означало бы физически невозможную конструкцию")

		suite:close("тензор не зависит от того, куда направлен нос",
			turned_error, 0, 1e-12,
			"та же постройка, повёрнутая на 90 градусов вместе с носом: в осях "
			.. "корпуса это одно и то же тело, поэтому тензор обязан совпасть "
			.. "точно. Расхождение означало бы, что крен считается вокруг "
			.. "мировой оси, а не вокруг продольной оси конструкции")

		suite:close("обращение тензора даёт единичную матрицу",
			identity_error, 0, 1e-12,
			"I*I^-1 = E по определению обратной матрицы; остаётся только "
			.. "округление при делении на определитель")

		suite:close("уравнения Эйлера совпадают с лабораторией",
			formula_error, 0, 1e-12, suite_reason)

		suite:close("момент импульса сохраняется при свободном вращении",
			drift_l, 0, 1e-9,
			"|I*w| — точный интеграл уравнений Эйлера при нулевом моменте; "
			.. "остаётся ошибка РК4 за 20000 шагов")

		suite:close("энергия вращения сохраняется при свободном вращении",
			drift_t, 0, 1e-9,
			"второй точный интеграл; независимая проверка тех же уравнений")

		suite:close("шаг мода совпадает с независимым решением РК4 во всех режимах",
			worst_regime, 0, 1e-6,
			"мод решает уравнение замкнуто, РК4 — численно с шагом "
			.. ("%.4f"):format(P.fine_dt) .. " с. Расхождение — это ошибка РК4, "
			.. "порядка dt^4 на шаг, накопленная за "
			.. ("%.0f"):format(P.duration / P.fine_dt) .. " шагов")

		suite:close("результат не зависит от частоты кадров",
			high - low, 0, 1e-12,
			"замкнутое решение линейного уравнения складывает показатели "
			.. "экспонент, поэтому нарезка времени на результат не влияет — "
			.. "то же свойство, что проверено в П1 для сглаживания")

		suite:close("длинный кадр не ломает решение",
			long_angle, exact_angle, 1e-6,
			"весь интервал посчитан ОДНИМ кадром при w_n*dt = "
			.. ("%.1f"):format(long_frequency * long_dt) .. ", то есть далеко за "
			.. "пределом устойчивости явной схемы w_n*dt < 2 (эксперимент 17). "
			.. "Замкнутое решение точно при любом шаге")

		-- Шкала масс: та же задача в килограммах
		local MASS_TO_KG = 500 / 3

		local light = reference_motion(140, 700, -2700, -320, 0.3, -0.4,
			P.duration)
		local heavy = reference_motion(140 * MASS_TO_KG, 700 * MASS_TO_KG,
			-2700 * MASS_TO_KG, -320 * MASS_TO_KG, 0.3, -0.4, P.duration)

		suite:close("угловое движение не зависит от шкалы масс",
			heavy, light, 1e-12,
			"момент, момент инерции, жёсткость и демпфирование линейны по "
			.. "массе, поэтому общий множитель сокращается в угловом ускорении "
			.. "точно. Это и есть причина, по которой мод считает вращение "
			.. "прямо в игровых массах, не переводя их в килограммы")

		suite:is_true("момент инерции растёт быстрее массы",
			inertia_growth > mass_growth * 3,
			"втрое более длинный фюзеляж при том же крыле тяжелее в "
			.. ("%.2f"):format(mass_growth) .. " раза, а инертнее по тангажу в "
			.. ("%.2f"):format(inertia_growth) .. ". Масса линейна по числу "
			.. "деталей, а инерция растёт примерно как куб длины — именно "
			.. "поэтому длинная машина вязкая по тангажу")

		suite:is_true("массы деталей в проверке совпадают с parts/*.lua",
			#mass_mismatch == 0,
			"числа читаются из исходника мода: разойдись они, проверка "
			.. "считала бы не ту конструкцию, которая летает в игре")

		suite:is_true("поведение полёта решает угловое движение, а не подгоняет угол",
			uses_dynamics and uses_inertia and #leftovers == 0,
			"поиск по исходнику behaviours/air.lua: должны появиться "
			.. "rotation_step и rig.inertia и исчезнуть TILT_SMOOTHING с "
			.. "TILT_PER_NODE. Их возвращение означало бы откат итерации")

		return suite
	end,
}
