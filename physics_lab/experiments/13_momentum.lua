-- the Axis · physics lab · эксперимент 13
-- Импульс: сохранение при взаимодействии, движение центра масс.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local rigid = require("lab.rigid")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "13",
	name = "momentum",
	title = "Импульс и его сохранение",

	question = [[
Что в столкновении сохраняется всегда, а что — только иногда? И почему центр
масс системы продолжает двигаться так, будто ничего не произошло?

Практическая польза: закон сохранения импульса — самая надёжная проверка
любого кода столкновений. Он выполняется при ЛЮБОМ коэффициенте
восстановления, при любом трении, при любом числе тел.]],

	model = [[
Импульс тела:
    p = m*v                                                  [кг·м/с]

Третий закон Ньютона: силы взаимодействия равны и противоположны, значит их
вклады в суммарный импульс сокращаются. Отсюда: суммарный импульс замкнутой
системы сохраняется ТОЧНО, независимо от характера взаимодействия.

Кинетическая энергия — не сохраняется:
    T = 0.5*m*v^2                                            [Дж]
При ударе с коэффициентом восстановления e теряется
    dT = 0.5 * mu * (1 - e^2) * v_rel^2                      [Дж]
где mu = m1*m2/(m1+m2) — приведённая масса. При e = 1 потерь нет (абсолютно
упругий удар), при e = 0 теряется всё относительное движение.

Скорость центра масс:
    v_cm = sum(m_i*v_i) / sum(m_i)                           [м/с]
не меняется при внутренних взаимодействиях — это переформулировка того же
закона.

Размерности: [кг]·[м/с] = [кг·м/с]; приведённая масса [кг^2]/[кг] = [кг],
значит dT = [кг]·[м^2/с^2] = [Дж]. Сходятся.]],

	simplifications = [[
Удары считаются мгновенными и центральными (вдоль линии центров). Реальный
удар длится конечное время и деформирует тела; коэффициент восстановления
как раз и сворачивает всю эту сложность в одно число. Вращение при ударе не
учитывается — это эксперимент 15.]],

	references = { R.baraff_rigid, R.mit_16_07_l28 },

	params = {
		mass1 = { value = 1200.0, note = "масса первого тела, кг" },
		mass2 = { value = 400.0, note = "масса второго тела, кг" },
		speed1 = { value = 12.0, note = "скорость первого тела, м/с" },
		speed2 = { value = -5.0, note = "скорость второго тела, м/с" },
	},

	run = function(P, ctx)
		local m1, m2 = P.mass1, P.mass2
		local reduced = m1 * m2 / (m1 + m2)

		print(("Тела: m1 = %.1f кг (v = %.2f м/с), m2 = %.1f кг (v = %.2f м/с)")
			:format(m1, P.speed1, m2, P.speed2))
		print(("Приведённая масса mu = m1*m2/(m1+m2) = %.3f кг"):format(reduced))

		local p_before = m1 * P.speed1 + m2 * P.speed2
		local t_before = 0.5 * m1 * P.speed1 ^ 2 + 0.5 * m2 * P.speed2 ^ 2
		local v_cm = p_before / (m1 + m2)
		local relative = P.speed1 - P.speed2

		print()
		print(("До удара: суммарный импульс %.4f кг·м/с, энергия %.4f Дж")
			:format(p_before, t_before))
		print(("Скорость центра масс %.6f м/с, относительная скорость %.4f м/с")
			:format(v_cm, relative))

		----------------------------------------------------------------------
		-- Перебор коэффициента восстановления
		----------------------------------------------------------------------
		print()
		print(text.row {
			{ "e", 8 }, { "v1', м/с", 12 }, { "v2', м/с", 12 },
			{ "импульс", 14 }, { "энергия, Дж", 14 }, { "потеря, Дж", 14 },
		})

		local worst_momentum_error = 0
		local worst_loss_error = 0
		local worst_separation_error = 0
		local results = {}
		local loss_curve = {}

		for index = 0, 10 do
			local e = index / 10

			-- Импульсный отклик (та же функция, что и в столкновениях).
			-- Нормаль направлена ОТ второго тела К первому: сближение тогда
			-- означает (v1 - v2).n < 0. Догоняющее тело идёт в +x, значит
			-- нормаль смотрит в -x.
			local normal = vec3.new(-1, 0, 0)

			local impulse = rigid.collision_impulse(
				vec3.new(P.speed1, 0, 0), vec3.new(P.speed2, 0, 0),
				normal, 1 / m1, 1 / m2, e)

			local v1 = P.speed1 + impulse * normal.x / m1
			local v2 = P.speed2 - impulse * normal.x / m2

			local p_after = m1 * v1 + m2 * v2
			local t_after = 0.5 * m1 * v1 * v1 + 0.5 * m2 * v2 * v2
			local loss = t_before - t_after
			local predicted_loss = 0.5 * reduced * (1 - e * e) * relative ^ 2

			worst_momentum_error = math.max(worst_momentum_error,
				math.abs(p_after - p_before) / math.abs(p_before))
			worst_loss_error = math.max(worst_loss_error,
				math.abs(loss - predicted_loss) / math.max(predicted_loss, 1e-9))

			-- Определение коэффициента восстановления: скорость разлёта
			-- равна e, умноженному на скорость сближения
			worst_separation_error = math.max(worst_separation_error,
				math.abs((v2 - v1) - e * relative) / math.max(relative, 1e-9))

			results[#results + 1] = { e = e, v1 = v1, v2 = v2 }
			loss_curve[#loss_curve + 1] = { e, loss }

			print(text.row {
				{ ("%.1f"):format(e), 8 },
				{ ("%.4f"):format(v1), 12 },
				{ ("%.4f"):format(v2), 12 },
				{ ("%.6f"):format(p_after), 14 },
				{ ("%.4f"):format(t_after), 14 },
				{ ("%.4f"):format(loss), 14 },
			})
		end

		print()
		print(("Импульс сохраняется при любом e: худшее отклонение %.2e")
			:format(worst_momentum_error))
		print(("Потеря энергии совпадает с 0.5*mu*(1-e^2)*v_rel^2: %.2e")
			:format(worst_loss_error))

		----------------------------------------------------------------------
		-- Полностью неупругий удар
		----------------------------------------------------------------------
		local inelastic = results[1]

		print()
		print(("Полностью неупругий удар (e = 0): оба тела уходят со скоростью "
			.. "%.6f м/с"):format(inelastic.v1))
		print(("Это ровно скорость центра масс %.6f м/с — не совпадение, а "
			.. "следствие сохранения импульса"):format(v_cm))

		----------------------------------------------------------------------
		-- Абсолютно упругий удар: классические формулы
		----------------------------------------------------------------------
		local elastic = results[#results]
		local classic_v1 = ((m1 - m2) * P.speed1 + 2 * m2 * P.speed2) / (m1 + m2)
		local classic_v2 = ((m2 - m1) * P.speed2 + 2 * m1 * P.speed1) / (m1 + m2)

		print()
		print("Абсолютно упругий удар (e = 1):")
		print(("  импульсный метод:  v1 = %.6f, v2 = %.6f")
			:format(elastic.v1, elastic.v2))
		print(("  классические формулы: v1 = %.6f, v2 = %.6f")
			:format(classic_v1, classic_v2))

		----------------------------------------------------------------------
		-- Многотельная система: внутренние силы сокращаются
		----------------------------------------------------------------------
		local bodies = {
			{ mass = 300, velocity = vec3.new(4, 1, -2) },
			{ mass = 700, velocity = vec3.new(-3, 0, 5) },
			{ mass = 150, velocity = vec3.new(9, -6, 1) },
		}

		local total_mass, total_momentum = 0, vec3.zero

		for _, b in ipairs(bodies) do
			total_mass = total_mass + b.mass
			total_momentum = total_momentum + b.velocity * b.mass
		end

		local system_cm = total_momentum / total_mass

		-- Прикладываем пары равных и противоположных внутренних сил
		local dt_step = 0.01
		local pair_force = vec3.new(1200, -800, 400)

		bodies[1].velocity = bodies[1].velocity + pair_force * (dt_step / bodies[1].mass)
		bodies[2].velocity = bodies[2].velocity - pair_force * (dt_step / bodies[2].mass)

		local after_momentum = vec3.zero

		for _, b in ipairs(bodies) do
			after_momentum = after_momentum + b.velocity * b.mass
		end

		print()
		print(("Система из 3 тел, суммарный импульс до: %s")
			:format(tostring(total_momentum)))
		print(("После пары внутренних сил:              %s")
			:format(tostring(after_momentum)))
		print(("Скорость центра масс: %s"):format(tostring(system_cm)))

		ctx.show({
			{ label = "потеря энергии", mark = "*", points = loss_curve },
		}, {
			title = "Потеря энергии в зависимости от коэффициента восстановления",
			xlabel = "e",
			ylabel = "потеря, Дж",
			height = 15,
		})

		ctx.save({
			{ label = "потеря энергии, Дж", points = loss_curve },
		}, {
			title = "Потеря энергии при ударе",
			xlabel = "коэффициент восстановления",
			ylabel = "потеря энергии, Дж",
		}, {
			headers = { "e", "energy_loss" },
			rows = loss_curve,
		})

		----------------------------------------------------------------------
		local suite = check.new("импульс")

		suite:close("импульс сохраняется при любом e",
			worst_momentum_error, 0, 1e-14,
			"третий закон Ньютона: импульсы, полученные телами, равны и "
			.. "противоположны по построению формулы. Допуск — машинная "
			.. "точность")

		suite:close("потеря энергии равна 0.5*mu*(1-e^2)*v_rel^2",
			worst_loss_error, 0, 1e-12,
			"классический результат теории удара; проверяется на всех "
			.. "одиннадцати значениях e сразу")

		suite:close("скорость разлёта равна e умножить на скорость сближения",
			worst_separation_error, 0, 1e-14,
			"это и есть определение коэффициента восстановления")

		suite:close("при e = 0 тела уходят со скоростью центра масс",
			inelastic.v1, v_cm, 1e-12,
			"относительное движение погашено полностью, остаётся только "
			.. "движение системы как целого")

		suite:close("упругий удар совпадает с классическими формулами",
			elastic.v1, classic_v1, 1e-12,
			"два независимых вывода: через импульс и через совместное "
			.. "решение уравнений сохранения импульса и энергии")

		suite:close("при e = 1 энергия сохраняется",
			0.5 * m1 * elastic.v1 ^ 2 + 0.5 * m2 * elastic.v2 ^ 2, t_before,
			1e-12,
			"абсолютно упругий удар по определению не теряет энергии")

		suite:close("внутренние силы не меняют импульс системы",
			vec3.length(after_momentum - total_momentum),
			0, 1e-10,
			"допуск абсолютный, в кг·м/с; пара сил равна и противоположна, "
			.. "поэтому вклад строго нулевой")

		return suite
	end,
}
