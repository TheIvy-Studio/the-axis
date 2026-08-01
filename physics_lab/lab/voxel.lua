-- the Axis · physics lab
-- Сборка воксельных тел из блоков.
--
-- Мост между игрой и механикой: в Luanti конструкция — это список блоков с
-- целыми координатами, а механике нужны масса, центр масс и тензор инерции.
-- Здесь блоки превращаются в набор точечных масс, с которым уже работает
-- lab/rigid.lua.
--
-- Игровая «масса» блока в моде — безразмерное число от 1 до 20, взятое из
-- групп копания. Перевод в килограммы делается через
-- constants.GAME.mass_unit_density и объём блока (1 м^3), и это ЕДИНСТВЕННОЕ
-- место, где такой перевод происходит.

local vec3 = require("lab.vec3")
local rigid = require("lab.rigid")
local C = require("lab.constants")

local M = {}

--- Переводит игровую массу блока в килограммы.
---     m = игровая_масса * плотность_на_единицу * объём_блока
--- Единицы: [—]·[кг/м^3]·[м^3] = [кг]. Сходится.
function M.block_mass(game_mass)
	local size = C.value("node_size")

	return game_mass * C.value("mass_unit_density") * size ^ 3
end

--- Блок конструкции.
function M.block(x, y, z, game_mass, role)
	return {
		position = vec3.new(x, y, z),
		mass = M.block_mass(game_mass),
		game_mass = game_mass,
		role = role or "structure",
	}
end

--------------------------------------------------------------------------------
-- Готовые тела
--------------------------------------------------------------------------------

--- Прямой стержень из блоков вдоль оси X. Ровно тот случай, для которого
--- есть школьная формула I = M*L^2/12, поэтому он и служит эталоном.
function M.rod(count, game_mass)
	local blocks = {}
	local offset = (count - 1) / 2

	for index = 0, count - 1 do
		blocks[#blocks + 1] = M.block(index - offset, 0, 0, game_mass)
	end

	return blocks
end

--- Простой самолёт: фюзеляж вдоль X, крылья по Z, двигатель на носу.
---
--- @param options.fuselage длина фюзеляжа в блоках
--- @param options.span     размах КАЖДОГО крыла в блоках
--- @param options.left     сколько блоков в левом крыле (по умолчанию span)
--- @param options.right    сколько блоков в правом крыле
function M.aircraft(options)
	options = options or {}

	local fuselage = options.fuselage or 7
	local span = options.span or 3
	local left = options.left or span
	local right = options.right or span

	-- Игровые массы деталей совпадают с модом axis_contraption
	local frame_mass = options.frame_mass or 2
	local wing_mass = options.wing_mass or 1
	local engine_mass = options.engine_mass or 6
	local seat_mass = options.seat_mass or 2

	local blocks = {}
	local offset = (fuselage - 1) / 2

	for index = 0, fuselage - 1 do
		blocks[#blocks + 1] = M.block(index - offset, 0, 0, frame_mass, "structure")
	end

	-- Двигатель на носу (нос смотрит в +X)
	blocks[#blocks + 1] = M.block(offset + 1, 0, 0, engine_mass, "engine")

	-- Сиденье ближе к центру
	blocks[#blocks + 1] = M.block(0, 1, 0, seat_mass, "seat")

	-- Крылья, расположение вокруг X = wing_station
	local station = options.wing_station or 0

	for index = 1, left do
		blocks[#blocks + 1] = M.block(station, 0, -index, wing_mass, "wing")
	end

	for index = 1, right do
		blocks[#blocks + 1] = M.block(station, 0, index, wing_mass, "wing")
	end

	return blocks
end

--------------------------------------------------------------------------------
-- Сводка
--------------------------------------------------------------------------------

--- Считает всё, что нужно механике: массу, центр масс, тензор инерции
--- относительно центра масс, счётчики ролей, геометрический центр.
function M.describe(blocks, include_own_inertia)
	local centre, mass = rigid.centre_of_mass(blocks)

	local inertia = rigid.inertia_tensor(blocks, centre,
		include_own_inertia and C.value("node_size") or nil)

	local counts = {}
	local geometric = vec3.zero

	for _, block in ipairs(blocks) do
		counts[block.role] = (counts[block.role] or 0) + 1
		geometric = geometric + block.position
	end

	geometric = geometric / #blocks

	return {
		blocks = blocks,
		count = #blocks,
		mass = mass,
		centre = centre,
		geometric_centre = geometric,
		inertia = inertia,
		counts = counts,
	}
end

--- Площадь крыла в плане: число блоков-крыльев на площадь блока.
function M.wing_area(description)
	local size = C.value("node_size")

	return (description.counts.wing or 0) * size * size
end

--- Площадь миделя (поперечного сечения) по габаритам тела.
function M.frontal_area(blocks)
	local min_y, max_y = math.huge, -math.huge
	local min_z, max_z = math.huge, -math.huge

	for _, block in ipairs(blocks) do
		min_y = math.min(min_y, block.position.y)
		max_y = math.max(max_y, block.position.y)
		min_z = math.min(min_z, block.position.z)
		max_z = math.max(max_z, block.position.z)
	end

	local size = C.value("node_size")

	return (max_y - min_y + 1) * (max_z - min_z + 1) * size * size
end

return M
