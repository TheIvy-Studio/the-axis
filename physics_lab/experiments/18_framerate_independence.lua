-- the Axis · physics lab · эксперимент 18
-- Независимость от частоты кадров.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local integrate = require("lab.integrate")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "18",
	name = "framerate_independence",
	title = "Независимость от частоты кадров",

	question = [[
Игрок с 30 кадрами в секунду и игрок со 144 должны видеть ОДИНАКОВУЮ физику.
Какие способы это обеспечивают, а какие только выглядят правильными?

Этот эксперимент проверяет в том числе код, который сейчас работает в моде.]],

	model = [[
Затухание к цели — самая частая операция в игровой физике. Встречаются четыре
записи, и различаются они принципиально.

  A. v = v * d                          множитель на кадр, без dt
     Полностью зависит от частоты: за секунду при 30 кадрах множитель d^30,
     при 144 — d^144. Это не приближение, а просто разные задачи.

  B. v = v * (1 - k*dt)                 линейное приближение
     Это явный Эйлер. Согласуется с точным решением до O(dt), но при
     dt > 1/k множитель становится ОТРИЦАТЕЛЬНЫМ и скорость разворачивается
     (эксперимент 17).

  C. v = v * exp(-k*dt)                 точное решение
     Так как exp(-k*dt1)*exp(-k*dt2) = exp(-k*(dt1+dt2)), результат зависит
     ТОЛЬКО от суммарного времени, а не от того, как оно нарезано на кадры.
     Это и есть строгая независимость от частоты кадров.

  D. x = x + (target - x) * min(rate*dt, 1)
     Именно так написана функция approach() в behaviours/air.lua. Это
     вариант B, записанный для сближения с целью, плюс ограничение сверху.
     Ограничение спасает от разворота, но ценой: при rate*dt >= 1 значение
     ПРЫГАЕТ в цель мгновенно. Правильная форма:

        x = x + (target - x) * (1 - exp(-rate*dt))

Отдельный приём — фиксированный шаг физики с накопителем
[gaffer_integration]: кадр может быть любым, физика всегда считается одним и
тем же dt, остаток копится. Тогда траектория воспроизводится независимо от
того, как рвано идут кадры.]],

	simplifications = [[
Кадры моделируются заданными длительностями, без учёта того, что реальный
кадр приходит с джиттером и иногда пропадает совсем. Последний случай
разобран отдельно: накопителю задаётся ограничение на число шагов за кадр,
иначе после долгой заминки симуляция пытается догнать всё сразу и подвисает
ещё сильнее — «спираль смерти».]],

	references = { R.gaffer_integration, R.hairer_odes },

	params = {
		decay_rate = { value = 3.0, note = "коэффициент затухания k, 1/с" },
		duration = { value = 2.0, note = "моделируемое время, с" },
		target = { value = 1.0, note = "цель для сближения" },
		start = { value = 0.0, note = "начальное значение" },
		approach_rate = { value = 3.0, note = "скорость сближения (как TILT_SMOOTHING в моде)" },
		fixed_dt = { value = 1 / 120, note = "шаг физики при фиксированном шаге, с" },
	},

	run = function(P, ctx)
		local k = P.decay_rate
		local rates = { 10, 20, 30, 60, 100, 144, 240 }

		----------------------------------------------------------------------
		-- Четыре способа затухания
		----------------------------------------------------------------------
		print(("Затухание скорости с k = %.2f 1/с за %.2f с."):format(k, P.duration))
		print(("Точный ответ: exp(-k*T) = %.10f"):format(math.exp(-k * P.duration)))
		print()
		print(text.row {
			{ "кадров/с", 12 }, { "A: без dt", 16 }, { "B: 1-k*dt", 16 },
			{ "C: exp(-k*dt)", 18 },
		})

		local exact = math.exp(-k * P.duration)

		local spread = { a = { math.huge, -math.huge }, b = { math.huge, -math.huge },
			c = { math.huge, -math.huge } }

		local function track(key, value)
			spread[key][1] = math.min(spread[key][1], value)
			spread[key][2] = math.max(spread[key][2], value)
		end

		-- Множитель варианта A подобран так, чтобы при 60 кадрах он совпадал
		-- с правильным ответом. Это типичная ситуация: коэффициент подобрали
		-- на своей машине, и на любой другой он означает другую физику.
		local per_frame = math.exp(-k / 60)

		for _, fps in ipairs(rates) do
			local dt = 1 / fps
			local frames = math.floor(P.duration * fps + 0.5)

			local a, b, c = 1.0, 1.0, 1.0

			for _ = 1, frames do
				a = a * per_frame
				b = b * (1 - k * dt)
				c = c * math.exp(-k * dt)
			end

			track("a", a)
			track("b", b)
			track("c", c)

			print(text.row {
				{ tostring(fps), 12 },
				{ ("%.10f"):format(a), 16 },
				{ ("%.10f"):format(b), 16 },
				{ ("%.10f"):format(c), 18 },
			})
		end

		print()
		print(("Разброс по частотам:  A = %.3e,  B = %.3e,  C = %.3e")
			:format(spread.a[2] - spread.a[1], spread.b[2] - spread.b[1],
				spread.c[2] - spread.c[1]))
		print("Вариант C не просто точнее — он даёт БУКВАЛЬНО одно и то же")
		print("число при любой частоте, потому что exp складывает показатели.")

		----------------------------------------------------------------------
		-- Функция approach() из мода
		----------------------------------------------------------------------
		print()
		print("Функция approach() из behaviours/air.lua против правильной формы:")
		print()
		print(text.row {
			{ "кадров/с", 12 }, { "approach (мод)", 18 },
			{ "1 - exp(-rate*dt)", 20 }, { "разница", 14 },
		})

		local rate = P.approach_rate

		local function approach_mod(current, target, dt)
			-- Дословно как в моде
			return current + (target - current) * math.min(rate * dt, 1)
		end

		local function approach_exact(current, target, dt)
			return current + (target - current) * (1 - math.exp(-rate * dt))
		end

		local mod_spread = { math.huge, -math.huge }
		local exact_spread = { math.huge, -math.huge }
		local mod_values = {}

		for _, fps in ipairs(rates) do
			local dt = 1 / fps
			local frames = math.floor(P.duration * fps + 0.5)

			local a, b = P.start, P.start

			for _ = 1, frames do
				a = approach_mod(a, P.target, dt)
				b = approach_exact(b, P.target, dt)
			end

			mod_spread[1] = math.min(mod_spread[1], a)
			mod_spread[2] = math.max(mod_spread[2], a)
			exact_spread[1] = math.min(exact_spread[1], b)
			exact_spread[2] = math.max(exact_spread[2], b)

			mod_values[fps] = a

			print(text.row {
				{ tostring(fps), 12 },
				{ ("%.10f"):format(a), 18 },
				{ ("%.10f"):format(b), 20 },
				{ ("%.3e"):format(a - b), 14 },
			})
		end

		print()
		print(("Разброс approach() по частотам: %.4e")
			:format(mod_spread[2] - mod_spread[1]))
		print(("Разброс правильной формы:       %.4e")
			:format(exact_spread[2] - exact_spread[1]))

		-- Обрыв на ограничении
		local clamp_dt = 1 / rate
		local snapped = approach_mod(P.start, P.target, clamp_dt * 1.01)

		print()
		print(("При dt >= 1/rate = %.4f с (то есть ниже %.1f кадров/с при "
			.. "rate = %.1f) ограничение срабатывает"):format(clamp_dt,
			rate, rate))
		print(("и значение прыгает в цель за один кадр: %.6f вместо %.6f.")
			:format(snapped, approach_exact(P.start, P.target, clamp_dt * 1.01)))
		print("На просевшем кадре наклон машины скачком встаёт в конечное")
		print("положение — визуально это рывок.")

		----------------------------------------------------------------------
		-- Фиксированный шаг с накопителем
		----------------------------------------------------------------------
		print()
		print("Фиксированный шаг физики при рваных кадрах:")

		local w = 4.0
		local accel = function(x) return vec3.new(-w * w * x.x, 0, 0) end

		-- Эталон: ровные кадры, тот же фиксированный шаг
		local reference = integrate.simulate {
			method = "symplectic",
			accel = accel,
			x0 = vec3.new(1, 0, 0),
			v0 = vec3.zero,
			dt = P.fixed_dt,
			duration = P.duration,
		}

		-- Рваная последовательность кадров. Числа заданы явно, а не
		-- случайно: эксперимент обязан воспроизводиться дословно.
		local jitter = { 0.004, 0.05, 0.011, 0.008, 0.13, 0.006, 0.017, 0.009,
			0.021, 0.007, 0.062, 0.005 }

		local stepper = integrate.make_fixed_stepper {
			method = "symplectic",
			accel = accel,
			x0 = vec3.new(1, 0, 0),
			v0 = vec3.zero,
			fixed_dt = P.fixed_dt,
			max_steps = 64,
		}

		local elapsed = 0
		local index = 1
		local total_steps = 0

		-- Кадры подаются, пока сумма их длительностей не даст ровно
		-- P.duration. Последний кадр укорачивается: иначе накопитель
		-- проглотит лишний шаг, и сравнивать будет нечего — эталон и опыт
		-- окажутся в разные моменты модельного времени.
		while elapsed < P.duration - 1e-12 do
			local frame = math.min(jitter[index], P.duration - elapsed)

			index = index % #jitter + 1
			elapsed = elapsed + frame

			local _, performed = stepper.advance(frame)

			total_steps = total_steps + performed
		end

		local jittered = stepper.state()

		print(("  эталон (ровные кадры): x = %.12f, v = %.12f")
			:format(reference.x.x, reference.v.x))
		print(("  рваные кадры:          x = %.12f, v = %.12f")
			:format(jittered.x.x, jittered.v.x))
		print(("  сделано шагов: %d, модельного времени %.6f с из %.6f")
			:format(total_steps, stepper.time(), P.duration))

		----------------------------------------------------------------------
		-- Графики
		----------------------------------------------------------------------
		local mod_curve, exact_curve = {}, {}

		for _, fps in ipairs(rates) do
			local dt = 1 / fps
			local frames = math.floor(P.duration * fps + 0.5)
			local a, b = P.start, P.start

			for _ = 1, frames do
				a = approach_mod(a, P.target, dt)
				b = approach_exact(b, P.target, dt)
			end

			mod_curve[#mod_curve + 1] = { fps, a }
			exact_curve[#exact_curve + 1] = { fps, b }
		end

		ctx.show({
			{ label = "approach() из мода", mark = "m", points = mod_curve },
			{ label = "1 - exp(-rate*dt)", mark = "e", points = exact_curve },
		}, {
			title = "Результат в зависимости от частоты кадров",
			xlabel = "кадров в секунду",
			ylabel = "значение через " .. tostring(P.duration) .. " с",
			height = 15,
		})

		ctx.save({
			{ label = "approach() из мода", points = mod_curve },
			{ label = "правильная форма", points = exact_curve, dashed = true },
		}, {
			title = "Зависимость от частоты кадров",
			xlabel = "кадров в секунду",
			ylabel = "значение",
		}, {
			headers = { "fps", "mod_approach", "exact" },
			rows = (function()
				local rows = {}

				for i, point in ipairs(mod_curve) do
					rows[i] = { point[1], point[2], exact_curve[i][2] }
				end

				return rows
			end)(),
		})

		----------------------------------------------------------------------
		local suite = check.new("независимость от частоты кадров")

		suite:close("exp(-k*dt) даёт одинаковый результат при любой частоте",
			spread.c[2] - spread.c[1], 0, 1e-12,
			"exp(-k*dt1)*exp(-k*dt2) = exp(-k*(dt1+dt2)) — тождество, "
			.. "поэтому разброс ограничен только округлением при "
			.. "накоплении произведения")

		suite:close("exp(-k*dt) совпадает с точным решением",
			spread.c[1], exact, 1e-12,
			"та же причина: это и есть точное решение, а не приближение")

		suite:is_true("множитель без dt даёт разную физику на разных частотах",
			spread.a[2] / math.max(spread.a[1], 1e-300) > 1e6,
			"результат при 10 и при 240 кадрах различается более чем в "
			.. "миллион раз ("
			.. ("%.3g против %.3g"):format(spread.a[2], spread.a[1])
			.. "): это буквально разные задачи, а не разная точность")

		suite:is_true("линейный множитель зависит от частоты",
			spread.b[2] - spread.b[1] > 1e-3,
			"явный Эйлер согласуется с точным решением только до O(dt), "
			.. "поэтому результат зависит от нарезки времени")

		suite:is_true("approach() из мода зависит от частоты кадров",
			mod_spread[2] - mod_spread[1] > 1e-3,
			"НАЙДЕННЫЙ ДЕФЕКТ: наклон машины в игре получается разным при "
			.. "разной частоте кадров. Разброс "
			.. ("%.3f"):format(mod_spread[2] - mod_spread[1])
			.. " по шкале, где полный ход равен 1")

		suite:close("правильная форма сближения от частоты не зависит",
			exact_spread[2] - exact_spread[1], 0, 1e-12,
			"замена min(rate*dt, 1) на 1 - exp(-rate*dt) делает операцию "
			.. "точной при любом шаге; это и есть предлагаемое исправление")

		suite:close("на просевшем кадре approach() прыгает в цель",
			snapped, P.target, 1e-12,
			"ограничение min(..., 1) обращает множитель в единицу, и "
			.. "значение достигает цели за один кадр — визуальный рывок")

		suite:close("фиксированный шаг воспроизводит траекторию при рваных кадрах",
			jittered.x.x, reference.x.x, 1e-12,
			"физика считается одним и тем же dt независимо от длительности "
			.. "кадров, поэтому последовательность шагов идентична")

		suite:close("скорость при рваных кадрах тоже совпадает",
			jittered.v.x, reference.v.x, 1e-12,
			"та же причина")

		return suite
	end,
}
