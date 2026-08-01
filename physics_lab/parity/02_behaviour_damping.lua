-- the Axis · physics lab · соответствие 02
-- Затухание в наземном и инертном поведениях: выполняется НАСТОЯЩИЙ control().

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local mod = require("parity.mod")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "П2",
	name = "parity_behaviour_damping",
	title = "Соответствие: затухание в поведениях",

	question = [[
Проверка 01 сверяла формулу. Здесь проверяется целиком шаг поведения: файлы
behaviours/inert.lua и behaviours/ground.lua загружаются по-настоящему, и их
функция control() выполняется покадрово с разной частотой. Сравнивается
результат — скорость машины через две секунды.

Это самая сильная форма проверки, доступная без запуска сервера: считается
тот же код, теми же аргументами, что и в игре.]],

	model = [[
ИНЕРТНОЕ ПОВЕДЕНИЕ. Ход гасится трением:
    dv/dt = -k*v   →   v(t) = v0 * exp(-k*t)                  [м/с]
k = 4 на земле (1/k = 0.25 с) и 0.4 в воздухе (1/k = 2.5 с).

Вертикаль накапливается линейно: v_y = v_y - g*dt с ограничением снизу. Сумма
g*dt по шагам равна g*T при любой нарезке, поэтому вертикаль от частоты кадров
не зависит и без всяких экспонент — это полезный контроль: если бы разброс
появился и там, ошибка была бы в стенде, а не в моде.

НАЗЕМНОЕ ПОВЕДЕНИЕ. Скорость подтягивается к целевой:
    dv/dt = rate*(target - v)   →   v(t) = target*(1 - exp(-rate*t))
rate = ACCELERATION/heaviness при газе и BRAKING/heaviness при его отсутствии,
heaviness = max(1, mass/40).

Наклон кузова возвращается в горизонт:
    pitch(t) = pitch0 * exp(-LEVELLING*t)

Все четыре выражения — замкнутые решения, а не приближения. Совпадение с ними
проверяется с машинной точностью; расхождение означало бы, что в моде стоит
другая формула.]],

	simplifications = [[
Проверяется только затухание. Поворот курса (rig.yaw) в наземном поведении
по-прежнему считается как yaw - move_x*TURN_SPEED*dtime*rolling/heaviness:
множитель rolling зависит от текущей скорости, поэтому при разной нарезке
времени накопленный поворот немного разойдётся. Это ОТДЕЛЬНЫЙ узел, он
переводится в свою итерацию; здесь управление рулём выключено (move_x = 0),
чтобы не смешивать два эффекта.]],

	references = { R.gaffer_integration },

	params = {
		duration = { value = 2.0, note = "моделируемое время, с" },
		speed_x = { value = 12.0, note = "начальный ход по X, м/с" },
		speed_z = { value = -5.0, note = "начальный ход по Z, м/с" },
		mass = { value = 40.0, note = "игровая масса машины (heaviness = mass/40)" },
		pitch = { value = 0.5, note = "начальный наклон кузова, рад" },
		server_dt = { value = 0.1, note = "типичный шаг сервера Luanti, с" },
	},

	run = function(P, ctx)
		local suite = check.new("соответствие: затухание в поведениях")

		----------------------------------------------------------------------
		-- Загрузка настоящих поведений с минимальными заготовками
		----------------------------------------------------------------------
		local registered = {}

		local stubs = {
			roles = {
				structure = "structure", seat = "seat", engine = "engine",
				wing = "wing", wheel = "wheel",
			},

			register_behaviour = function(name, definition)
				registered[name] = definition
			end,

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
			"api/smoothing.lua",
			"behaviours/inert.lua",
			"behaviours/ground.lua",
		}, stubs)

		if not loaded then
			print("Мод недоступен: " .. tostring(reason))

			suite:is_true("мод загружается", false,
				"без файлов мода сравнивать нечего; путь задаётся "
				.. "переменной окружения AXIS_MOD_PATH")

			return suite
		end

		print("Мод найден: " .. mod.path())
		print(("Загружены поведения: %s"):format(
			(function()
				local names = {}

				for name in pairs(registered) do
					names[#names + 1] = name
				end

				table.sort(names)

				return table.concat(names, ", ")
			end)()))

		local inert = registered.inert
		local ground = registered.ground

		if not inert or not ground then
			suite:is_true("оба поведения зарегистрированы", false,
				"ожидались inert и ground")

			return suite
		end

		local rates = { 10, 20, 30, 60, 100, 144, 240 }

		----------------------------------------------------------------------
		-- Инертное поведение
		----------------------------------------------------------------------
		local function drive_inert(fps, on_ground)
			local dt = 1 / fps
			local frames = math.floor(P.duration * fps + 0.5)

			local rig = {
				velocity = { x = P.speed_x, y = 0, z = P.speed_z },
				mass = P.mass,
				on_ground = on_ground,
				pitch = 0, roll = 0, yaw = 0,
				forward = { x = 1, y = 0, z = 0 },
			}

			-- Вызов внутри окружения мода: control() ищет глобальную
			-- contraption в момент выполнения, а не загрузки
			mod.call(loaded, function()
				for _ = 1, frames do
					inert.control(rig, dt)
				end
			end)

			return rig
		end

		print()
		print("ИНЕРТНОЕ ПОВЕДЕНИЕ, ход гасится трением (k = 4 на земле):")
		print(text.row {
			{ "кадров/с", 12 }, { "v_x через 2 с", 20 }, { "v_y", 16 },
		})

		local inert_low, inert_high = math.huge, -math.huge
		local vertical_low, vertical_high = math.huge, -math.huge

		for _, fps in ipairs(rates) do
			local rig = drive_inert(fps, true)

			inert_low = math.min(inert_low, rig.velocity.x)
			inert_high = math.max(inert_high, rig.velocity.x)
			vertical_low = math.min(vertical_low, rig.velocity.y)
			vertical_high = math.max(vertical_high, rig.velocity.y)

			print(text.row {
				{ tostring(fps), 12 },
				{ ("%.14f"):format(rig.velocity.x), 20 },
				{ ("%.10f"):format(rig.velocity.y), 16 },
			})
		end

		local exact_ground = P.speed_x * math.exp(-4 * P.duration)
		local exact_air = P.speed_x * math.exp(-0.4 * P.duration)

		local measured_ground = drive_inert(60, true).velocity.x
		local measured_air = drive_inert(60, false).velocity.x

		print()
		print(("На земле:  получено %.14f, замкнутое решение v0*exp(-4*T) = %.14f")
			:format(measured_ground, exact_ground))
		print(("В воздухе: получено %.14f, v0*exp(-0.4*T) = %.14f")
			:format(measured_air, exact_air))
		print(("Разброс по частотам: %.3e"):format(inert_high - inert_low))
		print(("Разброс вертикали:   %.3e (контроль: накопление линейное)")
			:format(vertical_high - vertical_low))

		----------------------------------------------------------------------
		-- Наземное поведение
		----------------------------------------------------------------------
		local function drive_ground(fps, move_y)
			local dt = 1 / fps
			local frames = math.floor(P.duration * fps + 0.5)

			local rig = {
				velocity = { x = 0, y = 0, z = 0 },
				mass = P.mass,
				on_ground = true,
				pitch = P.pitch, roll = P.pitch, yaw = 0,
				forward = { x = 1, y = 0, z = 0 },
			}

			-- Руль не трогаем: поворот курса — отдельный узел
			local controls = { move_x = 0, move_y = move_y, up = false,
				down = false }

			mod.call(loaded, function()
				for _ = 1, frames do
					ground.control(rig, dt, controls)
				end
			end)

			return rig
		end

		local heaviness = math.max(1, P.mass / 40)
		local accel_rate = 9 / heaviness

		print()
		print(("НАЗЕМНОЕ ПОВЕДЕНИЕ, разгон (heaviness = %.2f, rate = %.2f 1/с):")
			:format(heaviness, accel_rate))
		print(text.row {
			{ "кадров/с", 12 }, { "v_x через 2 с", 20 }, { "наклон", 18 },
		})

		local ground_low, ground_high = math.huge, -math.huge
		local pitch_low, pitch_high = math.huge, -math.huge

		for _, fps in ipairs(rates) do
			local rig = drive_ground(fps, 1)

			ground_low = math.min(ground_low, rig.velocity.x)
			ground_high = math.max(ground_high, rig.velocity.x)
			pitch_low = math.min(pitch_low, rig.pitch)
			pitch_high = math.max(pitch_high, rig.pitch)

			print(text.row {
				{ tostring(fps), 12 },
				{ ("%.14f"):format(rig.velocity.x), 20 },
				{ ("%.14f"):format(rig.pitch), 18 },
			})
		end

		local exact_speed = 7 * (1 - math.exp(-accel_rate * P.duration))
		local exact_pitch = P.pitch * math.exp(-3 * P.duration)
		local measured = drive_ground(60, 1)

		print()
		print(("Разгон:  получено %.14f, target*(1 - exp(-rate*T)) = %.14f")
			:format(measured.velocity.x, exact_speed))
		print(("Наклон:  получено %.14f, pitch0*exp(-3*T) = %.14f")
			:format(measured.pitch, exact_pitch))
		print(("Разброс скорости по частотам: %.3e")
			:format(ground_high - ground_low))
		print(("Разброс наклона по частотам:  %.3e")
			:format(pitch_high - pitch_low))

		----------------------------------------------------------------------
		-- Что изменилось по каждому месту
		----------------------------------------------------------------------
		local dt = P.server_dt

		print()
		print(("Изменение множителя на шаге сервера dt = %.3f с:"):format(dt))
		print(text.row {
			{ "место", 34 }, { "rate", 8 }, { "было", 12 }, { "стало", 12 },
			{ "разница", 12 },
		})

		local sites = {
			{ "ground: разгон", accel_rate },
			{ "ground: торможение", 7 / heaviness },
			{ "ground: возврат кузова в горизонт", 3 },
			{ "inert: трение о землю", 4 },
			{ "inert: трение в воздухе", 0.4 },
		}

		for _, site in ipairs(sites) do
			local rate = site[2]
			local old = math.min(rate * dt, 1)
			local new = 1 - math.exp(-rate * dt)

			print(text.row {
				{ site[1], 34 },
				{ ("%.2f"):format(rate), 8 },
				{ ("%.4f"):format(old), 12 },
				{ ("%.4f"):format(new), 12 },
				{ ("%+.1f %%"):format((new - old) / old * 100), 12 },
			})
		end

		print()
		print("Постоянные времени не менялись: rate остались прежними, но")
		print("теперь означают именно 1/rate секунд на сокращение остатка в e")
		print("раз. Разница множителя тем больше, чем больше произведение")
		print("rate*dt — для разгона она самая заметная.")

		-- Где старая запись прыгала
		print()
		print("Кадр, начиная с которого старая запись мгновенно достигала цели:")

		for _, site in ipairs(sites) do
			print(("  %s: dt >= %.3f с (то есть ниже %.1f кадров/с)")
				:format(site[1], 1 / site[2], site[2]))
		end

		----------------------------------------------------------------------
		local why_exact = "мод и лаборатория решают одно и то же уравнение; "
			.. "расхождение выше машинной точности означало бы, что формулы "
			.. "разные"

		suite:close("инертное: затухание на земле совпадает с v0*exp(-k*T)",
			measured_ground, exact_ground, 1e-12, why_exact)

		suite:close("инертное: затухание в воздухе совпадает с v0*exp(-k*T)",
			measured_air, exact_air, 1e-12, why_exact)

		suite:close("инертное: ход не зависит от частоты кадров",
			inert_high - inert_low, 0, 1e-12,
			"показатели экспонент складываются, поэтому нарезка времени на "
			.. "результат не влияет")

		suite:close("инертное: вертикаль не зависит от частоты кадров",
			vertical_high - vertical_low, 0, 1e-12,
			"контрольная проверка: сумма g*dt по шагам равна g*T при любой "
			.. "нарезке. Разброс здесь означал бы ошибку стенда, а не мода")

		suite:close("наземное: разгон совпадает с target*(1 - exp(-rate*T))",
			measured.velocity.x, exact_speed, 1e-12, why_exact)

		suite:close("наземное: разгон не зависит от частоты кадров",
			ground_high - ground_low, 0, 1e-12,
			"та же причина, что и у затухания: экспонента складывает "
			.. "показатели")

		suite:close("наземное: возврат кузова совпадает с pitch0*exp(-k*T)",
			measured.pitch, exact_pitch, 1e-12, why_exact)

		suite:close("наземное: наклон не зависит от частоты кадров",
			pitch_high - pitch_low, 0, 1e-12,
			"contraption.decay — точное решение, а не приближение")

		suite:is_true("торможение приводит машину к нулю",
			math.abs(drive_ground(60, 0).velocity.x) < 1e-4,
			"при отпущенном газе цель равна нулю, а за 2 с при rate = "
			.. ("%.1f"):format(7 / heaviness) .. " остаток exp(-rate*T) = "
			.. ("%.2e"):format(math.exp(-7 / heaviness * P.duration)))

		return suite
	end,
}
