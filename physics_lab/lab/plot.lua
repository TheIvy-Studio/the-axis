-- the Axis · physics lab
-- Графики без зависимостей: ASCII в терминал, SVG на диск, CSV для внешних
-- инструментов.
--
-- Ни numpy, ни matplotlib в системе нет, и тянуть их ради двадцати графиков
-- незачем. SVG — текстовый формат, он пишется из Lua в двадцать строк и
-- открывается любым браузером; вектор к тому же лучше растра для отчётов.

local text = require("lab.text")

local M = {}

--------------------------------------------------------------------------------
-- ASCII
--------------------------------------------------------------------------------

--- Рисует одну или несколько кривых прямо в терминале.
---
--- @param series список { label = "...", mark = "*", points = { {x, y}, ... } }
--- @param options.width, options.height, options.title, options.xlabel, options.ylabel
function M.ascii(series, options)
	options = options or {}

	local width = options.width or 72
	local height = options.height or 20

	local min_x, max_x = math.huge, -math.huge
	local min_y, max_y = math.huge, -math.huge

	for _, line in ipairs(series) do
		for _, point in ipairs(line.points) do
			min_x = math.min(min_x, point[1])
			max_x = math.max(max_x, point[1])
			min_y = math.min(min_y, point[2])
			max_y = math.max(max_y, point[2])
		end
	end

	if min_x == math.huge then
		return "(нет данных)"
	end

	-- Вырожденные диапазоны расширяются, иначе деление на ноль
	if max_x - min_x < 1e-12 then max_x = min_x + 1 end
	if max_y - min_y < 1e-12 then
		local pad = math.max(math.abs(min_y) * 0.1, 1)
		min_y, max_y = min_y - pad, max_y + pad
	end

	local canvas = {}

	for row = 1, height do
		canvas[row] = {}

		for column = 1, width do
			canvas[row][column] = " "
		end
	end

	-- Ось нуля, если она попадает в диапазон
	if min_y < 0 and max_y > 0 then
		local zero = math.floor((max_y - 0) / (max_y - min_y) * (height - 1)) + 1

		for column = 1, width do
			canvas[zero][column] = "."
		end
	end

	for _, line in ipairs(series) do
		local mark = line.mark or "*"

		for _, point in ipairs(line.points) do
			local column = math.floor((point[1] - min_x) / (max_x - min_x)
				* (width - 1)) + 1
			local row = math.floor((max_y - point[2]) / (max_y - min_y)
				* (height - 1)) + 1

			if column >= 1 and column <= width and row >= 1 and row <= height then
				canvas[row][column] = mark
			end
		end
	end

	local out = {}

	if options.title then
		out[#out + 1] = options.title
	end

	local label_width = 11

	for row = 1, height do
		local value = max_y - (row - 1) / (height - 1) * (max_y - min_y)
		local prefix = (row == 1 or row == height
				or row == math.floor((height + 1) / 2))
			and ("%10.4g "):format(value)
			or string.rep(" ", label_width)

		out[#out + 1] = prefix .. "|" .. table.concat(canvas[row])
	end

	out[#out + 1] = string.rep(" ", label_width) .. "+"
		.. string.rep("-", width)

	-- Подписи концов оси X. Звёздочную ширину ("%-*s") LuaJIT не понимает,
	-- поэтому промежуток считается вручную.
	local left_label = ("%.6g"):format(min_x)
	local right_label = ("%.6g"):format(max_x)
	local gap = math.max(1, width - #left_label - #right_label)

	out[#out + 1] = string.rep(" ", label_width + 1) .. left_label
		.. string.rep(" ", gap) .. right_label

	local legend = {}

	for _, line in ipairs(series) do
		legend[#legend + 1] = ("%s %s"):format(line.mark or "*", line.label)
	end

	if #legend > 0 then
		out[#out + 1] = string.rep(" ", label_width + 1)
			.. table.concat(legend, "   ")
	end

	if options.xlabel or options.ylabel then
		out[#out + 1] = ("%sx: %s    y: %s")
			:format(string.rep(" ", label_width + 1),
				options.xlabel or "?", options.ylabel or "?")
	end

	return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- CSV
--------------------------------------------------------------------------------

function M.csv(path, headers, rows)
	local file, message = io.open(path, "w")

	if not file then
		return nil, message
	end

	file:write(table.concat(headers, ","), "\n")

	for _, row in ipairs(rows) do
		local cells = {}

		for index, cell in ipairs(row) do
			cells[index] = type(cell) == "number"
				and ("%.10g"):format(cell) or tostring(cell)
		end

		file:write(table.concat(cells, ","), "\n")
	end

	file:close()

	return path
end

--------------------------------------------------------------------------------
-- SVG
--------------------------------------------------------------------------------

local PALETTE = {
	"#4FA3D1", "#E0793B", "#61C08B", "#C86B9E", "#D6C04F", "#9C7BD6",
}

--- Пишет линейный график в SVG. Формат текстовый, зависимостей нет.
function M.svg(path, series, options)
	options = options or {}

	local width = options.width or 900
	local height = options.height or 480
	local pad_left, pad_right = 78, 24
	local pad_top, pad_bottom = 48, 56

	local min_x, max_x = math.huge, -math.huge
	local min_y, max_y = math.huge, -math.huge

	for _, line in ipairs(series) do
		for _, point in ipairs(line.points) do
			min_x = math.min(min_x, point[1])
			max_x = math.max(max_x, point[1])
			min_y = math.min(min_y, point[2])
			max_y = math.max(max_y, point[2])
		end
	end

	if min_x == math.huge then
		return nil, "нет данных"
	end

	if max_x - min_x < 1e-12 then max_x = min_x + 1 end
	if max_y - min_y < 1e-12 then
		local pad = math.max(math.abs(min_y) * 0.1, 1)
		min_y, max_y = min_y - pad, max_y + pad
	end

	-- Небольшой отступ по вертикали, чтобы кривая не липла к рамке
	local margin = (max_y - min_y) * 0.05
	min_y, max_y = min_y - margin, max_y + margin

	local plot_width = width - pad_left - pad_right
	local plot_height = height - pad_top - pad_bottom

	local function screen_x(x)
		return pad_left + (x - min_x) / (max_x - min_x) * plot_width
	end

	local function screen_y(y)
		return pad_top + (max_y - y) / (max_y - min_y) * plot_height
	end

	local out = {}

	local function emit(text)
		out[#out + 1] = text
	end

	emit(('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
		.. 'viewBox="0 0 %d %d" font-family="monospace">')
		:format(width, height, width, height))
	emit('<rect width="100%" height="100%" fill="#14171c"/>')

	-- Сетка и подписи осей
	local ticks = 6

	for index = 0, ticks do
		local fraction = index / ticks

		local x = pad_left + fraction * plot_width
		local y = pad_top + fraction * plot_height

		emit(('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#2a2f38"/>')
			:format(x, pad_top, x, pad_top + plot_height))
		emit(('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#2a2f38"/>')
			:format(pad_left, y, pad_left + plot_width, y))

		emit(('<text x="%.2f" y="%.2f" fill="#8a93a3" font-size="11" '
			.. 'text-anchor="middle">%.4g</text>')
			:format(x, pad_top + plot_height + 18,
				min_x + fraction * (max_x - min_x)))
		emit(('<text x="%.2f" y="%.2f" fill="#8a93a3" font-size="11" '
			.. 'text-anchor="end">%.4g</text>')
			:format(pad_left - 8, y + 4, max_y - fraction * (max_y - min_y)))
	end

	-- Линия нуля
	if min_y < 0 and max_y > 0 then
		emit(('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" '
			.. 'stroke="#4a5262" stroke-dasharray="4 4"/>')
			:format(pad_left, screen_y(0), pad_left + plot_width, screen_y(0)))
	end

	for index, line in ipairs(series) do
		local colour = line.colour or PALETTE[(index - 1) % #PALETTE + 1]
		local parts = {}

		for point_index, point in ipairs(line.points) do
			parts[#parts + 1] = ("%s%.2f,%.2f")
				:format(point_index == 1 and "M" or "L",
					screen_x(point[1]), screen_y(point[2]))
		end

		emit(('<path d="%s" fill="none" stroke="%s" stroke-width="%s"%s/>')
			:format(table.concat(parts, " "), colour, line.thickness or "2",
				line.dashed and ' stroke-dasharray="6 4"' or ""))

		-- Легенда
		local legend_y = pad_top + 4 + (index - 1) * 18

		emit(('<rect x="%.2f" y="%.2f" width="22" height="3" fill="%s"/>')
			:format(pad_left + plot_width - 190, legend_y, colour))
		emit(('<text x="%.2f" y="%.2f" fill="#c8cede" font-size="12">%s</text>')
			:format(pad_left + plot_width - 162, legend_y + 6, line.label))
	end

	if options.title then
		emit(('<text x="%.2f" y="26" fill="#e6ebf5" font-size="15">%s</text>')
			:format(pad_left, options.title))
	end

	if options.xlabel then
		emit(('<text x="%.2f" y="%.2f" fill="#8a93a3" font-size="12" '
			.. 'text-anchor="middle">%s</text>')
			:format(pad_left + plot_width / 2, height - 12, options.xlabel))
	end

	if options.ylabel then
		emit(('<text transform="translate(16,%.2f) rotate(-90)" fill="#8a93a3" '
			.. 'font-size="12" text-anchor="middle">%s</text>')
			:format(pad_top + plot_height / 2, options.ylabel))
	end

	emit('</svg>')

	local file, message = io.open(path, "w")

	if not file then
		return nil, message
	end

	file:write(table.concat(out, "\n"))
	file:close()

	return path
end

--------------------------------------------------------------------------------
-- Прореживание
--------------------------------------------------------------------------------

--- Оставляет не больше `limit` точек. Нужно, чтобы SVG от симуляции на
--- 100000 шагов не весил мегабайты: глазу разница незаметна, а файл меньше
--- в сотни раз.
function M.thin(points, limit)
	limit = limit or 600

	if #points <= limit then
		return points
	end

	local out = {}
	local stride = #points / limit

	for index = 1, limit do
		out[index] = points[math.floor((index - 1) * stride) + 1]
	end

	out[#out + 1] = points[#points]

	return out
end

return M
