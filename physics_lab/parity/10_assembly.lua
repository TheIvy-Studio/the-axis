-- the Axis · physics lab · соответствие 10
-- Сборка: выполняются настоящие api/scan.lua, api/selection.lua и
-- api/geometry.lua.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local mod = require("parity.mod")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

--- Мир на время проверки: какие ноды где стоят и что склеено.
local world = { nodes = {}, bonded = {} }

local function cell(pos)
	return ("%d:%d:%d"):format(pos.x, pos.y, pos.z)
end

local function engine_stub()
	return {
		hash_node_position = cell,
		get_node = function(pos)
			return { name = world.nodes[cell(pos)] or "air" }
		end,
		register_on_leaveplayer = function() end,
		register_globalstep = function() end,
		add_particle = function() end,
		get_connected_players = function() return {} end,
		registered_nodes = {
			-- Забор: столб плюс перемычки к соседям, коробка «connected»
			["mcl_fences:fence"] = {
				groups = { axey = 1 }, walkable = true,
				node_box = {
					type = "connected",
					fixed = { { -0.125, -0.5, -0.125, 0.125, 0.5, 0.125 } },
					connect_front = { { -0.1, 0, -0.5, 0.1, 0.4, 0 } },
				},
				collision_box = {
					type = "connected",
					fixed = { { -0.125, -0.5, -0.125, 0.125, 1.0, 0.125 } },
					connect_front = { { -0.1, 0, -0.5, 0.1, 0.9, 0 } },
				},
			},
			-- Плита: половина куба
			["mcl_stairs:slab"] = {
				groups = { pickaxey = 1 }, walkable = true,
				node_box = { type = "fixed",
					fixed = { -0.5, -0.5, -0.5, 0.5, 0, 0.5 } },
			},
			-- Ступенька: две коробки
			["mcl_stairs:stair"] = {
				groups = { pickaxey = 1 }, walkable = true,
				node_box = { type = "fixed", fixed = {
					{ -0.5, -0.5, -0.5, 0.5, 0, 0.5 },
					{ -0.5, 0, 0, 0.5, 0.5, 0.5 },
				} },
			},
			["mcl_core:stone"] = { groups = { pickaxey = 1 }, walkable = true },
			["axis_contraption:envelope"] = { walkable = true },
		},
	}
end

return experiment.define {
	id = "П10",
	name = "parity_assembly",
	title = "Соответствие: сборка и выделение",

	question = [[
Соберётся ли в одно целое круглый шар — и попадёт ли клей туда, куда его
навели?

Обход склеенного шёл только по граням, и круглая оболочка разваливалась на
десяток отдельных конструкций: у ступенек соседние блоки стоят по диагонали и
гранями не соприкасаются вовсе. Собрать шар было попросту нельзя.]],

	model = [[
СОСЕДСТВО ПО КАСАНИЮ. Скреплённые блоки держатся вместе, если соприкасаются
хоть чем-нибудь: гранью, ребром или углом. Поэтому обход идёт по всем
двадцати шести клеткам вокруг, а не по шести.

Расширять его безопасно: он всё равно ходит только по блокам, намазанным
клеем, и шире отмеченного не уедет.

ВЫДЕЛЕНИЕ КОРОБКОЙ. Клей берёт всю коробку между двумя углами, а не линию
между ними. Поэтому выделять можно и по диагонали: отметил угол оболочки,
навёлся на противоположный — захватился весь куб. Порядок углов и знак
координат значения не имеют.

ГАБАРИТЫ ДЕТАЛИ. Коробка вида «connected» — забор, стена, стекло в рамке —
считается по столбу: перемычки к соседям есть не всегда, а вес и коллизия
блока не должны зависеть от того, что стоит рядом. Пока этого не было, забор
получал коллизию в целый блок и загораживал палубу, а весил как кубометр
дерева.]],

	simplifications = [[
1. Мир подставной: ноды и метки клея живут в таблице, а не на карте. Для
   обхода и выделения этого довольно — они работают ровно с этими двумя
   вопросами: что за нода и склеена ли она.
2. Проверяется геометрия выделения, а не то, как оно выглядит: рамка рисуется
   частицами, и без клиента о ней сказать нечего.]],

	references = { R.mit_16_07_l26 },

	params = {
		radius = { value = 5, note = "радиус испытательной сферы, блоков" },
	},

	run = function(P, ctx)
		local suite = check.new("соответствие: сборка")

		local previous_core = rawget(_G, "core")

		_G.core = engine_stub()

		local loaded, reason = mod.load({
			"api/registry.lua", "api/geometry.lua", "api/scan.lua",
			"api/selection.lua",
		})

		if not loaded then
			_G.core = previous_core

			print("Мод недоступен: " .. tostring(reason))

			suite:is_true("мод загружается", false,
				"без файлов мода сравнивать нечего; путь задаётся переменной "
				.. "окружения AXIS_MOD_PATH")

			return suite
		end

		print("Мод найден: " .. mod.path())

		-- Метки клея живут в метаданных ноды, которых у подставного мира нет
		loaded.is_bonded = function(pos)
			return world.bonded[cell(pos)] == true
		end

		local function place(cells, name)
			world.nodes, world.bonded = {}, {}

			for _, at in ipairs(cells) do
				local key = cell(at)

				world.nodes[key] = name or "axis_contraption:envelope"
				world.bonded[key] = true
			end
		end

		------------------------------------------------------------------
		-- Формы, которые раньше разваливались
		------------------------------------------------------------------
		local function sphere(radius)
			local cells = {}
			local span = math.ceil(radius) + 1

			for x = -span, span do
				for y = -span, span do
					for z = -span, span do
						local away = math.sqrt(x * x + y * y + z * z)

						if math.abs(away - radius) <= 0.5 then
							cells[#cells + 1] = { x = x, y = y, z = z }
						end
					end
				end
			end

			return cells
		end

		local function stairs(count)
			local cells = {}

			for index = 0, count - 1 do
				cells[#cells + 1] = { x = index, y = index, z = 0 }
			end

			return cells
		end

		local function corners(count)
			local cells = {}

			for index = 0, count - 1 do
				cells[#cells + 1] = { x = index, y = index, z = index }
			end

			return cells
		end

		print()
		print("Собирается ли постройка в одно целое:")
		print(text.row {
			{ "форма", 34 }, { "блоков", 10 }, { "собрано", 10 },
		})

		local whole = true

		for _, case in ipairs({
			{ "лестница по ребру", stairs(6) },
			{ "цепочка по углам", corners(5) },
			{ "сфера радиуса 3", sphere(3) },
			{ ("сфера радиуса %d"):format(P.radius), sphere(P.radius) },
		}) do
			local name, cells = case[1], case[2]

			place(cells)

			local collected = mod.call(loaded, loaded.collect, cells[1])

			if #collected ~= #cells then
				whole = false
			end

			print(text.row {
				{ name, 34 },
				{ ("%d"):format(#cells), 10 },
				{ ("%d"):format(#collected), 10 },
			})
		end

		------------------------------------------------------------------
		-- Обход не выходит за пределы склеенного
		------------------------------------------------------------------
		local ball = sphere(3)

		place(ball)

		-- Рядом стоит такой же блок, но не намазанный
		world.nodes["9:9:9"] = "axis_contraption:envelope"

		local guarded = mod.call(loaded, loaded.collect, ball[1])

		print()
		print(("Несклеенный блок рядом: собрано %d из %d — не захвачен")
			:format(#guarded, #ball))

		------------------------------------------------------------------
		-- Выделение коробкой
		------------------------------------------------------------------
		local function size(first, second)
			return mod.call(loaded, loaded.selection_size, first, second)
		end

		print()
		print("Сколько блоков берёт клей между двумя углами:")
		print(text.row {
			{ "от", 18 }, { "до", 18 }, { "блоков", 10 }, { "должно", 10 },
		})

		local boxes = {
			{ { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, 1 },
			{ { x = 0, y = 0, z = 0 }, { x = 4, y = 0, z = 0 }, 5 },
			{ { x = 0, y = 0, z = 0 }, { x = 2, y = 0, z = 2 }, 9 },
			{ { x = 0, y = 0, z = 0 }, { x = 4, y = 4, z = 4 }, 125 },
			{ { x = -2, y = -2, z = -2 }, { x = 2, y = 2, z = 2 }, 125 },
		}

		local box_error = 0

		for _, case in ipairs(boxes) do
			local first, second, want = case[1], case[2], case[3]
			local got = size(first, second)

			box_error = math.max(box_error, math.abs(got - want))

			print(text.row {
				{ ("(%d, %d, %d)"):format(first.x, first.y, first.z), 18 },
				{ ("(%d, %d, %d)"):format(second.x, second.y, second.z), 18 },
				{ ("%d"):format(got), 10 },
				{ ("%d"):format(want), 10 },
			})
		end

		-- Порядок углов не важен
		local forward = size({ x = 0, y = 0, z = 0 }, { x = 4, y = 4, z = 4 })
		local backward = size({ x = 4, y = 4, z = 4 }, { x = 0, y = 0, z = 0 })

		-- Границы нормализуются
		local low, high = mod.call(loaded, loaded.selection_bounds,
			{ x = 5, y = -3, z = 2 }, { x = 1, y = 4, z = -6 })

		local normalised = low.x == 1 and low.y == -3 and low.z == -6
			and high.x == 5 and high.y == 4 and high.z == 2

		-- Оболочка дирижабля должна влезать в предел
		local envelope_box = size({ x = 0, y = 0, z = 0 },
			{ x = 10, y = 10, z = 10 })

		------------------------------------------------------------------
		-- Габариты деталей
		------------------------------------------------------------------
		print()
		print("Коллизия детали на конструкции:")
		print(text.row {
			{ "нода", 26 }, { "коробка", 34 },
		})

		local boxes_by_node = {}

		for _, name in ipairs({ "mcl_fences:fence", "mcl_stairs:slab",
				"mcl_stairs:stair", "mcl_core:stone", "нет:такой" }) do
			local box = mod.call(loaded, loaded.node_collision_box, name)

			boxes_by_node[name] = box

			print(text.row {
				{ name, 26 },
				{ ("%.3f %.3f %.3f  %.3f %.3f %.3f"):format(box[1], box[2],
					box[3], box[4], box[5], box[6]), 34 },
			})
		end

		local fence = boxes_by_node["mcl_fences:fence"]
		local slab = boxes_by_node["mcl_stairs:slab"]
		local stone = boxes_by_node["mcl_core:stone"]

		_G.core = previous_core

		------------------------------------------------------------------
		suite:is_true("постройка собирается целиком, чем бы блоки ни касались",
			whole,
			"лестница по ребру, цепочка по углам и сферы обязаны собираться в "
			.. "одну конструкцию. Пока обход шёл по граням, круглый шар "
			.. "разваливался на десяток кусков, и собрать его было нельзя")

		suite:close("обход не выходит за пределы склеенного",
			#guarded, #ball, 1e-12,
			"рядом стоит такой же блок, но не намазанный клеем. Захвати его "
			.. "обход — расширение соседства перестало бы быть безопасным, и "
			.. "один клик утягивал бы половину карты")

		suite:close("клей берёт коробку между углами, а не линию",
			box_error, 0, 1e-12,
			"объём коробки считается перемножением сторон; каждый угол "
			.. "включается. Диагональ 0,0,0 — 2,0,2 обязана дать квадрат из "
			.. "девяти, а не три блока по прямой")

		suite:close("порядок углов не важен",
			backward, forward, 1e-12,
			"границы нормализуются, поэтому выделять можно в любую сторону")

		suite:is_true("границы приводятся к минимуму и максимуму",
			normalised,
			"из перепутанных углов (5,-3,2) и (1,4,-6) обязаны получиться "
			.. "углы (1,-3,-6) и (5,4,2)")

		suite:is_true("оболочка дирижабля влезает в предел выделения",
			envelope_box <= loaded.MAX_SELECTION,
			("куб 11x11x11 — это %d блоков при пределе %d"):format(envelope_box,
				loaded.MAX_SELECTION))

		suite:is_true("забор не получает коллизию в целый блок",
			fence[1] > -0.5 and fence[4] < 0.5 and fence[3] > -0.5
				and fence[6] < 0.5,
			"у забора коробка вида «connected», и раньше она не разбиралась "
			.. "вовсе — бралась заглушка в целый куб. Забор загораживал палубу, "
			.. "хотя стоя на земле он тонкий")

		suite:close("плита остаётся половиной блока",
			slab[5], 0, 1e-12,
			"обычная коробка «fixed» разбиралась и раньше; проверка сторожит, "
			.. "что разбор не сломался заодно с новым случаем")

		suite:close("обычный блок занимает весь куб",
			stone[5], 0.5, 1e-12,
			"у ноды без коробки габариты равны кубу — иначе игрок проваливался "
			.. "бы сквозь палубу")

		suite:close("незнакомая нода считается целым блоком",
			boxes_by_node["нет:такой"][5], 0.5, 1e-12,
			"осторожная догадка: лучше сделать деталь плотнее, чем позволить "
			.. "сквозь неё падать")

		return suite
	end,
}
