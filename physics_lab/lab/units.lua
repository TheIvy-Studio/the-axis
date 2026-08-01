-- the Axis · physics lab
-- Размерности СИ и проверка согласованности формул.
--
-- Зачем это здесь. Требование «проверять размерность каждого уравнения»
-- бесполезно, если проверка живёт в комментарии: комментарий не падает.
-- Поэтому размерность здесь — исполняемый объект. Величина Quantity несёт
-- число и вектор степеней семи базовых единиц СИ; сложение величин разной
-- размерности бросает ошибку, умножение складывает степени. Формулу можно
-- один раз прогнать на величинах, и если она собрана неверно — тест упадёт,
-- а не «выглядит правильно».
--
-- Источник определений базовых единиц: [si_brochure].

local M = {}

-- Порядок базовых единиц СИ. Показатели степеней хранятся в этом порядке.
local BASE = { "m", "kg", "s", "A", "K", "mol", "cd" }

M.BASE = BASE

--------------------------------------------------------------------------------
-- Размерность
--------------------------------------------------------------------------------

local Dim = {}
Dim.__index = Dim

local function dim(t)
	return setmetatable({
		t.m or 0, t.kg or 0, t.s or 0,
		t.A or 0, t.K or 0, t.mol or 0, t.cd or 0,
	}, Dim)
end

M.dim = dim

function Dim.__eq(a, b)
	for i = 1, #BASE do
		-- Допуск нужен для дробных степеней: sqrt даёт 0.5, и накопленная
		-- ошибка двоичного представления не должна ломать сравнение.
		if math.abs(a[i] - b[i]) > 1e-9 then
			return false
		end
	end

	return true
end

function Dim.__mul(a, b)
	local out = setmetatable({}, Dim)

	for i = 1, #BASE do
		out[i] = a[i] + b[i]
	end

	return out
end

function Dim.__div(a, b)
	local out = setmetatable({}, Dim)

	for i = 1, #BASE do
		out[i] = a[i] - b[i]
	end

	return out
end

function Dim.__pow(a, n)
	local out = setmetatable({}, Dim)

	for i = 1, #BASE do
		out[i] = a[i] * n
	end

	return out
end

function Dim.__tostring(self)
	local positive, negative = {}, {}

	for i, name in ipairs(BASE) do
		local power = self[i]

		if math.abs(power) > 1e-9 then
			local target = power > 0 and positive or negative
			local size = math.abs(power)
			local text = size == 1 and name
				or (name .. "^" .. tostring(size):gsub("%.0$", ""))

			target[#target + 1] = text
		end
	end

	if #positive == 0 and #negative == 0 then
		return "1"
	end

	local text = #positive > 0 and table.concat(positive, "·") or "1"

	if #negative > 0 then
		text = text .. "/" .. table.concat(negative, "·")
	end

	return text
end

--------------------------------------------------------------------------------
-- Готовые размерности
--------------------------------------------------------------------------------

local D = {}

D.scalar = dim {}
D.length = dim { m = 1 }
D.mass = dim { kg = 1 }
D.time = dim { s = 1 }
D.area = dim { m = 2 }
D.volume = dim { m = 3 }
D.velocity = dim { m = 1, s = -1 }
D.acceleration = dim { m = 1, s = -2 }
D.force = dim { kg = 1, m = 1, s = -2 }              -- Н
D.energy = dim { kg = 1, m = 2, s = -2 }             -- Дж
D.power = dim { kg = 1, m = 2, s = -3 }              -- Вт
D.pressure = dim { kg = 1, m = -1, s = -2 }          -- Па
D.density = dim { kg = 1, m = -3 }
D.momentum = dim { kg = 1, m = 1, s = -1 }           -- кг·м/с
D.inertia = dim { kg = 1, m = 2 }                    -- кг·м^2
D.torque = dim { kg = 1, m = 2, s = -2 }             -- Н·м
D.angular_momentum = dim { kg = 1, m = 2, s = -1 }
D.frequency = dim { s = -1 }
-- Угол в СИ безразмерен (рад = м/м). Отдельная размерность ему не нужна,
-- но угловая скорость по размерности совпадает с частотой — это не
-- совпадение, а следствие безразмерности угла.
D.angle = dim {}
D.angular_velocity = dim { s = -1 }
D.angular_acceleration = dim { s = -2 }

M.D = D

--------------------------------------------------------------------------------
-- Величина: число вместе с размерностью
--------------------------------------------------------------------------------

local Quantity = {}
Quantity.__index = Quantity

local function is_quantity(x)
	return type(x) == "table" and getmetatable(x) == Quantity
end

M.is_quantity = is_quantity

--- Создаёт величину. Число без размерности считается безразмерным.
local function quantity(value, dimension)
	return setmetatable({ v = value, d = dimension or D.scalar }, Quantity)
end

M.Q = quantity

local function lift_operand(x)
	return is_quantity(x) and x or quantity(x, D.scalar)
end

function Quantity.__add(a, b)
	a, b = lift_operand(a), lift_operand(b)

	if not (a.d == b.d) then
		error(("сложение несовместимых величин: [%s] + [%s]")
			:format(tostring(a.d), tostring(b.d)), 2)
	end

	return quantity(a.v + b.v, a.d)
end

function Quantity.__sub(a, b)
	a, b = lift_operand(a), lift_operand(b)

	if not (a.d == b.d) then
		error(("вычитание несовместимых величин: [%s] - [%s]")
			:format(tostring(a.d), tostring(b.d)), 2)
	end

	return quantity(a.v - b.v, a.d)
end

function Quantity.__mul(a, b)
	a, b = lift_operand(a), lift_operand(b)

	return quantity(a.v * b.v, a.d * b.d)
end

function Quantity.__div(a, b)
	a, b = lift_operand(a), lift_operand(b)

	return quantity(a.v / b.v, a.d / b.d)
end

function Quantity.__unm(a)
	return quantity(-a.v, a.d)
end

function Quantity.__pow(a, n)
	a = lift_operand(a)

	if is_quantity(n) then
		if not (n.d == D.scalar) then
			error("показатель степени обязан быть безразмерным", 2)
		end

		n = n.v
	end

	return quantity(a.v ^ n, a.d ^ n)
end

function Quantity.__eq(a, b)
	return a.d == b.d and a.v == b.v
end

function Quantity.__lt(a, b)
	a, b = lift_operand(a), lift_operand(b)

	if not (a.d == b.d) then
		error("сравнение несовместимых величин", 2)
	end

	return a.v < b.v
end

function Quantity.__tostring(self)
	return ("%.6g [%s]"):format(self.v, tostring(self.d))
end

--- Корень с корректным делением размерности пополам.
function M.sqrt(q)
	return lift_operand(q) ^ 0.5
end

--- Проверяет, что величина имеет ожидаемую размерность.
--- Возвращает численное значение, чтобы вызов можно было встроить в формулу.
function M.expect(name, q, expected)
	if not is_quantity(q) then
		error(("%s: ожидалась величина с размерностью, получено %s")
			:format(name, type(q)), 2)
	end

	if not (q.d == expected) then
		error(("%s: размерность [%s], ожидалась [%s]")
			:format(name, tostring(q.d), tostring(expected)), 2)
	end

	return q.v
end

--- Сокращение для тестов: правда/ложь без исключения.
function M.same(q, expected)
	return is_quantity(q) and q.d == expected
end

return M
