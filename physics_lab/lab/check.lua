-- the Axis · physics lab
-- Проверки: сравнение численного результата с аналитическим эталоном.
--
-- Принцип, ради которого лаборатория и строится: у эксперимента должен быть
-- ответ, известный НЕ из этого же кода. Либо замкнутое решение, либо закон
-- сохранения, либо порядок сходимости. Сравнение симуляции с самой собой
-- ничего не доказывает.
--
-- Допуск у каждой проверки задаётся осмысленно. «Подогнать допуск, пока не
-- зазеленеет» — прямо запрещено: если результат не лезет в разумный допуск,
-- надо искать причину, а не двигать порог.

local text = require("lab.text")

local M = {}

local Suite = {}
Suite.__index = Suite

--- Относительная ошибка. Около нуля переключается на абсолютную, иначе
--- деление на почти-ноль даёт бессмысленные проценты.
function M.relative_error(actual, expected)
	local scale = math.abs(expected)

	if scale < 1e-12 then
		return math.abs(actual - expected)
	end

	return math.abs(actual - expected) / scale
end

function M.new(title)
	return setmetatable({
		title = title,
		entries = {},
		failed = 0,
	}, Suite)
end

--- Численное сравнение с допуском по относительной ошибке.
---
--- @param why обязательное обоснование допуска
function Suite:close(name, actual, expected, tolerance, why)
	if not why then
		error("у допуска обязано быть обоснование: " .. name, 2)
	end

	local error_value = M.relative_error(actual, expected)
	local ok = error_value <= tolerance

	self.entries[#self.entries + 1] = {
		name = name,
		actual = actual,
		expected = expected,
		error_value = error_value,
		tolerance = tolerance,
		why = why,
		ok = ok,
	}

	if not ok then
		self.failed = self.failed + 1
	end

	return ok
end

--- Проверка «величина лежит в диапазоне». Для случаев, где точного значения
--- нет, но физически осмысленные границы есть.
function Suite:within(name, actual, low, high, why)
	if not why then
		error("у диапазона обязано быть обоснование: " .. name, 2)
	end

	local ok = actual >= low and actual <= high

	self.entries[#self.entries + 1] = {
		name = name,
		actual = actual,
		range = { low, high },
		why = why,
		ok = ok,
	}

	if not ok then
		self.failed = self.failed + 1
	end

	return ok
end

--- Логическая проверка.
function Suite:is_true(name, value, why)
	if not why then
		error("у проверки обязано быть обоснование: " .. name, 2)
	end

	local ok = value == true

	self.entries[#self.entries + 1] = {
		name = name,
		boolean_value = value,
		why = why,
		ok = ok,
	}

	if not ok then
		self.failed = self.failed + 1
	end

	return ok
end

--- Печатает результаты и возвращает true, если всё сошлось.
function Suite:report()
	print()
	print(("Проверки: %s"):format(self.title))
	print(("%s"):format(string.rep("-", 78)))

	for _, entry in ipairs(self.entries) do
		local mark = entry.ok and "ОК  " or "СБОЙ"

		local name = text.pad(entry.name, 46)

		if entry.range then
			print(("  %s %s %.6g в [%.6g, %.6g]")
				:format(mark, name, entry.actual,
					entry.range[1], entry.range[2]))
		elseif entry.boolean_value ~= nil then
			print(("  %s %s %s")
				:format(mark, name, tostring(entry.boolean_value)))
		else
			print(("  %s %s получено %s эталон %s ошибка %.3g (допуск %.3g)")
				:format(mark, name,
					text.pad(("%.6g"):format(entry.actual), 13),
					text.pad(("%.6g"):format(entry.expected), 13),
					entry.error_value, entry.tolerance))
		end

		print(("       обоснование допуска: %s"):format(entry.why))
	end

	print(("%s"):format(string.rep("-", 78)))
	print(("Итог: %d из %d сошлось")
		:format(#self.entries - self.failed, #self.entries))

	return self.failed == 0
end

function Suite:passed()
	return self.failed == 0
end

function Suite:count()
	return #self.entries, self.failed
end

return M
