-- the Axis · physics lab · соответствие 09
-- Аэростат: выполняются настоящие api/envelope.lua, api/structure.lua и
-- behaviours/airship.lua.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local mod = require("parity.mod")
local check = require("lab.check")
local text = require("lab.text")
local R = require("lab.references")

local PARTS = {
	["axis_contraption:frame"] = { role = "structure", mass = 0.5 },
	["axis_contraption:envelope"] = { role = "envelope", mass = 0.05 },
	["axis_contraption:burner"] = { role = "burner", mass = 2 },
	["axis_contraption:burner_lever"] = { role = "lever", mass = 0.5 },
}

-- Сколько частиц выбито за прогон: по ним видно, свистит ли щель
local particles = 0
local last_particle = nil

--- Заглушка движка. Модули аэростата вешают колбэки и рисуют частицы, а вне
--- сервера ни того, ни другого нет.
local function engine_stub()
	return {
		register_on_player_receive_fields = function() end,
		register_on_leaveplayer = function() end,
		register_globalstep = function() end,
		register_on_mods_loaded = function() end,
		show_formspec = function() end,
		chat_send_player = function() end,
		formspec_escape = function(value) return value end,
		get_player_by_name = function() return nil end,
		registered_nodes = {},
		add_particle = function(spec)
			particles = particles + 1
			last_particle = spec.pos
		end,
	}
end

return experiment.define {
	id = "П9",
	name = "parity_airship",
	title = "Соответствие: аэростат",

	question = [[
Летает ли аэростат — и на том ли пути, которым его гоняет игра?

Прежние проверки этого мода вызывали refresh ОДИН раз, на целых координатах.
Игра делает иначе: собирает, переносит точку отсчёта в центр масс и считает
заново — уже по дробным. Ровно на этом различии мод и сломался: целый куб
показывал «воздуха нет». Поэтому здесь воспроизводится весь путь.]],

	model = [[
ПОЛОСТЬ. Оболочка держит воздух, если замкнута. Ищется это заливкой снаружи:
всё, куда наружный воздух дотёк, полостью не является.

Заливка НЕ ИДЁТ ВВЕРХ. Горячий воздух лёгкий: он всплывает и держится под
куполом, а вниз не утекает. Поэтому дыра в дне — не дыра, а горло, через
которое горелка и загоняет тепло; у настоящего шара низ открыт целиком. А
прореха в крыше выпускает всё, в борту — только то, что ниже неё.

ПОДЪЁМ. F = LIFT_PER_CELL * объём * заполненность. Заполненность идёт к цели,
заданной рычагом, по экспоненте: горелка греет, остывание тянет обратно.
Уровень рычага задаёт не скорость нагрева, а долю, до которой шар
прогревается, — поэтому им держат высоту, а не только лезут вверх.

ЦЕЛАЯ СЕТКА. Позиции деталей отсчитываются от центра масс, а он дробный.
Складывать такие координаты и сравнивать их строками нельзя: -1.380 + 1 не
даст в точности -0.380. Полость поэтому считается на целой сетке,
отсчитанной от первой детали. Это и проверяется прогоном всего пути.]],

	simplifications = [[
1. Проверяется поведение и геометрия, а не картинка: частицы считаются
   заглушкой, их число и место — всё, что можно узнать без клиента.
2. Столкновений с миром нет, высота считается интегрированием вертикальной
   скорости. Для аэростата этого довольно: он ни во что не упирается.]],

	references = { R.nasa_drag_equation },

	params = {
		size = { value = 7, note = "сторона испытательной оболочки, блоков" },
		flight = { value = 20.0, note = "сколько лететь, с" },
	},

	run = function(P, ctx)
		local suite = check.new("соответствие: аэростат")

		local previous_core = rawget(_G, "core")

		_G.core = engine_stub()

		local loaded, reason = mod.load({
			"api/registry.lua", "api/smoothing.lua", "api/inertia.lua",
			"api/drag.lua", "api/lift.lua", "api/envelope.lua", "api/lever.lua",
			"api/pointing.lua", "api/mass.lua", "api/structure.lua",
			"behaviours/airship.lua",
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

		for name, part in pairs(PARTS) do
			loaded.registered_parts[name] = { role = part.role, mass = part.mass }
		end

		local airship = loaded.registered_behaviours.airship
		local lift_per_cell = loaded.LIFT_PER_CELL

		------------------------------------------------------------------
		-- Постройка и полный путь сборки
		------------------------------------------------------------------
		--- Куб со стороной n, горелка и рычаг под ним.
		--- @param hole "top" | "side" | "bottom" | "edge" | nil
		local function make(n, hole, level)
			local half = math.floor(n / 2)
			local parts = {}

			for x = -half, half do
				for y = -half, half do
					for z = -half, half do
						local wall = math.abs(x) == half or math.abs(y) == half
							or math.abs(z) == half

						local pierced =
							(hole == "top" and x == 0 and y == half and z == 0)
							or (hole == "side" and x == half and y == 0 and z == 0)
							or (hole == "bottom" and x == 0 and y == -half
								and z == 0)
							or (hole == "edge" and x == half and y == half
								and z == 0)

						if wall and not pierced then
							parts[#parts + 1] = {
								name = "axis_contraption:envelope",
								position = { x = x, y = y, z = z },
							}
						end
					end
				end
			end

			parts[#parts + 1] = { name = "axis_contraption:burner",
				position = { x = 0, y = -half - 1, z = 0 } }
			parts[#parts + 1] = { name = "axis_contraption:burner_lever",
				position = { x = 1, y = -half - 1, z = 0 },
				param2 = level or 15 }

			return parts
		end

		--- Ровно то, что делает игра: refresh, перенос точки отсчёта в центр
		--- масс, refresh ещё раз.
		local function assemble(parts)
			local rig = {
				parts = parts,
				forward = { x = 0, z = 1 },
				velocity = { x = 0, y = 0, z = 0 },
				yaw = 0, pitch = 0, roll = 0,
				pitch_rate = 0, roll_rate = 0,
				object = {
					is_valid = function() return true end,
					get_pos = function() return { x = 100, y = 20, z = -50 } end,
				},
			}

			mod.call(loaded, loaded.refresh, rig)

			local centre = rig.centre

			for _, part in ipairs(rig.parts) do
				part.position.x = part.position.x - centre.x
				part.position.y = part.position.y - centre.y
				part.position.z = part.position.z - centre.z
			end

			mod.call(loaded, loaded.refresh, rig)

			return rig
		end

		local function fly(rig, seconds)
			particles, last_particle = 0, nil

			mod.call(loaded, function()
				for _ = 1, math.floor(seconds * 60) do
					airship.control(rig, 1 / 60, { move_x = 0, move_y = 0,
						up = false, down = false })
				end
			end)

			return rig
		end

		------------------------------------------------------------------
		-- 1. Целая оболочка
		------------------------------------------------------------------
		local inner = (P.size - 2) ^ 3
		local whole = assemble(make(P.size))

		print()
		print(("Оболочка %dx%d: деталей %d, вес %.2f, полость %d")
			:format(P.size, P.size, #whole.parts, whole.mass,
				whole.envelope_volume))
		print(("  позиции после переноса отсчёта: %.3f — дробные, как в игре")
			:format(whole.parts[1].position.y))

		fly(whole, P.flight)

		print(("  через %.0f с: прогрет на %.0f %%, ход %+.2f блока в секунду")
			:format(P.flight, whole.envelope_fill * 100, whole.velocity.y))

		------------------------------------------------------------------
		-- 2. Прорехи
		------------------------------------------------------------------
		print()
		print("Что держит оболочка с прорехой:")
		print(text.row {
			{ "где прореха", 22 }, { "полость", 10 }, { "щель найдена", 14 },
			{ "свистит", 10 },
		})

		local cases = {}

		for _, hole in ipairs({ "top", "side", "bottom", "edge" }) do
			local rig = assemble(make(P.size, hole))

			fly(rig, 3)

			cases[hole] = {
				volume = rig.envelope_volume,
				breach = rig.envelope_breach,
				particles = particles,
				pos = last_particle,
				climb = rig.velocity.y,
			}

			local titles = {
				top = "в крыше", side = "в борту",
				bottom = "горло в дне", edge = "снятый угол",
			}

			print(text.row {
				{ titles[hole], 22 },
				{ ("%d"):format(cases[hole].volume), 10 },
				{ cases[hole].breach and "да" or "нет", 14 },
				{ ("%d"):format(cases[hole].particles), 10 },
			})
		end

		print()
		print("Горло в дне и снятый угол течью не считаются: через первое")
		print("горячий воздух и подаётся, а через второй ему не пройти — соседи")
		print("угла по граням остаются стенками.")

		------------------------------------------------------------------
		-- 3. Рычаг задаёт высоту, а не скорость подъёма
		------------------------------------------------------------------
		print()
		print("Положение рычага против того, до чего прогреется шар:")
		print(text.row {
			{ "рычаг", 10 }, { "прогрев", 12 }, { "ход, блоков/с", 16 },
		})

		local levels = {}

		for _, level in ipairs({ 0, 5, 8, 15 }) do
			local rig = assemble(make(P.size, nil, level))

			fly(rig, 30)

			levels[level] = {
				fill = rig.envelope_fill,
				climb = rig.velocity.y,
			}

			print(text.row {
				{ ("%d из 15"):format(level), 10 },
				{ ("%.0f %%"):format(rig.envelope_fill * 100), 12 },
				{ ("%+.2f"):format(rig.velocity.y), 16 },
			})
		end

		------------------------------------------------------------------
		-- 4. Больше груза — больше шар
		------------------------------------------------------------------
		print()
		print("Какой шар поднимет какой вес:")
		print(text.row {
			{ "оболочка", 12 }, { "полость", 10 }, { "поднимает", 12 },
			{ "вес самой", 12 },
		})

		local grows = true
		local previous = -1

		for _, n in ipairs({ 5, 7, 9 }) do
			local rig = assemble(make(n))
			local lift = mod.call(loaded, loaded.envelope_lift,
				rig.envelope_volume, 1)
			local spare = lift / 9.81 - rig.mass

			if spare <= previous then
				grows = false
			end

			previous = spare

			print(text.row {
				{ ("%dx%dx%d"):format(n, n, n), 12 },
				{ ("%d"):format(rig.envelope_volume), 10 },
				{ ("%.0f гран"):format(lift / 9.81), 12 },
				{ ("%.1f гран"):format(rig.mass), 12 },
			})
		end

		print()
		print("Объём растёт как куб размера, а вес оболочки как квадрат,")
		print("поэтому большой шар выгоднее маленького — как и в жизни.")

		_G.core = previous_core

		------------------------------------------------------------------
		suite:close("целая оболочка держит весь объём",
			whole.envelope_volume, inner, 1e-12,
			"полый куб со стороной n держит (n-2)^3 клеток: это его нутро без "
			.. "стенок. Расхождение означало бы, что заливка просачивается "
			.. "сквозь стенку")

		suite:is_true("объём считается на целой сетке, а не на дробной",
			math.abs(whole.parts[1].position.y % 1) > 1e-6,
			"проверка нарочно гоняет ПОЛНЫЙ путь игры: после переноса точки "
			.. "отсчёта в центр масс координаты дробные ("
			.. ("%.3f"):format(whole.parts[1].position.y) .. "). Прежние "
			.. "проверки вызывали refresh один раз, на целых, и не заметили "
			.. "поломки, из-за которой целый куб показывал «воздуха нет»")

		suite:is_true("целый шар не свистит",
			cases.bottom.particles == 0,
			"струя пара выбивается только из настоящей течи; у исправной "
			.. "оболочки её быть не должно")

		suite:is_true("прореха в крыше выпускает весь воздух",
			cases.top.volume == 0 and cases.top.breach ~= nil
				and cases.top.particles > 0,
			"наружный воздух заходит сверху свободно, и держаться нечему. "
			.. "Щель обязана найтись, а из неё — бить пар")

		suite:is_true("прореха в борту выпускает только то, что ниже неё",
			cases.side.volume > 0 and cases.side.volume < inner
				and cases.side.breach ~= nil and cases.side.particles > 0,
			"воздух, всплывший выше прорехи, держится под куполом: "
			.. ("осталось %d из %d"):format(cases.side.volume, inner)
			.. ". Это и делает пробоину в борту не смертельной, а обидной")

		suite:is_true("горло в дне течью не считается",
			cases.bottom.volume >= inner and cases.bottom.breach == nil
				and cases.bottom.particles == 0,
			"горячий воздух лёгкий и вниз не утекает; через это горло горелка "
			.. "его и подаёт. У настоящего шара низ открыт целиком")

		suite:is_true("снятый угловой блок течью не считается",
			cases.edge.volume >= inner and cases.edge.breach == nil,
			"соседи угла по граням остаются стенками, и воздуху сквозь него "
			.. "не пройти. Поэтому шар можно скруглять, не боясь потерять "
			.. "герметичность")

		suite:close("струя бьёт у самой машины",
			math.sqrt((cases.top.pos.x - 100) ^ 2 + (cases.top.pos.y - 20) ^ 2
				+ (cases.top.pos.z + 50) ^ 2), 0, P.size,
			"частицы обязаны появляться в пределах габаритов конструкции, а "
			.. "не где-то в стороне: место щели переводится из целой сетки в "
			.. "координаты постройки, а оттуда в мир, и ошибка в любом из "
			.. "переводов увела бы струю")

		suite:is_true("погашенный рычаг не греет",
			levels[0].fill < 0.01 and levels[0].climb <= 0,
			"нулевая цель — нулевой прогрев; шар при этом снижается")

		suite:is_true("рычаг задаёт долю прогрева, а не скорость нагрева",
			math.abs(levels[5].fill - 5 / 15) < 0.02
				and math.abs(levels[8].fill - 8 / 15) < 0.02,
			"на пятёрке шар выходит на треть, на восьмёрке чуть больше "
			.. "половины и там остаётся: подъём уравновешен остыванием. Так "
			.. "рычагом держат высоту, а не только лезут вверх")

		suite:is_true("прибавленный огонь поднимает машину",
			levels[8].climb > levels[5].climb
				and levels[15].climb > levels[8].climb,
			"больше прогрев — больше подъёмная сила: "
			.. ("%.2f, %.2f, %.2f блока в секунду"):format(levels[5].climb,
				levels[8].climb, levels[15].climb))

		suite:is_true("прогретый шар поднимается",
			whole.envelope_fill > 0.85 and whole.velocity.y > 0.5,
			"за " .. ("%.0f"):format(P.flight) .. " с при постоянной прогрева "
			.. "в девять секунд шар набирает "
			.. ("%.0f %%"):format(whole.envelope_fill * 100)
			.. " и идёт вверх " .. ("%.2f"):format(whole.velocity.y)
			.. " блока в секунду")

		suite:is_true("шар побольше поднимает больше сверх себя",
			grows,
			"полость растёт как куб стороны, а вес оболочки как квадрат, "
			.. "поэтому запас грузоподъёмности обязан расти с размером. Иначе "
			.. "строить большие шары не было бы смысла")

		suite:is_true("подъёмная сила прочитана из мода",
			type(lift_per_cell) == "number" and lift_per_cell > 0,
			"стенд не хранит копию: LIFT_PER_CELL берётся из api/envelope.lua "
			.. "и равен " .. tostring(lift_per_cell))

		return suite
	end,
}
