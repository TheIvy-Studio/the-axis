-- the Axis · physics lab · эксперимент 15
-- Отклик на столкновение: импульс, восстановление, трение.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local rigid = require("lab.rigid")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "15",
	name = "collision_response",
	title = "Отклик на столкновение",

	question = [[
Как правильно оттолкнуть тело от препятствия? В моде сейчас при упоре
скорость по оси просто обнуляется — это частный случай абсолютно неупругого
удара, и он не даёт ни отскока, ни трения, ни скольжения вдоль поверхности.]],

	model = [[
Импульсный метод [baraff_rigid]. Для двух тел, сталкивающихся по нормали n:

    j = -(1 + e) * (v_rel . n) / (1/m1 + 1/m2)                [кг·м/с]
    v1' = v1 + (j/m1)*n
    v2' = v2 - (j/m2)*n

Нормаль направлена от второго тела к первому, сближение означает
(v1 - v2).n < 0. Если тела расходятся, импульс не применяется — иначе они
«прилипают», получая каждый кадр добавку на разлёт.

Неподвижное препятствие — предельный случай бесконечной массы: 1/m2 = 0,
и тогда
    v' = v - (1 + e)*(v.n)*n
При e = 0 это ровно «обнулить составляющую по нормали», то есть то, что
делает мод сейчас. При e = 1 — зеркальное отражение.

Трение по Кулону: касательный импульс ограничен конусом трения
    |j_t| <= mu * |j_n|
Если импульса, нужного для полной остановки скольжения, хватает в пределах
конуса — контакт залипает, иначе скользит.

Прыгающий мяч даёт замкнутые формулы для проверки:
    высота n-го отскока    h_n = h_0 * e^(2n)                 [м]
    полное время до покоя  T = t_1 * (1 + e)/(1 - e)          [с]
где t_1 = sqrt(2*h_0/g) — время первого падения. Второе выражение конечно
при e < 1, хотя число отскоков бесконечно: сумма геометрической прогрессии.

Размерности: j = [кг·м/с]; j/m = [м/с]. Сходятся.]],

	simplifications = [[
1. Удар мгновенный и точечный. Реальный контакт имеет длительность и
   площадь. Для игры мгновенный удар — стандарт.
2. Вращение при ударе не учитывается. Полная формула добавляет в знаменатель
   члены с обратным тензором инерции; без них удар по краю конструкции не
   закручивает её, а должен бы.
3. Коэффициент восстановления считается постоянным. У настоящих материалов
   он падает с ростом скорости удара.
4. Одновременные контакты (тело лежит на нескольких блоках) решаются
   последовательно, а не совместно. Это стандартная практика, но она даёт
   дрожание на стопках тел.]],

	references = { R.baraff_rigid },

	params = {
		mass = { value = 800.0, note = "масса тела, кг" },
		restitution = { value = 0.45, note = "коэффициент восстановления" },
		friction = { value = 0.6, note = "коэффициент трения" },
		drop_height = { value = 20.0, note = "высота падения, м" },
		gravity = { value = 9.81, note = "ускорение падения, м/с^2" },
		impact_speed = { value = 15.0, note = "скорость удара для расчётов, м/с" },
		slide_speed = { value = 3.0, note = "скорость скольжения вдоль поверхности, м/с" },
	},

	run = function(P, ctx)
		----------------------------------------------------------------------
		-- Удар о неподвижное препятствие
		----------------------------------------------------------------------
		local normal = vec3.new(0, 1, 0)
		local incoming = vec3.new(P.slide_speed, -P.impact_speed, 0)

		print("Удар о неподвижную поверхность (нормаль вверх):")
		print(("  скорость до удара: %s"):format(tostring(incoming)))

		print()
		print(text.row {
			{ "e", 8 }, { "скорость после", 26 }, { "отскок, м/с", 14 },
			{ "потеря энергии, %", 18 },
		})

		local before_energy = 0.5 * P.mass * vec3.length_squared(incoming)
		local restitution_curve = {}
		local worst_definition = 0

		for index = 0, 10 do
			local e = index / 10

			local impulse = rigid.collision_impulse(incoming, vec3.zero,
				normal, 1 / P.mass, 0, e)

			local after = incoming + normal * (impulse / P.mass)
			local after_energy = 0.5 * P.mass * vec3.length_squared(after)

			-- Определение: скорость отскока равна e * скорость подлёта
			worst_definition = math.max(worst_definition,
				math.abs(vec3.dot(after, normal)
					- (-e * vec3.dot(incoming, normal))) / P.impact_speed)

			restitution_curve[#restitution_curve + 1] = { e, after.y }

			print(text.row {
				{ ("%.1f"):format(e), 8 },
				{ tostring(after), 26 },
				{ ("%.4f"):format(after.y), 14 },
				{ ("%.2f"):format((1 - after_energy / before_energy) * 100), 18 },
			})
		end

		print()
		print("Обратите внимание на строку e = 0: составляющая по нормали")
		print("обнуляется, касательная не трогается. Это ровно то, что делает")
		print("мод сейчас, — частный случай, а не отдельный механизм.")

		----------------------------------------------------------------------
		-- Трение
		----------------------------------------------------------------------
		local normal_impulse = rigid.collision_impulse(incoming, vec3.zero,
			normal, 1 / P.mass, 0, P.restitution)

		print()
		print(("Нормальный импульс при e = %.2f: %.2f кг·м/с")
			:format(P.restitution, normal_impulse))

		print()
		print(text.row {
			{ "mu", 8 }, { "предел конуса", 16 }, { "нужно для остановки", 22 },
			{ "касательный импульс", 22 }, { "режим", 12 },
		})

		local required = -P.slide_speed / (1 / P.mass)
		local friction_curve = {}

		for _, mu in ipairs({ 0.0, 0.05, 0.1, 0.2, 0.4, 0.6, 1.0 }) do
			local tangential = rigid.friction_impulse(P.slide_speed,
				normal_impulse, 1 / P.mass, mu)

			local limit = mu * math.abs(normal_impulse)
			local sticks = math.abs(required) <= limit

			friction_curve[#friction_curve + 1] = { mu, math.abs(tangential) }

			print(text.row {
				{ ("%.2f"):format(mu), 8 },
				{ ("%.2f"):format(limit), 16 },
				{ ("%.2f"):format(math.abs(required)), 22 },
				{ ("%.2f"):format(tangential), 22 },
				{ sticks and "залипание" or "скольжение", 12 },
			})
		end

		----------------------------------------------------------------------
		-- Прыгающий мяч
		----------------------------------------------------------------------
		local e = P.restitution
		local g = P.gravity
		local h0 = P.drop_height
		local t1 = math.sqrt(2 * h0 / g)
		local total_time = t1 * (1 + e) / (1 - e)

		print()
		print(("Прыгающий мяч, e = %.2f, высота %.1f м:"):format(e, h0))
		print(("  время первого падения t1 = sqrt(2h/g) = %.4f с"):format(t1))
		print(("  полное время до покоя t1*(1+e)/(1-e)  = %.4f с"):format(total_time))

		local heights = {}
		local simulated_time = t1
		local speed = math.sqrt(2 * g * h0)
		local worst_height_error = 0

		print()
		print(text.row {
			{ "отскок", 10 }, { "высота, м", 14 }, { "h0*e^(2n)", 14 },
			{ "время, с", 12 },
		})

		for n = 1, 12 do
			-- Импульсный отклик применяется к настоящей скорости подлёта
			local impulse = rigid.collision_impulse(vec3.new(0, -speed, 0),
				vec3.zero, normal, 1 / P.mass, 0, e)

			speed = -(vec3.new(0, -speed, 0) + normal * (impulse / P.mass)).y
			speed = math.abs(speed)

			local height = speed * speed / (2 * g)
			local predicted = h0 * e ^ (2 * n)

			worst_height_error = math.max(worst_height_error,
				math.abs(height - predicted) / predicted)

			heights[#heights + 1] = { n, height }

			-- Полёт вверх и обратно
			simulated_time = simulated_time + 2 * speed / g

			if n <= 6 then
				print(text.row {
					{ tostring(n), 10 },
					{ ("%.6f"):format(height), 14 },
					{ ("%.6f"):format(predicted), 14 },
					{ ("%.4f"):format(simulated_time), 12 },
				})
			end
		end

		print(("  ... после 12 отскоков накоплено %.4f с из %.4f с")
			:format(simulated_time, total_time))

		ctx.show({
			{ label = "высота отскока", mark = "*", points = heights },
		}, {
			title = "Высота отскоков падает как e^(2n)",
			xlabel = "номер отскока",
			ylabel = "высота, м",
			height = 15,
		})

		ctx.save({
			{ label = "высота, м", points = heights },
		}, {
			title = "Затухание отскоков",
			xlabel = "номер отскока",
			ylabel = "высота, м",
		}, {
			headers = { "bounce", "height" },
			rows = heights,
		})

		----------------------------------------------------------------------
		local suite = check.new("столкновения")

		suite:close("скорость отскока равна e умножить на скорость подлёта",
			worst_definition, 0, 1e-14,
			"определение коэффициента восстановления; проверяется сразу на "
			.. "одиннадцати значениях e")

		suite:is_true("при e = 0 касательная скорость не меняется",
			(function()
				local impulse = rigid.collision_impulse(incoming, vec3.zero,
					normal, 1 / P.mass, 0, 0)
				local after = incoming + normal * (impulse / P.mass)

				return math.abs(after.x - incoming.x) < 1e-14
					and math.abs(after.y) < 1e-14
			end)(),
			"импульс направлен строго по нормали, значит на касательную "
			.. "составляющую он повлиять не может")

		suite:is_true("расходящиеся тела не получают импульса",
			rigid.collision_impulse(vec3.new(0, 5, 0), vec3.zero, normal,
				1 / P.mass, 0, P.restitution) == 0,
			"без этой проверки тела «прилипают»: каждый кадр им добавляется "
			.. "импульс на разлёт, и они дрожат на поверхности")

		suite:close("высоты отскоков падают как h0*e^(2n)",
			worst_height_error, 0, 1e-12,
			"скорость умножается на e при каждом ударе, а высота "
			.. "квадратична по скорости — отсюда степень 2n")

		suite:is_true("трение не превышает конус Кулона",
			(function()
				for _, mu in ipairs({ 0.0, 0.05, 0.1, 0.2, 0.4, 0.6, 1.0 }) do
					local tangential = rigid.friction_impulse(P.slide_speed,
						normal_impulse, 1 / P.mass, mu)

					if math.abs(tangential) > mu * math.abs(normal_impulse) + 1e-12 then
						return false
					end
				end

				return true
			end)(),
			"условие |j_t| <= mu*|j_n| — определение сухого трения; его "
			.. "нарушение означало бы силу трения из ниоткуда")

		suite:close("при нулевом трении касательный импульс равен нулю",
			rigid.friction_impulse(P.slide_speed, normal_impulse,
				1 / P.mass, 0), 0, 1e-14,
			"конус вырождается в точку")

		suite:is_true("полное время отскоков конечно",
			total_time < math.huge and total_time > t1,
			"сумма геометрической прогрессии сходится при e < 1: отскоков "
			.. "бесконечно много, а времени они занимают конечно")

		suite:close("время до покоя равно t1*(1+e)/(1-e)",
			t1 * (1 + e) / (1 - e), total_time, 1e-12,
			"замкнутая сумма ряда 1 + 2*sum(e^n)")

		return suite
	end,
}
