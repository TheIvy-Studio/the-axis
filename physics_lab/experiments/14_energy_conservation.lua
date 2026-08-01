-- the Axis · physics lab · эксперимент 14
-- Сохранение энергии: чем симплектические схемы отличаются от остальных.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "14",
	name = "energy_conservation",
	title = "Сохранение энергии и симплектические схемы",

	question = [[
Почему одни схемы интегрирования «накачивают» систему энергией, другие её
теряют, а третьи держат ровно? И почему это важнее порядка точности, когда
симуляция работает часами?]],

	model = [[
Гармонический осциллятор — эталон, у которого всё считается точно:
    m*d2x/dt2 = -k*x,   w = sqrt(k/m)                         [рад/с]
    E = 0.5*m*v^2 + 0.5*k*x^2 = const                         [Дж]

Для явного Эйлера энергия растёт по ТОЧНОМУ закону. Подставив шаг схемы в
выражение энергии, получаем

    E[n+1] = E[n] * (1 + w^2*dt^2)

то есть за N шагов энергия умножается на (1 + w^2*dt^2)^N. Это не «плохая
точность», а качественно неверное поведение: система раскачивается при любом
сколь угодно малом шаге.

Полунеявный (симплектический) Эйлер энергию НЕ сохраняет, но сохраняет
близкую величину — модифицированный гамильтониан [hairer_geometric]:

    H~ = 0.5*v^2 + 0.5*w^2*x^2 - (w^2*dt/2)*x*v               [Дж/кг]

Эта величина сохраняется ТОЧНО (проверяется прямой подстановкой шага схемы).
Именно поэтому обычная энергия у симплектической схемы колеблется в узкой
полосе шириной порядка dt и не уходит: она отличается от сохраняющейся
величины на слагаемое, само по себе ограниченное.

РК4 не симплектичен: у него энергия медленно уползает, обычно вниз. На
коротких отрезках это незаметно (ошибка порядка dt^4), на длинных — заметно.

Практический вывод для игры: для долгоживущей симуляции важнее не порядок
точности, а тип схемы.]],

	simplifications = [[
Осциллятор без затухания и без внешних сил. Это сознательно: любое
затухание маскирует численный рост энергии, и отличить одно от другого
станет невозможно.]],

	references = { R.hairer_geometric, R.hairer_odes, R.verlet_1967 },

	params = {
		omega = { value = 2.0, note = "собственная частота, рад/с" },
		amplitude = { value = 1.0, note = "начальная амплитуда, м" },
		dt = { value = 0.02, note = "шаг интегрирования, с" },
		periods = { value = 200, note = "сколько периодов моделировать" },
	},

	run = function(P, ctx)
		local w = P.omega
		local period = 2 * math.pi / w
		local duration = period * P.periods

		local function energy(x, v)
			return 0.5 * v.x * v.x + 0.5 * w * w * x.x * x.x
		end

		local accel = function(x) return vec3.new(-w * w * x.x, 0, 0) end

		local x0 = vec3.new(P.amplitude, 0, 0)
		local v0 = vec3.zero
		local e0 = energy(x0, v0)

		print(("Осциллятор: w = %.4f рад/с, период %.4f с, %d периодов = %.1f с")
			:format(w, period, P.periods, duration))
		print(("Шаг dt = %.4f с, то есть %.1f шагов на период")
			:format(P.dt, period / P.dt))
		print(("Начальная энергия (на единицу массы) E0 = %.6f Дж/кг"):format(e0))

		----------------------------------------------------------------------
		local series = {}
		local results = {}
		local marks = { euler = "e", symplectic = "s", verlet = "v", rk4 = "r" }

		-- Фактический шаг. Он чуть отличается от запрошенного: длительность
		-- делится на целое число шагов. Разница в восьмом знаке, но в
		-- аналитических формулах ниже стоит именно ФАКТИЧЕСКИЙ шаг —
		-- иначе эталон посчитан для другой задачи, и расхождение примут
		-- за ошибку схемы.
		local effective_dt

		for _, method in ipairs(integrate.methods) do
			local points = {}
			local min_e, max_e = math.huge, -math.huge

			local final, steps, _, step_dt = integrate.simulate {
				method = method.key,
				accel = accel,
				x0 = x0,
				v0 = v0,
				dt = P.dt,
				duration = duration,
				sample = function(t, x, v)
					local e = energy(x, v)

					min_e = math.min(min_e, e)
					max_e = math.max(max_e, e)

					if #points < 4000 then
						points[#points + 1] = { t, e / e0 }
					end
				end,
			}

			effective_dt = step_dt

			results[method.key] = {
				method = method,
				final = energy(final.x, final.v) / e0,
				min = min_e / e0,
				max = max_e / e0,
				steps = steps,
			}

			series[#series + 1] = {
				label = method.label,
				mark = marks[method.key],
				points = points,
			}
		end

		print()
		print(text.row {
			{ "схема", 24 }, { "E/E0 в конце", 16 }, { "минимум", 14 },
			{ "максимум", 14 }, { "размах", 12 },
		})

		for _, method in ipairs(integrate.methods) do
			local r = results[method.key]

			print(text.row {
				{ method.label, 24 },
				{ ("%.6g"):format(r.final), 16 },
				{ ("%.6f"):format(r.min), 14 },
				{ ("%.6g"):format(r.max), 14 },
				{ ("%.4g"):format(r.max - r.min), 12 },
			})
		end

		----------------------------------------------------------------------
		-- Точный закон роста энергии у явного Эйлера
		----------------------------------------------------------------------
		local steps_total = results.euler.steps
		local growth = (1 + w * w * effective_dt * effective_dt) ^ steps_total

		print()
		print(("Явный Эйлер: предсказанный рост (1 + w^2*dt^2)^N = %.6g")
			:format(growth))
		print(("             измеренный рост                    = %.6g")
			:format(results.euler.final))

		----------------------------------------------------------------------
		-- Модифицированный гамильтониан полунеявной схемы
		----------------------------------------------------------------------
		local function modified(x, v)
			return 0.5 * v.x * v.x + 0.5 * w * w * x.x * x.x
				- 0.5 * w * w * effective_dt * x.x * v.x
		end

		local h0 = modified(x0, v0)
		local worst_modified = 0
		local worst_plain = 0

		integrate.simulate {
			method = "symplectic",
			accel = accel,
			x0 = x0,
			v0 = v0,
			dt = P.dt,
			duration = duration,
			sample = function(_, x, v)
				worst_modified = math.max(worst_modified,
					math.abs(modified(x, v) - h0) / h0)
				worst_plain = math.max(worst_plain,
					math.abs(energy(x, v) - e0) / e0)
			end,
		}

		print()
		print(("Полунеявный Эйлер за %d шагов:"):format(steps_total))
		print(("  обычная энергия гуляет на %.4f %%"):format(worst_plain * 100))
		print(("  модифицированный гамильтониан H~ дрейфует на %.3e")
			:format(worst_modified))
		print("  Первое — колебание в фиксированной полосе, второе — почти")
		print("  машинный ноль. Именно это и означает «схема симплектическая».")

		----------------------------------------------------------------------
		-- Зависимость от шага
		----------------------------------------------------------------------
		print()
		print("Как размах энергии зависит от шага (полунеявный Эйлер):")
		print(text.row {
			{ "dt, с", 12 }, { "шагов на период", 18 }, { "размах E, %", 14 },
		})

		local band_curve = {}

		for _, dt in ipairs({ 0.16, 0.08, 0.04, 0.02, 0.01, 0.005 }) do
			local min_e, max_e = math.huge, -math.huge

			integrate.simulate {
				method = "symplectic",
				accel = accel,
				x0 = x0,
				v0 = v0,
				dt = dt,
				duration = period * 20,
				sample = function(_, x, v)
					local e = energy(x, v)
					min_e = math.min(min_e, e)
					max_e = math.max(max_e, e)
				end,
			}

			local band = (max_e - min_e) / e0

			band_curve[#band_curve + 1] = { dt, band }

			print(text.row {
				{ ("%.4f"):format(dt), 12 },
				{ ("%.1f"):format(period / dt), 18 },
				{ ("%.4f"):format(band * 100), 14 },
			})
		end

		print()
		print("Полоса сужается пропорционально шагу — первый порядок, как и")
		print("положено. Но она НЕ растёт со временем, и это главное.")

		ctx.show(series, {
			title = "Энергия относительно начальной",
			xlabel = "время, с",
			ylabel = "E/E0",
		})

		ctx.save(series, {
			title = "Поведение энергии у разных схем",
			xlabel = "время, с",
			ylabel = "E/E0",
		}, {
			headers = { "t", "euler", "symplectic", "verlet", "rk4" },
			rows = (function()
				local rows = {}
				local count = math.min(#series[1].points, #series[4].points)

				for index = 1, count do
					rows[index] = {
						series[1].points[index][1],
						series[1].points[index][2],
						series[2].points[index][2],
						series[3].points[index][2],
						series[4].points[index][2],
					}
				end

				return rows
			end)(),
		})

		----------------------------------------------------------------------
		local suite = check.new("сохранение энергии")

		suite:close("рост энергии у явного Эйлера равен (1 + w^2*dt^2)^N",
			results.euler.final, growth, 1e-9,
			"точный закон, выведенный подстановкой шага схемы в выражение "
			.. "энергии. Формула считается по ФАКТИЧЕСКОМУ шагу: при росте "
			.. "в 10^21 раз ошибка в восьмом знаке шага дала бы расхождение "
			.. "в сотые доли процента")

		suite:close("модифицированный гамильтониан сохраняется точно",
			worst_modified, 0, 1e-12,
			"H~ — точный инвариант полунеявной схемы для линейного "
			.. "осциллятора, проверяется прямой подстановкой. Это и есть "
			.. "определение симплектичности в действии")

		suite:is_true("у симплектической схемы энергия ограничена",
			results.symplectic.max - results.symplectic.min < 0.05
				and math.abs(results.symplectic.final - 1) < 0.05,
			"за " .. tostring(P.periods) .. " периодов энергия не ушла: она "
			.. "колеблется в полосе, ширина которой задаётся шагом, а не "
			.. "временем")

		suite:is_true("у Верле энергия тоже ограничена и полоса уже",
			results.verlet.max - results.verlet.min
				< results.symplectic.max - results.symplectic.min,
			"Верле тоже симплектичен, но второго порядка, поэтому полоса "
			.. "порядка dt^2, а не dt")

		suite:is_true("у явного Эйлера энергия растёт неограниченно",
			results.euler.final > 10,
			"качественно неверное поведение: схема добавляет энергию каждый "
			.. "шаг при ЛЮБОМ dt > 0")

		suite:is_true("у РК4 энергия почти не меняется, но не сохраняется точно",
			math.abs(results.rk4.final - 1) < 1e-3,
			"схема не симплектична, дрейф есть, но при 4-м порядке он мал")

		suite:close("полоса энергии линейна по шагу",
			band_curve[1][2] / band_curve[2][2], 2, 0.05,
			"первый порядок схемы: вдвое меньший шаг даёт вдвое более узкую "
			.. "полосу. Допуск 5 % — при крупном шаге начинает сказываться "
			.. "нелинейность")

		return suite
	end,
}
