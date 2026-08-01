-- the Axis · physics lab
-- Трёхмерные векторы. Значения неизменяемы: каждая операция возвращает новый
-- вектор. Так исключается целый класс ошибок, когда интегратор портит
-- состояние, которое ещё понадобится следующей стадии (РК4 без этого
-- ломается молча).

local V = {}
V.__index = V

local function new(x, y, z)
	return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V)
end

function V.__add(a, b) return new(a.x + b.x, a.y + b.y, a.z + b.z) end
function V.__sub(a, b) return new(a.x - b.x, a.y - b.y, a.z - b.z) end
function V.__unm(a) return new(-a.x, -a.y, -a.z) end

function V.__mul(a, b)
	if type(a) == "number" then
		return new(a * b.x, a * b.y, a * b.z)
	end

	if type(b) == "number" then
		return new(a.x * b, a.y * b, a.z * b)
	end

	-- Покомпонентное умножение. Скалярное произведение — dot, чтобы «*»
	-- нельзя было спутать с ним по недосмотру.
	return new(a.x * b.x, a.y * b.y, a.z * b.z)
end

function V.__div(a, b) return new(a.x / b, a.y / b, a.z / b) end

function V.__eq(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end

function V.__tostring(a)
	return ("(%.6g, %.6g, %.6g)"):format(a.x, a.y, a.z)
end

function V.dot(a, b)
	return a.x * b.x + a.y * b.y + a.z * b.z
end

function V.cross(a, b)
	return new(
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x)
end

function V.length(a)
	return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end

function V.length_squared(a)
	return a.x * a.x + a.y * a.y + a.z * a.z
end

--- Единичный вектор. Нулевой вектор возвращается как есть: направления у
--- него нет, и выдумывать его нельзя.
function V.normalise(a)
	local length = V.length(a)

	if length < 1e-12 then
		return new(0, 0, 0)
	end

	return new(a.x / length, a.y / length, a.z / length)
end

--- Проекция a на направление n (n должен быть единичным).
function V.project(a, n)
	return n * V.dot(a, n)
end

--- Составляющая a поперёк направления n.
function V.reject(a, n)
	return a - V.project(a, n)
end

function V.distance(a, b)
	return V.length(a - b)
end

V.new = new
V.zero = new(0, 0, 0)
V.unit_x = new(1, 0, 0)
V.unit_y = new(0, 1, 0)
V.unit_z = new(0, 0, 1)

return setmetatable(V, { __call = function(_, x, y, z) return new(x, y, z) end })
