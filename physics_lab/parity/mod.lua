-- the Axis · physics lab · соответствие
-- Загрузчик настоящих файлов мода.
--
-- Проверки соответствия отличаются от экспериментов одним: они работают не с
-- моделью, а с ТЕМ САМЫМ кодом, который выполняется на сервере. Модель может
-- быть верна, а в моде стоять другая формула — именно это расхождение здесь и
-- ловится.
--
-- Файлы мода написаны в стиле dofile: они пишут в глобальную таблицу
-- contraption. Загрузчик подменяет её на чистую, выполняет нужные файлы и
-- возвращает результат, восстановив глобальное окружение.

local M = {}

--------------------------------------------------------------------------------
-- Поиск мода
--------------------------------------------------------------------------------

-- Список строится по шагам, а не литералом: os.getenv возвращает nil, когда
-- переменная не задана, а nil первым элементом таблицы обрывает ipairs на
-- первом же шаге — список молча оказался бы пустым.
local CANDIDATES = {}

do
	local override = os.getenv("AXIS_MOD_PATH")

	if override then
		CANDIDATES[#CANDIDATES + 1] = override
	end

	CANDIDATES[#CANDIDATES + 1] = "../mods/axis_contraption"
	CANDIDATES[#CANDIDATES + 1] = "mods/axis_contraption"
	CANDIDATES[#CANDIDATES + 1] = "../../mods/axis_contraption"
end

local function readable(path)
	local file = io.open(path, "r")

	if not file then
		return false
	end

	file:close()

	return true
end

--- Путь к моду или nil, если его нет рядом.
function M.path()
	for _, candidate in ipairs(CANDIDATES) do
		if candidate and readable(candidate .. "/init.lua") then
			return candidate
		end
	end

	return nil
end

function M.available()
	return M.path() ~= nil
end

--------------------------------------------------------------------------------
-- Загрузка
--------------------------------------------------------------------------------

--- Выполняет перечисленные файлы мода в чистом окружении.
---
--- @param files список путей относительно корня мода
--- @param stubs необязательные заготовки: что положить в contraption заранее
--- @return таблица contraption после выполнения, либо nil и причина
function M.load(files, stubs)
	local root = M.path()

	if not root then
		return nil, "мод axis_contraption не найден рядом с лабораторией"
	end

	local previous = rawget(_G, "contraption")
	local sandbox = {}

	for key, value in pairs(stubs or {}) do
		sandbox[key] = value
	end

	_G.contraption = sandbox

	local ok, message = pcall(function()
		for _, file in ipairs(files) do
			local chunk, load_error = loadfile(root .. "/" .. file)

			if not chunk then
				error(load_error, 0)
			end

			chunk()
		end
	end)

	_G.contraption = previous

	if not ok then
		return nil, message
	end

	return sandbox
end

--------------------------------------------------------------------------------
-- Вызов кода мода
--------------------------------------------------------------------------------

--- Выполняет функцию, временно установив таблицу мода в глобальное окружение.
---
--- Зачем это нужно. Функции поведений обращаются к глобальной contraption не
--- при загрузке, а в момент ВЫЗОВА: строка вида contraption.decay(...) внутри
--- control() ищет глобальную переменную каждый раз заново. Если снять
--- окружение сразу после чтения файлов, загрузка пройдёт, а первый же вызов
--- упадёт на попытке индексировать nil. Поэтому вызывать код мода нужно в том
--- же окружении, в котором он загружался.
function M.call(sandbox, fn, ...)
	local previous = rawget(_G, "contraption")

	_G.contraption = sandbox

	local results = { pcall(fn, ...) }

	_G.contraption = previous

	if not results[1] then
		error(results[2], 0)
	end

	-- Оператор and/or усекает список до одного значения, поэтому выбор
	-- распаковщика делается ОТДЕЛЬНО от самой распаковки. Прежняя запись
	-- table.unpack and table.unpack(...) or unpack(...) молча возвращала
	-- только первый результат, и функции мода с парой возвращаемых значений
	-- теряли второй.
	local unpacker = table.unpack or unpack

	return unpacker(results, 2)
end

--------------------------------------------------------------------------------
-- Чтение исходника
--------------------------------------------------------------------------------

--- Возвращает текст файла мода. Нужен для проверок на уровне исходного кода:
--- убедиться, что старая формула не осталась где-то ещё.
function M.source(file)
	local root = M.path()

	if not root then
		return nil
	end

	local handle = io.open(root .. "/" .. file, "r")

	if not handle then
		return nil
	end

	local text = handle:read("*a")

	handle:close()

	return text
end

--- Ищет образец во всех файлах мода. Возвращает список совпадений
--- { file, line, text }.
function M.grep(pattern, files)
	local found = {}

	for _, file in ipairs(files) do
		local text = M.source(file)

		if text then
			local number = 0

			for line in text:gmatch("[^\n]*") do
				number = number + 1

				if line:find(pattern) then
					found[#found + 1] = {
						file = file,
						line = number,
						text = line:gsub("^%s+", ""),
					}
				end
			end
		end
	end

	return found
end

return M
