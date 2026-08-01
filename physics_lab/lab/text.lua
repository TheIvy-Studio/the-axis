-- the Axis · physics lab
-- Выравнивание текста по ширине в символах, а не в байтах.
--
-- string.format("%-20s", ...) считает БАЙТЫ, а кириллица в UTF-8 занимает два
-- байта на букву. Из-за этого любая таблица с русскими подписями разъезжается.
-- Здесь ширина считается в кодовых точках.

local M = {}

--- Длина строки в символах UTF-8.
function M.length(text)
	local count = 0

	for _ in tostring(text):gmatch("[^\128-\191]") do
		count = count + 1
	end

	return count
end

--- Дополняет строку пробелами до нужной ширины.
--- @param align "left" (по умолчанию) или "right"
function M.pad(text, width, align)
	text = tostring(text)

	local padding = width - M.length(text)

	if padding <= 0 then
		return text
	end

	if align == "right" then
		return string.rep(" ", padding) .. text
	end

	return text .. string.rep(" ", padding)
end

--- Собирает строку таблицы: список пар { текст, ширина[, выравнивание] }.
function M.row(cells, separator)
	local parts = {}

	for index, cell in ipairs(cells) do
		parts[index] = M.pad(cell[1], cell[2], cell[3])
	end

	return table.concat(parts, separator or " ")
end

return M
