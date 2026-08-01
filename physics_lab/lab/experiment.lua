-- the Axis · physics lab
-- Каркас эксперимента.
--
-- Каждый эксперимент — самостоятельная программа и одновременно модуль:
--
--     luajit experiments/04_air_resistance.lua          — запуск в одиночку
--     luajit run.lua                                    — запуск всех подряд
--
-- Разница только в том, что общий прогон выставляет глобальный флаг LAB_BATCH,
-- и тогда файл не запускает себя сам, а возвращает описание наружу.
--
-- Параметры каждого эксперимента вынесены в таблицу `params` и переопределяются
-- из командной строки:
--
--     luajit experiments/04_air_resistance.lua mass=1200 cd=0.9 dt=0.002
--
-- Так повторить опыт с другими числами можно за секунды и без правки кода.

local plot = require("lab.plot")
local text = require("lab.text")

local M = {}

M.OUT_DIR = "out"

--------------------------------------------------------------------------------
-- Разбор аргументов
--------------------------------------------------------------------------------

local function parse_arguments(argv)
	local overrides = {}
	local flags = {}

	for _, item in ipairs(argv or {}) do
		local flag = item:match("^%-%-([%w%-]+)$")

		if flag then
			flags[flag] = true
		else
			local key, value = item:match("^([%w_]+)=(.+)$")

			if key then
				overrides[key] = tonumber(value)
					or (value == "true" and true)
					or (value == "false" and false)
					or value
			end
		end
	end

	return overrides, flags
end

--------------------------------------------------------------------------------
-- Печать
--------------------------------------------------------------------------------

local function rule(character)
	return string.rep(character or "=", 78)
end

local function print_header(spec, params)
	print(rule("="))
	print(("ЭКСПЕРИМЕНТ %s · %s"):format(spec.id, spec.title))
	print(rule("="))

	if spec.question then
		print()
		print("Вопрос:")

		for line in spec.question:gmatch("[^\n]+") do
			print("  " .. line)
		end
	end

	if spec.model then
		print()
		print("Модель:")

		for line in spec.model:gmatch("[^\n]+") do
			print("  " .. line)
		end
	end

	if spec.simplifications then
		print()
		print("Упрощения и что из-за них теряется:")

		for line in spec.simplifications:gmatch("[^\n]+") do
			print("  " .. line)
		end
	end

	if spec.references and #spec.references > 0 then
		print()
		print("Источники:")

		for _, ref in ipairs(spec.references) do
			print(("  %s — %s"):format(ref.title, ref.org))
			print(("    %s"):format(ref.url))
		end
	end

	if params and next(params) then
		print()
		print("Параметры (переопределяются как имя=значение в аргументах):")

		local names = {}

		for name in pairs(params) do
			names[#names + 1] = name
		end

		table.sort(names)

		for _, name in ipairs(names) do
			local entry = spec.params[name]
			local value = params[name]

			print(("  %s = %s %s")
				:format(text.pad(name, 16),
					text.pad(type(value) == "number"
						and ("%.6g"):format(value) or tostring(value), 12),
					entry and entry.note or ""))
		end
	end

	print()
end

--------------------------------------------------------------------------------
-- Контекст выполнения
--------------------------------------------------------------------------------

local function make_context(spec, flags)
	local artifacts = {}

	local context = {
		flags = flags,
		quiet = flags.quiet or false,
	}

	--- Путь к файлу артефакта в out/.
	function context.path(suffix)
		return ("%s/%s_%s.%s"):format(M.OUT_DIR, spec.id, spec.name,
			suffix)
	end

	--- Печатает ASCII-график, если не запрошен тихий режим.
	function context.show(series, options)
		if context.quiet then
			return
		end

		print()
		print(plot.ascii(series, options))
		print()
	end

	--- Пишет SVG и CSV, если запрошены флагами.
	function context.save(series, options, csv)
		if flags.svg then
			local thinned = {}

			for index, line in ipairs(series) do
				thinned[index] = {
					label = line.label,
					colour = line.colour,
					dashed = line.dashed,
					points = plot.thin(line.points),
				}
			end

			local path = context.path(options and options.suffix or "svg")
			path = path:gsub("%.svg$", ".svg")

			local written = plot.svg(path, thinned, options)

			if written then
				artifacts[#artifacts + 1] = written
			end
		end

		if flags.csv and csv then
			local path = context.path("csv")
			local written = plot.csv(path, csv.headers, csv.rows)

			if written then
				artifacts[#artifacts + 1] = written
			end
		end
	end

	function context.artifacts()
		return artifacts
	end

	return context
end

--------------------------------------------------------------------------------
-- Определение эксперимента
--------------------------------------------------------------------------------

--- Собирает значения параметров: значения по умолчанию плюс переопределения.
local function resolve_params(spec, overrides)
	local params = {}

	for name, entry in pairs(spec.params or {}) do
		params[name] = entry.value
	end

	for name, value in pairs(overrides or {}) do
		if params[name] == nil then
			io.stderr:write(("предупреждение: у эксперимента %s нет параметра "
				.. "'%s', значение проигнорировано\n"):format(spec.id, name))
		else
			params[name] = value
		end
	end

	return params
end

--- Выполняет эксперимент и возвращает результат.
function M.execute(spec, argv, extra_flags)
	local overrides, flags = parse_arguments(argv)

	for name, value in pairs(extra_flags or {}) do
		flags[name] = value
	end

	local params = resolve_params(spec, overrides)
	local context = make_context(spec, flags)

	if not flags.quiet then
		print_header(spec, params)
	end

	-- В тихом режиме глушится и собственная печать эксперимента: иначе
	-- сводка общего прогона утонет в двадцати простынях вывода.
	local restore_print

	if flags.quiet then
		restore_print = print
		_G.print = function() end
	end

	local ok_run, suite = pcall(spec.run, params, context)

	if restore_print then
		_G.print = restore_print
	end

	if not ok_run then
		io.stderr:write(("эксперимент %s упал: %s\n"):format(spec.id,
			tostring(suite)))

		return {
			id = spec.id,
			name = spec.name,
			title = spec.title,
			ok = false,
			total = 0,
			failed = 1,
			crashed = tostring(suite),
			artifacts = {},
		}
	end

	local ok = true

	if suite then
		if not flags.quiet then
			ok = suite:report()
		else
			ok = suite:passed()
		end
	end

	local artifacts = context.artifacts()

	if #artifacts > 0 and not flags.quiet then
		print()
		print("Записано:")

		for _, path in ipairs(artifacts) do
			print("  " .. path)
		end
	end

	local total, failed = suite and suite:count() or 0, suite and 0 or 0

	if suite then
		total, failed = suite:count()
	end

	return {
		id = spec.id,
		name = spec.name,
		title = spec.title,
		ok = ok,
		total = total,
		failed = failed,
		artifacts = artifacts,
	}
end

--- Объявляет эксперимент. В одиночном запуске сразу его выполняет.
function M.define(spec)
	assert(spec.id and spec.name and spec.title and spec.run,
		"эксперименту нужны id, name, title и run")

	spec.execute = function(argv, flags)
		return M.execute(spec, argv, flags)
	end

	-- Общий прогон сам решает, что и когда запускать
	if rawget(_G, "LAB_BATCH") then
		return spec
	end

	local result = M.execute(spec, rawget(_G, "arg"))

	if not result.ok then
		os.exit(1)
	end

	return spec
end

return M
