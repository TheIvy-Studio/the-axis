-- the Axis · physics lab
-- Матрицы 3x3. Нужны ровно для одного: тензор инерции и его обращение.
--
-- Хранение построчное: m[i][j] — строка i, столбец j.

local vec3 = require("lab.vec3")

local M = {}
M.__index = M

local function new(rows)
	return setmetatable({
		{ rows[1][1], rows[1][2], rows[1][3] },
		{ rows[2][1], rows[2][2], rows[2][3] },
		{ rows[3][1], rows[3][2], rows[3][3] },
	}, M)
end

function M.identity()
	return new { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
end

function M.zero()
	return new { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
end

function M.diagonal(a, b, c)
	return new { { a, 0, 0 }, { 0, b, 0 }, { 0, 0, c } }
end

function M.__add(a, b)
	local out = M.zero()

	for i = 1, 3 do
		for j = 1, 3 do
			out[i][j] = a[i][j] + b[i][j]
		end
	end

	return out
end

function M.__sub(a, b)
	local out = M.zero()

	for i = 1, 3 do
		for j = 1, 3 do
			out[i][j] = a[i][j] - b[i][j]
		end
	end

	return out
end

function M.__mul(a, b)
	-- Число × матрица
	if type(a) == "number" then
		local out = M.zero()

		for i = 1, 3 do
			for j = 1, 3 do
				out[i][j] = a * b[i][j]
			end
		end

		return out
	end

	if type(b) == "number" then
		return M.__mul(b, a)
	end

	-- Матрица × вектор
	if b.x then
		return vec3.new(
			a[1][1] * b.x + a[1][2] * b.y + a[1][3] * b.z,
			a[2][1] * b.x + a[2][2] * b.y + a[2][3] * b.z,
			a[3][1] * b.x + a[3][2] * b.y + a[3][3] * b.z)
	end

	-- Матрица × матрица
	local out = M.zero()

	for i = 1, 3 do
		for j = 1, 3 do
			local sum = 0

			for k = 1, 3 do
				sum = sum + a[i][k] * b[k][j]
			end

			out[i][j] = sum
		end
	end

	return out
end

function M.transpose(a)
	return new {
		{ a[1][1], a[2][1], a[3][1] },
		{ a[1][2], a[2][2], a[3][2] },
		{ a[1][3], a[2][3], a[3][3] },
	}
end

function M.determinant(a)
	return a[1][1] * (a[2][2] * a[3][3] - a[2][3] * a[3][2])
		- a[1][2] * (a[2][1] * a[3][3] - a[2][3] * a[3][1])
		+ a[1][3] * (a[2][1] * a[3][2] - a[2][2] * a[3][1])
end

--- Обращение через присоединённую матрицу. Для 3x3 это дешевле и точнее
--- гауссова исключения, а вырожденный случай ловится явно: тензор инерции
--- вырожден только у тела нулевой массы или строго одномерного набора точек,
--- и это ошибка постановки задачи, а не ситуация, которую надо сглаживать.
function M.inverse(a)
	local det = M.determinant(a)

	if math.abs(det) < 1e-15 then
		error("матрица вырождена, обратной не существует", 2)
	end

	local inv_det = 1 / det

	return new {
		{
			(a[2][2] * a[3][3] - a[2][3] * a[3][2]) * inv_det,
			(a[1][3] * a[3][2] - a[1][2] * a[3][3]) * inv_det,
			(a[1][2] * a[2][3] - a[1][3] * a[2][2]) * inv_det,
		},
		{
			(a[2][3] * a[3][1] - a[2][1] * a[3][3]) * inv_det,
			(a[1][1] * a[3][3] - a[1][3] * a[3][1]) * inv_det,
			(a[1][3] * a[2][1] - a[1][1] * a[2][3]) * inv_det,
		},
		{
			(a[2][1] * a[3][2] - a[2][2] * a[3][1]) * inv_det,
			(a[1][2] * a[3][1] - a[1][1] * a[3][2]) * inv_det,
			(a[1][1] * a[2][2] - a[1][2] * a[2][1]) * inv_det,
		},
	}
end

function M.__tostring(a)
	local rows = {}

	for i = 1, 3 do
		rows[i] = ("[%10.4f %10.4f %10.4f]")
			:format(a[i][1], a[i][2], a[i][3])
	end

	return table.concat(rows, "\n")
end

M.new = new

return M
