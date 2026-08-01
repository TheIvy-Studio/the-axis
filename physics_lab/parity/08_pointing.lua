-- the Axis · physics lab · соответствие 08
-- Наведение на конструкцию: выполняется настоящий api/pointing.lua.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local mod = require("parity.mod")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "П8",
	name = "parity_pointing",
	title = "Соответствие: наведение на конструкцию",

	question = [[
Попадает ли игрок туда, куда целится, когда строит на собранной машине?

Раньше сторона установки угадывалась по одному лишь направлению взгляда:
брали ось, вдоль которой игрок смотрит сильнее всего, и ставили деталь с той
стороны. Поставить блок сбоку, глядя чуть сверху, было невозможно, а у
повёрнутой машины блок вставал вообще не с той стороны — взгляд считался в
осях мира, а смещение в осях постройки.]],

	model = [[
ПОВОРОТ. Матрица конструкции обязана совпадать с той, что движок строит для
сущности в setPitchYawRollRad: углы берутся с обратным знаком, порядок —
крен, тангаж, курс. Совпадение проверяется двумя способами:

  * при нулевых тангаже и крене преобразование обязано в точности совпасть с
    contraption.rotate, которой мод уже поворачивает детали;
  * поворот обязан сохранять длину и быть обратимым — это свойство любой
    матрицы поворота.

ЛУЧ И КУБ. Метод плит: для каждой оси считается отрезок времени, пока луч
находится между парой граней. Пересечение есть, когда все три отрезка
перекрываются; грань входа — та, в которую луч вошёл ПОСЛЕДНЕЙ. Именно так
движок определяет грань у обычных нод, и именно поэтому косой луч попадает в
боковую грань, а не в ту, к которой ближе.

ВЫБОР ДЕТАЛИ. Из всех деталей на пути берётся ближайшая по расстоянию входа.
Деталь, внутри которой стоит сам игрок, пропускается: вход в неё остался
позади глаз.]],

	simplifications = [[
1. Каждая деталь считается полным кубом. Плиты, лестницы и прочие ноды с
   собственной формой ловятся указателем как целые блоки — то же самое делает
   и коллизия деталей.
2. Проверяется геометрия, а не то, попадёт ли по детали сам движок. Движок
   выбирает объект по НЕПОВЁРНУТОМУ кубу вокруг него, поэтому у сильно
   накренённой машины он может не увидеть деталь вовсе; тогда клика не будет
   и точность наведения ни при чём.]],

	references = { R.mit_16_07_l26 },

	params = {
		fuselage = { value = 7, note = "длина испытательной постройки, блоков" },
	},

	run = function(P, ctx)
		local suite = check.new("соответствие: наведение")

		-- pointing.lua опирается на contraption.rotate из geometry.lua, а тот
		-- тянет за собой core. Поворот вокруг вертикали подставляется здесь
		-- ровно в том виде, в каком он записан в моде, и это же сравнение
		-- служит проверкой.
		local loaded, reason = mod.load({ "api/pointing.lua" }, {
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

		------------------------------------------------------------------
		-- 1. Поворот
		------------------------------------------------------------------
		local yaw_error = 0

		for _, yaw in ipairs({ 0, 0.3, 1.0, math.pi / 2, 2.5, -1.2 }) do
			local m = mod.call(loaded, loaded.rotation_matrix, 0, yaw, 0)

			for _, v in ipairs({ { x = 1, y = 0, z = 0 }, { x = 0, y = 1, z = 0 },
					{ x = 0, y = 0, z = 1 }, { x = 2, y = -3, z = 1.5 } }) do
				local a = mod.call(loaded, loaded.to_world, v, m)
				local b = loaded.rotate(v, yaw)

				yaw_error = math.max(yaw_error, math.abs(a.x - b.x),
					math.abs(a.y - b.y), math.abs(a.z - b.z))
			end
		end

		local round_trip, length_error = 0, 0

		for _, angles in ipairs({ { 0, 0, 0 }, { 0.2, 1.1, -0.4 },
				{ -0.7, 2.0, 0.9 }, { 1.3, -2.2, 0.6 } }) do
			local m = mod.call(loaded, loaded.rotation_matrix, angles[1],
				angles[2], angles[3])

			for _, v in ipairs({ { x = 1, y = 2, z = 3 },
					{ x = -4, y = 0.5, z = 2 } }) do
				local world = mod.call(loaded, loaded.to_world, v, m)
				local back = mod.call(loaded, loaded.to_body, world, m)

				round_trip = math.max(round_trip, math.abs(back.x - v.x),
					math.abs(back.y - v.y), math.abs(back.z - v.z))

				length_error = math.max(length_error, math.abs(
					math.sqrt(v.x ^ 2 + v.y ^ 2 + v.z ^ 2)
					- math.sqrt(world.x ^ 2 + world.y ^ 2 + world.z ^ 2)))
			end
		end

		print()
		print(("Поворот: совпадение с contraption.rotate %.2e, обратимость "
			.. "%.2e, длина %.2e"):format(yaw_error, round_trip, length_error))

		------------------------------------------------------------------
		-- 2. Грани куба
		------------------------------------------------------------------
		local centre = { x = 0, y = 0, z = 0 }

		local FACES = {
			{ "справа", { x = 5, y = 0, z = 0 }, { x = -1, y = 0, z = 0 }, "x", 1, 4.5 },
			{ "слева", { x = -5, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, "x", -1, 4.5 },
			{ "сверху", { x = 0, y = 3, z = 0 }, { x = 0, y = -1, z = 0 }, "y", 1, 2.5 },
			{ "снизу", { x = 0, y = -3, z = 0 }, { x = 0, y = 1, z = 0 }, "y", -1, 2.5 },
			{ "спереди", { x = 0, y = 0, z = 8 }, { x = 0, y = 0, z = -1 }, "z", 1, 7.5 },
			{ "сзади", { x = 0, y = 0, z = -8 }, { x = 0, y = 0, z = 1 }, "z", -1, 7.5 },
		}

		print()
		print("Грань, в которую попадает луч:")
		print(text.row {
			{ "откуда", 12 }, { "нормаль", 14 }, { "расстояние", 14 },
			{ "ожидалось", 12 },
		})

		local face_error = 0
		local faces_right = true

		for _, case in ipairs(FACES) do
			local name, origin, direction = case[1], case[2], case[3]
			local axis, sign, distance = case[4], case[5], case[6]

			local d, normal = mod.call(loaded, loaded.ray_cube, origin,
				direction, centre)

			if not d or normal[axis] ~= sign then
				faces_right = false
			else
				face_error = math.max(face_error, math.abs(d - distance))
			end

			print(text.row {
				{ name, 12 },
				{ normal and ("%+d %+d %+d"):format(normal.x, normal.y,
					normal.z) or "промах", 14 },
				{ d and ("%.4f"):format(d) or "—", 14 },
				{ ("%.2f"):format(distance), 12 },
			})
		end

		-- Косой луч: в плиту по Y он входит на t = 1.875, а по X на t = 2.5,
		-- то есть позже. Значит грань входа боковая, а не верхняя, хотя
		-- смотрит игрок сверху.
		local slant, slant_normal = mod.call(loaded, loaded.ray_cube,
			{ x = -2, y = 2, z = 0 }, { x = 0.6, y = -0.8, z = 0 }, centre)

		print()
		print(("Косой луч сверху-сбоку: нормаль %+d %+d %+d, расстояние %.4f")
			:format(slant_normal.x, slant_normal.y, slant_normal.z, slant))
		print("Грань входа — та, в которую луч вошёл последней. Раньше сторона")
		print("выбиралась по наибольшей составляющей взгляда, и здесь получилась")
		print("бы верхняя грань, то есть блок встал бы не туда.")

		local miss = mod.call(loaded, loaded.ray_cube, { x = 5, y = 5, z = 5 },
			{ x = -1, y = 0, z = 0 }, centre)
		local behind = mod.call(loaded, loaded.ray_cube, { x = 5, y = 0, z = 0 },
			{ x = 1, y = 0, z = 0 }, centre)
		local inside = mod.call(loaded, loaded.ray_cube, { x = 0, y = 0, z = 0 },
			{ x = 1, y = 0, z = 0 }, centre)

		------------------------------------------------------------------
		-- 3. Выбор детали
		------------------------------------------------------------------
		local parts = {}
		local offset = (P.fuselage - 1) / 2

		for index = 0, P.fuselage - 1 do
			parts[#parts + 1] = { position = { x = 0, y = 0, z = index - offset } }
		end

		local top_index = #parts + 1
		parts[top_index] = { position = { x = 0, y = 1, z = 0 } }

		local side_index, side_normal = mod.call(loaded, loaded.pick_part, parts,
			{ x = 10, y = 0, z = 0 }, { x = -1, y = 0, z = 0 }, 20)

		local above_index, above_normal = mod.call(loaded, loaded.pick_part,
			parts, { x = 0, y = 10, z = 0 }, { x = 0, y = -1, z = 0 }, 20)

		-- Луч, проходящий мимо всей постройки
		local nothing = mod.call(loaded, loaded.pick_part, parts,
			{ x = 10, y = 10, z = 0 }, { x = 0, y = 1, z = 0 }, 20)

		print()
		print(("Сбоку виден блок %d, нормаль x=%+d; сверху блок %d, нормаль y=%+d")
			:format(side_index or 0, side_normal and side_normal.x or 0,
				above_index or 0, above_normal and above_normal.y or 0))

		------------------------------------------------------------------
		-- 4. Повёрнутая конструкция
		------------------------------------------------------------------
		-- Постройка развёрнута на 90 градусов, игрок смотрит на неё с востока.
		-- Новая деталь обязана встать со стороны игрока — в осях МИРА, а не
		-- постройки. Прежний счёт ошибался именно здесь.
		print()
		print("Куда встанет блок при разном повороте конструкции:")
		print(text.row {
			{ "курс, °", 10 }, { "в осях постройки", 20 }, { "в осях мира", 22 },
		})

		local world_error = 0
		local placed_right = true

		for _, degrees in ipairs({ 0, 45, 90, 180, 270 }) do
			local yaw = math.rad(degrees)
			local rig = { parts = parts, pitch = 0, yaw = yaw, roll = 0 }

			local hit = mod.call(loaded, loaded.trace, rig,
				{ x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 },
				{ x = -1, y = 0, z = 0 }, 20)

			if not hit then
				placed_right = false
			else
				local world = mod.call(loaded, loaded.to_world, hit.place,
					hit.matrix)

				-- Игрок стоит на востоке и смотрит на запад: блок обязан
				-- оказаться восточнее детали и на той же высоте
				if world.x <= 0 or math.abs(world.y) > 0.01 then
					placed_right = false
				end

				world_error = math.max(world_error, math.abs(world.z))

				print(text.row {
					{ ("%d"):format(degrees), 10 },
					{ ("(%.0f, %.0f, %.0f)"):format(hit.place.x, hit.place.y,
						hit.place.z), 20 },
					{ ("(%.2f, %.2f, %.2f)"):format(world.x, world.y, world.z), 22 },
				})
			end
		end

		print()
		print("В осях постройки смещение каждый раз разное, а в осях мира блок")
		print("всегда встаёт со стороны игрока. Это и есть то, что ломалось.")

		------------------------------------------------------------------
		-- 5. Занятость клетки
		------------------------------------------------------------------
		local occupied = mod.call(loaded, loaded.cell_free, parts,
			{ x = 0, y = 0, z = 0 })
		local vacant = mod.call(loaded, loaded.cell_free, parts,
			{ x = 5, y = 5, z = 5 })

		------------------------------------------------------------------
		suite:close("поворот по курсу совпадает с contraption.rotate",
			yaw_error, 0, 1e-12,
			"мод уже поворачивает детали функцией contraption.rotate, и "
			.. "матрица наведения обязана давать то же самое. Разойдись они — "
			.. "подсветка встала бы не там, где игрок видит деталь")

		suite:close("преобразование обратимо",
			round_trip, 0, 1e-12,
			"матрица поворота ортогональна, поэтому обратное преобразование — "
			.. "транспонирование. Остаётся только округление")

		suite:close("поворот не меняет длину",
			length_error, 0, 1e-12,
			"свойство любой матрицы поворота; его нарушение означало бы, что "
			.. "в матрице закралось растяжение")

		suite:is_true("все шесть граней куба определяются верно",
			faces_right,
			"луч, пущенный с каждой из шести сторон, обязан дать нормаль той "
			.. "грани, в которую он вошёл")

		suite:close("расстояние до грани совпадает с расчётным",
			face_error, 0, 1e-12,
			"расстояние до плоскости грани считается точно: это деление "
			.. "разности координат на составляющую направления")

		suite:is_true("косой луч входит через грань, в которую вошёл последней",
			slant_normal.x == -1 and math.abs(slant - 2.5) < 1e-12,
			"взгляд направлен вниз сильнее, чем вбок, но в боковую плиту луч "
			.. "входит позже. Прежний счёт выбрал бы верхнюю грань по "
			.. "наибольшей составляющей взгляда — и промахнулся бы")

		suite:is_true("луч мимо куба не попадает", miss == nil,
			"отрезки по осям не перекрываются, значит пересечения нет")

		suite:is_true("куб позади глаз не считается попаданием", behind == nil,
			"луч уходит от куба; выход из него остался позади начала")

		suite:is_true("деталь, внутри которой стоит игрок, пропускается",
			inside ~= nil and inside < 0,
			"вход в куб позади глаз, поэтому расстояние отрицательное, и "
			.. "contraption.pick_part такую деталь не берёт: игрок смотрит на "
			.. "то, что дальше, а не на стенку вокруг себя")

		suite:is_true("сбоку виден крайний блок, а не дальний",
			side_index ~= nil and side_normal.x == 1,
			"из всех деталей на пути берётся ближайшая по расстоянию входа")

		suite:is_true("сверху виден верхний блок, а не тот, что под ним",
			above_index == top_index and above_normal.y == 1,
			"блок на крыше ближе к глазам, значит именно он и попадает под "
			.. "прицел")

		suite:is_true("луч мимо постройки ничего не выбирает",
			nothing == nil,
			"иначе игрок ставил бы блоки, глядя в небо")

		suite:is_true("на повёрнутой конструкции блок встаёт со стороны игрока",
			placed_right,
			"проверено на пяти углах поворота, включая 45 градусов, где ось "
			.. "постройки не совпадает ни с одной осью мира. Прежний счёт "
			.. "смешивал оси мира и постройки и ошибался тем сильнее, чем "
			.. "больше повёрнута машина")

		suite:close("блок не уезжает вбок при повороте",
			world_error, 0, 1e-12,
			"игрок смотрит строго вдоль оси X, значит и новая деталь обязана "
			.. "оказаться на той же линии: боковое смещение — ровно ноль")

		suite:is_true("занятая клетка не считается свободной", not occupied,
			"иначе две детали встали бы в одну клетку")

		suite:is_true("свободная клетка распознаётся", vacant,
			"иначе строить было бы негде")

		return suite
	end,
}
