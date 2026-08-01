-- the Axis · physics lab · соответствие 07
-- Шкала масс: выполняется настоящий api/mass.lua.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local mod = require("parity.mod")
local check = require("lab.check")
local text = require("lab.text")
local C = require("lab.constants")
local R = require("lab.references")

-- Справочные плотности материалов, кг/м^3. Числа общеизвестные: сухая сосна
-- 500, гранит 2700, железо 7870, золото 19300.
local MATERIALS = {
	{ "шерсть, ткань", 100 },
	{ "листва", 150 },
	{ "снег", 400 },
	{ "сосна сухая", 500 },
	{ "лёд", 917 },
	{ "вода", 1000 },
	{ "земля, песок", 1500 },
	{ "кирпич", 1900 },
	{ "бетон", 2400 },
	{ "стекло", 2500 },
	{ "обсидиан", 2600 },
	{ "гранит", 2700 },
	{ "алмаз", 3500 },
	{ "железо", 7870 },
	{ "медь", 8960 },
	{ "золото", 19300 },
}

-- Детали мода: масса задана прямо, по плотности авиационной конструкции
local PART_MASSES = {
	{ "panel", "Панель обшивки" },
	{ "wing", "Крыло" },
	{ "frame", "Каркас" },
	{ "seat", "Сиденье" },
	{ "wheel", "Колесо" },
	{ "engine", "Двигатель" },
}

return experiment.define {
	id = "П7",
	name = "parity_mass",
	title = "Соответствие: шкала масс",

	question = [[
Откуда мод берёт вес блока — из свойств материала или из головы?

До этой итерации веса стояли списком: камень 7, дерево 3, земля 4. Числа
работали, но обосновать их было нечем, и добавить новый материал можно было
только на глаз.]],

	model = [[
Масса выводится из справочной плотности материала:

    масса = DENSITY_SCALE * sqrt(плотность)

Масштаб привязан к одной точке: сухая сосна, 500 кг/м^3, весит 3 единицы,
откуда DENSITY_SCALE = 3/sqrt(500) = 0.13416.

ПОЧЕМУ КОРЕНЬ. Настоящие плотности отличаются в 193 раза: от шерсти в
100 кг/м^3 до золота в 19300. При прямом переводе золотой блок весил бы 116
единиц против трёх у дерева, и всё тяжелее камня стало бы неподъёмным.
Корень сжимает разброс до 13.9, сохраняя порядок.

Это игровое упрощение, и цена его считается здесь численно: перевод в
килограммы (lab/constants.lua → mass_unit_density) точен только в точке
калибровки, а к краям шкалы всё сильнее щадит игрока.

ЧТО ПРОВЕРЯЕТСЯ:
  * формула воспроизводится модом на всём списке материалов;
  * шкала монотонна: плотнее материал — тяжелее блок;
  * детали мода легче любого природного блока, потому что они не сплошные, а
    ферма с обшивкой;
  * машину хватает поднять не только саму себя, но и обшивку.]],

	simplifications = [[
1. Материал определяется по имени ноды и по копательной группе. Для блока из
   чужого мода с непривычным именем останется догадка по группе, а без неё —
   значение по умолчанию.
2. Внутри группы все материалы считаются одинаковыми: любая нода, копаемая
   киркой, идёт как гранит. Различить руду и мрамор мод не может и не
   пытается.
3. Форма ноды учитывается только объёмом (плита весит вдвое меньше куба).
   Полая внутри постройка снаружи выглядит как сплошной блок.]],

	references = { R.nasa_drag_equation },

	params = {
		fuselage = { value = 7, note = "длина фюзеляжа испытательной машины, блоков" },
		span = { value = 3, note = "размах каждого крыла, блоков" },
		margin = { value = 1.25, note = "запас V_max/V_срыв, при котором машина ещё летает" },
	},

	run = function(P, ctx)
		local suite = check.new("соответствие: шкала масс")

		local loaded, reason = mod.load({
			"api/registry.lua",
			"api/smoothing.lua",
			"api/inertia.lua",
			"api/drag.lua",
			"api/lift.lua",
			"api/envelope.lua",
			"api/pointing.lua",
			"api/mass.lua",
			"api/structure.lua",
			"behaviours/air.lua",
		}, {
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
		-- Масштаб шкалы читается из исходника
		------------------------------------------------------------------
		local mass_source = mod.source("api/mass.lua") or ""
		local calibration_mass = tonumber(
			mass_source:match("local DENSITY_SCALE = ([%d%.]+) / math%.sqrt"))
		local calibration_density = tonumber(
			mass_source:match("local DENSITY_SCALE = [%d%.]+ / math%.sqrt%((%d+)%)"))

		local scale = (calibration_mass and calibration_density)
			and calibration_mass / math.sqrt(calibration_density) or 0

		print()
		print(("Калибровка из api/mass.lua: %.0f кг/м^3 = %.1f единицы, "
			.. "масштаб %.5f"):format(calibration_density or 0,
			calibration_mass or 0, scale))

		------------------------------------------------------------------
		-- 1. Формула против мода
		------------------------------------------------------------------
		local unit_density = C.value("mass_unit_density")

		print()
		print("Масса блока по плотности материала:")
		print(text.row {
			{ "материал", 20 }, { "кг/м^3", 10 }, { "мод", 8 },
			{ "формула", 10 }, { "линейно", 10 }, { "во сколько щадит", 18 },
		})

		local formula_error = 0
		local monotone = true
		local previous_mass, previous_density = -1, -1
		local worst_mercy, worst_material = 0, ""

		for _, entry in ipairs(MATERIALS) do
			local name, density = entry[1], entry[2]

			local from_mod = mod.call(loaded, loaded.mass_from_density, density)
			local rounded = math.max(0.5,
				math.floor(scale * math.sqrt(density) * 2 + 0.5) / 2)

			formula_error = math.max(formula_error, math.abs(from_mod - rounded))

			if density > previous_density and from_mod < previous_mass then
				monotone = false
			end

			previous_mass, previous_density = from_mod, density

			-- Во сколько раз игра щадит по сравнению с честным переводом
			local honest = density / unit_density
			local mercy = honest / from_mod

			if mercy > worst_mercy then
				worst_mercy, worst_material = mercy, name
			end

			print(text.row {
				{ name, 20 },
				{ ("%d"):format(density), 10 },
				{ ("%.1f"):format(from_mod), 8 },
				{ ("%.2f"):format(scale * math.sqrt(density)), 10 },
				{ ("%.1f"):format(honest), 10 },
				{ ("%.2f"):format(mercy), 18 },
			})
		end

		print()
		print(("Сильнее всего шкала щадит %s: в %.1f раза против честного "
			.. "перевода."):format(worst_material, worst_mercy))
		print("В точке калибровки щадить нечего — там перевод точен.")

		------------------------------------------------------------------
		-- 2. Детали мода против природных блоков
		------------------------------------------------------------------
		local basic = mod.source("parts/basic.lua") or ""
		local aircraft = mod.source("parts/aircraft.lua") or ""
		local sources = basic .. "\n" .. aircraft

		print()
		print("Детали мода: масса задана прямо, по плотности конструкции")
		print(text.row {
			{ "деталь", 22 }, { "масса", 10 }, { "кг/м^3", 12 },
		})

		local heaviest_part = 0
		local part_values = {}

		for _, entry in ipairs(PART_MASSES) do
			local key, label = entry[1], entry[2]
			local declared = tonumber(sources:match('register_part%("' .. key
				.. '".-mass = ([%d%.]+)'))

			if declared then
				part_values[key] = declared
				heaviest_part = math.max(heaviest_part, declared)

				print(text.row {
					{ label, 22 },
					{ ("%.2f"):format(declared), 10 },
					{ ("%.0f"):format(declared * unit_density), 12 },
				})
			end
		end

		-- Каркас и обшивка обязаны укладываться в плотность настоящего
		-- самолётного набора: 50...100 кг/м^3
		local frame_density = (part_values.frame or 0) * unit_density
		local panel_density = (part_values.panel or 0) * unit_density

		local lightest_natural = math.huge

		for _, entry in ipairs(MATERIALS) do
			lightest_natural = math.min(lightest_natural,
				mod.call(loaded, loaded.mass_from_density, entry[2]))
		end

		print()
		print(("Каркас %.0f кг/м^3 — настоящий самолётный набор даёт 50...100.")
			:format(frame_density))
		print(("Самый лёгкий природный блок весит %.1f, самая тяжёлая деталь "
			.. "мода %.1f."):format(lightest_natural, heaviest_part))

		------------------------------------------------------------------
		-- 3. Бюджет обшивки
		------------------------------------------------------------------
		local function aircraft_parts(options)
			local parts = {}
			local fuselage = options.fuselage
			local offset = (fuselage - 1) / 2

			for index = 0, fuselage - 1 do
				parts[#parts + 1] = { name = "axis_contraption:frame",
					position = { x = 0, y = 0, z = index - offset } }
			end

			parts[#parts + 1] = { name = "axis_contraption:seat",
				position = { x = 0, y = 1, z = 0 } }
			parts[#parts + 1] = { name = "axis_contraption:engine",
				position = { x = 0, y = 0, z = offset + 1 } }

			for index = 1, options.span do
				parts[#parts + 1] = { name = "axis_contraption:wing",
					position = { x = -index, y = 0, z = -1 } }
				parts[#parts + 1] = { name = "axis_contraption:wing",
					position = { x = index, y = 0, z = -1 } }
			end

			return parts
		end

		-- Детали объявляются с теми массами, что стоят в исходнике
		for _, entry in ipairs(PART_MASSES) do
			local key = entry[1]
			local role = (key == "wing" and "wing")
				or (key == "engine" and "engine")
				or (key == "seat" and "seat")
				or (key == "wheel" and "wheel") or "structure"

			loaded.registered_parts["axis_contraption:" .. key] = {
				role = role, mass = part_values[key] or 1,
			}
		end

		local rig = {
			parts = aircraft_parts { fuselage = P.fuselage, span = P.span },
			forward = { x = 0, z = 1 },
			velocity = { x = 0, y = 0, z = 0 },
			yaw = 0, pitch = 0, roll = 0,
			pitch_rate = 0, roll_rate = 0,
			on_ground = false,
		}

		mod.call(loaded, loaded.refresh, rig)

		local air_source = mod.source("behaviours/air.lua") or ""

		local function constant(pattern, radians)
			local value = tonumber(air_source:match(pattern)) or 0

			return radians and math.rad(value) or value
		end

		local GRAVITY = constant("local GRAVITY = ([%d%.]+)")
		local AIR_DENSITY = constant("local AIR_DENSITY = ([%d%.]+)")
		local CD_BLUFF = constant("local CD_BLUFF = ([%d%.]+)")
		local THRUST_PER_ENGINE = constant("local THRUST_PER_ENGINE = ([%d%.]+)")
		local WING_LIFT = tonumber((mod.source("api/lift.lua") or "")
			:match("contraption%.WING_LIFT = ([%d%.]+)")) or 0

		local cd_body = mod.call(loaded, loaded.body_drag_coefficient,
			rig.body_length, rig.frontal_area, CD_BLUFF)

		local top = math.sqrt(rig.counts.engine * THRUST_PER_ENGINE
			/ (0.5 * AIR_DENSITY * cd_body * rig.frontal_area))

		--- Сколько блоков данного веса машина поднимет сверх себя.
		--- Скорость, на которой крыло несёт заданный вес: сила линейна по
		--- скорости, поэтому она находится делением, а не корнем.
		local function carry_speed(mass)
			return mass * GRAVITY / (WING_LIFT * AIR_DENSITY * rig.wing_area)
		end

		local function budget(per_block)
			local blocks = 0

			while blocks < 500 do
				local mass = rig.mass + (blocks + 1) * per_block

				if top / carry_speed(mass) < P.margin then
					break
				end

				blocks = blocks + 1
			end

			return blocks
		end

		print()
		print(("Испытательная машина: масса %.2f, крыло %d м^2, потолок %.1f м/с")
			:format(rig.mass, rig.wing_area, top))
		print(("Сколько блоков она поднимет сверх себя при запасе %.2f:")
			:format(P.margin))
		print(text.row {
			{ "груз", 24 }, { "масса блока", 14 }, { "блоков", 10 },
		})

		local panel_budget = budget(part_values.panel or 0.25)

		-- Сколько панелей нужно, чтобы обшить фюзеляж со всех сторон: четыре
		-- грани по всей длине плюс два торца. Крылья обшивать нечем и незачем
		-- — они сами поверхность.
		local surface = 4 * P.fuselage + 2

		for _, entry in ipairs({
			{ "панель обшивки", part_values.panel or 0.25 },
			{ "шерсть", mod.call(loaded, loaded.mass_from_density, 100) },
			{ "доски", mod.call(loaded, loaded.mass_from_density, 500) },
			{ "земля", mod.call(loaded, loaded.mass_from_density, 1500) },
			{ "камень", mod.call(loaded, loaded.mass_from_density, 2700) },
		}) do
			print(text.row {
				{ entry[1], 24 },
				{ ("%.1f"):format(entry[2]), 14 },
				{ ("%d"):format(budget(entry[2])), 10 },
			})
		end

		print()
		print(("Обшить фюзеляж со всех сторон — %d панелей (4 грани по длине "
			.. "плюс два торца); бюджет %d."):format(surface, panel_budget))
		print("До этой итерации машина поднимала десяток панелей и ни одного")
		print("камня: летать приходилось на голом каркасе.")

		------------------------------------------------------------------
		-- 4. Область внедрения
		------------------------------------------------------------------
		local has_density = mass_source:find("DENSITY_SCALE", 1, true) ~= nil
		local has_table = mass_source:find("base = %d") ~= nil

		print()
		print("Область внедрения:")
		print(("  масса выводится из плотности: %s")
			:format(has_density and "да" or "НЕТ"))
		print(("  прежний список весов на глаз: %s")
			:format(has_table and "ОСТАЛСЯ" or "нет"))
		print()
		print("Очередь: киля и путевой устойчивости у постройки по-прежнему нет")
		print("(эксперимент 09). Столкновения решаются обнулением скорости по")
		print("оси, а не импульсом (эксперимент 15).")

		------------------------------------------------------------------
		suite:close("масса совпадает с формулой по плотности",
			formula_error, 0, 1e-12,
			"мод и проверка считают одно выражение DENSITY_SCALE*sqrt(rho) с "
			.. "округлением до половины единицы; масштаб прочитан из "
			.. "исходника мода, а не записан здесь копией")

		suite:is_true("шкала монотонна по плотности",
			monotone,
			"плотнее материал — тяжелее блок. Немонотонность означала бы, что "
			.. "где-то выгодно строить из более плотного материала, и это "
			.. "сразу читалось бы как ошибка")

		suite:close("в точке калибровки перевод в килограммы точен",
			mod.call(loaded, loaded.mass_from_density, calibration_density)
				* unit_density, calibration_density, 1e-9,
			"masса * mass_unit_density обязана дать ровно ту плотность, по "
			.. "которой шкала калибрована. Это единственная точка, где "
			.. "перевод честен, и именно поэтому она названа явно")

		suite:is_true("к краям шкалы игра щадит, и это измерено",
			worst_mercy > 3,
			"сжатие корнем не бесплатно: самый плотный материал в игре легче "
			.. "честного перевода в "
			.. ("%.1f"):format(worst_mercy) .. " раза. Проверка не требует "
			.. "малости этого числа — она требует, чтобы оно было напечатано, "
			.. "а не спрятано")

		suite:is_true("каркас укладывается в плотность самолётного набора",
			frame_density >= 50 and frame_density <= 100,
			"настоящая ферма с обшивкой даёт 50...100 кг/м^3 по занимаемому "
			.. "объёму; здесь " .. ("%.0f"):format(frame_density)
			.. ". Выше — машина возит лишний вес без причины, ниже — "
			.. "конструкция становится невесомой")

		suite:is_true("обшивка легче каркаса",
			panel_density < frame_density,
			"лист по нервюрам не может весить больше несущей фермы: "
			.. ("%.0f против %.0f кг/м^3"):format(panel_density, frame_density))

		suite:is_true("детали мода легче любого природного блока",
			heaviest_part <= 3 and (part_values.frame or 1) < lightest_natural,
			"каркас и обшивка — не сплошные бруски, а конструкция. Тяжелее "
			.. "их только двигатель, и он тяжёл по делу: это мотор с винтом. "
			.. ("Каркас %.2f против самого лёгкого природного %.1f")
				:format(part_values.frame or 0, lightest_natural))

		suite:is_true("машину хватает поднять вместе с обшивкой",
			panel_budget >= surface,
			"обшить фюзеляж со всех сторон — четыре грани по длине плюс два "
			.. "торца, то есть " .. tostring(surface)
			.. " панелей; бюджет " .. tostring(panel_budget)
			.. ". Если бы бюджета не хватало, летать пришлось бы на голом "
			.. "каркасе, а всякая отделка отнимала бы способность взлететь")

		suite:is_true("масса выводится из плотности, а не из списка",
			has_density and not has_table,
			"поиск по исходнику api/mass.lua: должен появиться DENSITY_SCALE "
			.. "и исчезнуть прежний список весов, расставленных на глаз")

		return suite
	end,
}
