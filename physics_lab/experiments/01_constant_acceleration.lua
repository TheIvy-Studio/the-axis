-- the Axis · physics lab · эксперимент 01
-- Равноускоренное движение.

-- Запуск в одиночку: путь к модулям лаборатории от расположения этого файла.
package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "01",
	name = "constant_acceleration",
	title = "Равноускоренное движение",

	question = [[
Правильно ли реализованы интеграторы? Постоянное ускорение — единственный
случай, где ответ известен точно и в замкнутом виде, поэтому проверять их
надо здесь, до всякой аэродинамики. Если схема врёт уже тут, дальше можно
не смотреть.]],

	model = [[
    dv/dt = a = const                                        [м/с^2]
    v(t)  = v0 + a*t                                         [м/с]
    x(t)  = x0 + v0*t + a*t^2/2                              [м]

Это не приближение, а точное решение. Кинематика равноускоренного движения,
любой курс механики.

Более того, ошибка каждой схемы тоже считается точно. Для явного Эйлера
положение обновляется по СТАРОЙ скорости:

    x_N = x0 + sum(v_n * dt), n = 0..N-1
        = x0 + v0*T + a*dt^2 * N*(N-1)/2
        = x0 + v0*T + a*T^2/2 - a*T*dt/2

то есть он недобирает ровно a*T*dt/2. Полунеявный берёт НОВУЮ скорость и
ровно на столько же перебирает. Верле и РК4 воспроизводят параболу точно:
у первого в схеме есть член a*dt^2/2, второй точен для многочленов до
четвёртой степени включительно.

Ожидаемые ошибки известны заранее с точностью до машинного нуля — значит
это не «похоже на правду», а настоящая проверка.]],

	simplifications = [[
Никаких. Это эталонная задача.]],

	references = { R.hairer_odes },

	params = {
		acceleration = { value = 3.0, note = "ускорение, м/с^2" },
		v0 = { value = 5.0, note = "начальная скорость, м/с" },
		x0 = { value = 0.0, note = "начальное положение, м" },
		duration = { value = 10.0, note = "длительность, с" },
		dt = { value = 0.01, note = "шаг интегрирования, с" },
	},

	run = function(P, ctx)
		local a = P.acceleration
		local T = P.duration

		local function exact_velocity(t) return P.v0 + a * t end
		local function exact_position(t)
			return P.x0 + P.v0 * t + 0.5 * a * t * t
		end

		local accel = function() return vec3.new(a, 0, 0) end

		local series = {
			{
				label = "точное решение",
				mark = "-",
				points = (function()
					local points = {}

					for step = 0, 100 do
						local t = T * step / 100
						points[#points + 1] = { t, exact_position(t) }
					end

					return points
				end)(),
			},
		}

		local results = {}
		local marks = { euler = "e", symplectic = "s", verlet = "v", rk4 = "r" }

		for _, method in ipairs(integrate.methods) do
			local points = {}

			local final = integrate.simulate {
				method = method.key,
				accel = accel,
				x0 = vec3.new(P.x0, 0, 0),
				v0 = vec3.new(P.v0, 0, 0),
				dt = P.dt,
				duration = T,
				sample = function(t, x)
					points[#points + 1] = { t, x.x }
				end,
			}

			results[method.key] = {
				method = method,
				x = final.x.x,
				v = final.v.x,
			}

			series[#series + 1] = {
				label = method.label,
				mark = marks[method.key],
				points = points,
			}
		end

		local expected_x = exact_position(T)
		local expected_v = exact_velocity(T)

		print(("Точное решение при t = %.4g с:  x = %.10f м,  v = %.10f м/с")
			:format(T, expected_x, expected_v))
		print()
		print(text.row {
			{ "схема", 24 }, { "x, м", 18 }, { "ошибка x, м", 16 },
			{ "ошибка v, м/с", 14 },
		})

		for _, method in ipairs(integrate.methods) do
			local result = results[method.key]

			print(text.row {
				{ method.label, 24 },
				{ ("%.8f"):format(result.x), 18 },
				{ ("%.3e"):format(result.x - expected_x), 16 },
				{ ("%.3e"):format(result.v - expected_v), 14 },
			})
		end

		-- Предсказанное аналитически смещение схем первого порядка
		local predicted_bias = 0.5 * a * T * P.dt

		print()
		print(("Аналитически предсказанный сдвиг схем 1-го порядка: "
			.. "a*T*dt/2 = %.6f м"):format(predicted_bias))

		ctx.show(series, {
			title = "Положение x(t), равноускоренное движение",
			xlabel = "время, с",
			ylabel = "x, м",
		})

		ctx.save(series, {
			title = "Равноускоренное движение: x(t)",
			xlabel = "время, с",
			ylabel = "положение, м",
		}, {
			headers = { "t", "exact", "euler", "symplectic", "verlet", "rk4" },
			rows = (function()
				local rows = {}
				local count = #series[2].points

				for index = 1, count do
					local t = series[2].points[index][1]

					rows[#rows + 1] = {
						t, exact_position(t),
						series[2].points[index][2],
						series[3].points[index][2],
						series[4].points[index][2],
						series[5].points[index][2],
					}
				end

				return rows
			end)(),
		})

		local suite = check.new("равноускоренное движение")

		-- Скорость: линейна по времени, поэтому точна во всех схемах
		local velocity_tolerance = 1e-12
		local velocity_why = "скорость линейна по t, все четыре схемы "
			.. "воспроизводят её точно; допуск — накопление ошибки "
			.. "округления за " .. tostring(math.floor(T / P.dt)) .. " шагов"

		for _, method in ipairs(integrate.methods) do
			suite:close("скорость: " .. method.label,
				results[method.key].v, expected_v,
				velocity_tolerance, velocity_why)
		end

		-- Положение: отклонения предсказаны аналитически
		suite:close("явный Эйлер отстаёт ровно на a*T*dt/2",
			results.euler.x - expected_x, -predicted_bias, 1e-9,
			"тождество, выведенное суммированием ряда; расхождение возможно "
			.. "только за счёт двоичного округления")

		suite:close("полунеявный Эйлер опережает ровно на a*T*dt/2",
			results.symplectic.x - expected_x, predicted_bias, 1e-9,
			"то же тождество с обратным знаком: положение берёт новую скорость")

		suite:close("Верле точен на параболе",
			results.verlet.x, expected_x, 1e-12,
			"в схеме явно присутствует член a*dt^2/2, поэтому парабола "
			.. "воспроизводится без ошибки усечения")

		suite:close("РК4 точен на параболе",
			results.rk4.x, expected_x, 1e-12,
			"метод 4-го порядка точен для многочленов степени до 4")

		return suite
	end,
}
