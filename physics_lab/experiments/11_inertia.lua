-- the Axis · physics lab · эксперимент 11
-- Момент инерции воксельного тела и теорема Штейнера.

package.path = ((arg and arg[0] or ""):gsub("[^/\\]*$", "") .. "../?.lua;")
	.. package.path

local experiment = require("lab.experiment")
local rigid = require("lab.rigid")
local voxel = require("lab.voxel")
local vec3 = require("lab.vec3")
local check = require("lab.check")
local C = require("lab.constants")
local text = require("lab.text")
local R = require("lab.references")

return experiment.define {
	id = "11",
	name = "inertia",
	title = "Момент инерции воксельной конструкции",

	question = [[
Насколько тяжело раскрутить конструкцию и почему длинная машина поворачивает
хуже короткой при той же массе?

Это то, чего в моде нет вообще: там масса есть, а момента инерции нет, и
поэтому вращение задаётся не физикой, а сглаживанием (TILT_SMOOTHING).]],

	model = [[
Для набора точечных масс [mit_16_07_l26]:

    I_xx = sum m*(y^2 + z^2)      I_xy = -sum m*x*y
    I_yy = sum m*(x^2 + z^2)      I_xz = -sum m*x*z
    I_zz = sum m*(x^2 + y^2)      I_yz = -sum m*y*z

Единицы: [кг·м^2]. Сходится.

Матрица симметрична. Внедиагональные элементы — центробежные моменты; они
отвечают за то, что момент вокруг одной оси раскручивает тело вокруг другой.
У симметричного тела они нули, у несимметричного — нет, и именно они дают
эффект «дёрнул по крену, получил и рыскание».

Теорема Гюйгенса — Штейнера для переноса оси на вектор d:
    I_new = I_cm + m*((d.d)*E - d (x) d)

Эталоны для проверки:
  * Тонкий стержень длины L вокруг поперечной оси через центр: I = m*L^2/12.
    Формула ТОНКОГО стержня: поперечный размер считается нулевым.
  * Однородный прямоугольный брус L x s x s вокруг поперечной оси через
    центр: I = m*(L^2 + s^2)/12. Второе слагаемое — вклад поперечного
    размера, которым формула тонкого стержня пренебрегает.
  * Однородный куб со стороной s вокруг оси через центр: I = m*s^2/6
    (частный случай бруса при L = s).

Цепочка из N блоков — это и есть однородный брус L x s x s, где L = N*s.
Поэтому правильный эталон для неё — формула бруса, а не тонкого стержня.
Разложение по слагаемым:
    точечные массы в центрах блоков   m*s^2*(N^2 - 1)/12
  + собственная инерция кубов         m*s^2/6
  = брус                              m*s^2*(N^2 + 1)/12 = m*(L^2 + s^2)/12

Это тождество и проверяется. Если считать блоки точками и сравнивать с
тонким стержнем, получится расхождение 1/N^2 — оно не ошибка кода, а
разница между дискретной и непрерывной моделью.]],

	simplifications = [[
Блок можно считать точкой или учитывать его собственный момент инерции
(m*s^2/6 по каждой оси). Разница не растёт с плечом, поэтому у большой
конструкции она мала, а у конструкции из двух-трёх блоков — заметна.
Оба варианта считаются и сравниваются.]],

	references = { R.mit_16_07_l26 },

	params = {
		rod_blocks = { value = 11, note = "длина эталонного стержня, блоков" },
		block_mass = { value = 3, note = "игровая масса блока (3 = дерево)" },
		fuselage = { value = 9, note = "длина фюзеляжа машины, блоков" },
		span = { value = 3, note = "размах крыла, блоков" },
	},

	run = function(P, ctx)
		local size = C.value("node_size")

		----------------------------------------------------------------------
		-- Стержень из блоков против школьной формулы
		----------------------------------------------------------------------
		local rod = voxel.rod(P.rod_blocks, P.block_mass)
		local centre, mass = rigid.centre_of_mass(rod)

		local inertia_points = rigid.inertia_tensor(rod, centre)
		local inertia_cubes = rigid.inertia_tensor(rod, centre, size)

		local length = P.rod_blocks * size
		-- Тонкий стержень: поперечный размер отброшен
		local thin_rod = mass * length * length / 12
		-- Однородный брус L x s x s: правильный эталон для цепочки блоков
		local solid_box = mass * (length * length + size * size) / 12
		local discrete = mass * size * size
			* (P.rod_blocks ^ 2 - 1) / 12

		print(("Стержень: %d блоков, масса %.2f кг, длина %.2f м")
			:format(P.rod_blocks, mass, length))
		print(("  центр масс: %s"):format(tostring(centre)))
		print()
		print(text.row {
			{ "модель", 40 }, { "I_zz, кг·м^2", 16 },
		})
		print(text.row {
			{ "точечные массы в центрах блоков", 40 },
			{ ("%.4f"):format(inertia_points[3][3]), 16 },
		})
		print(text.row {
			{ "точное дискретное m*s^2*(N^2-1)/12", 40 },
			{ ("%.4f"):format(discrete), 16 },
		})
		print(text.row {
			{ "блоки с собственной инерцией", 40 },
			{ ("%.4f"):format(inertia_cubes[3][3]), 16 },
		})
		print(text.row {
			{ "однородный брус m*(L^2+s^2)/12", 40 },
			{ ("%.4f"):format(solid_box), 16 },
		})
		print(text.row {
			{ "тонкий стержень m*L^2/12", 40 },
			{ ("%.4f"):format(thin_rod), 16 },
		})
		print(("Отношение точечной модели к тонкому стержню: %.6f "
			.. "(ожидается 1 - 1/N^2 = %.6f)")
			:format(discrete / thin_rod, 1 - 1 / P.rod_blocks ^ 2))

		-- Сумма собственных инерций кубов
		local own_total = mass * size * size / 6

		print(("Вклад собственной инерции блоков: %.4f кг·м^2 (%.2f %% от целого)")
			:format(own_total, own_total / inertia_cubes[3][3] * 100))

		----------------------------------------------------------------------
		-- Теорема Штейнера
		----------------------------------------------------------------------
		local offset = vec3.new(length / 2, 0, 0)
		local shifted = rigid.parallel_axis(inertia_points, mass, offset)
		local direct = rigid.inertia_tensor(rod, centre + offset)

		print()
		print(("Перенос оси на %.3f м (в конец стержня):"):format(length / 2))
		print(("  по теореме Штейнера: I_zz = %.4f"):format(shifted[3][3]))
		print(("  прямым пересчётом:   I_zz = %.4f"):format(direct[3][3]))
		print(("  брус вокруг конца m*(L^2/3 + s^2/12) = %.4f")
			:format(mass * (length * length / 3 + size * size / 12)))

		----------------------------------------------------------------------
		-- Настоящая машина
		----------------------------------------------------------------------
		local body = voxel.describe(
			voxel.aircraft { fuselage = P.fuselage, span = P.span }, true)

		print()
		print(("Машина: %d блоков, масса %.1f кг"):format(body.count, body.mass))
		print(("  центр масс:            %s"):format(tostring(body.centre)))
		print(("  геометрический центр:  %s"):format(tostring(body.geometric_centre)))
		print()
		print("  Тензор инерции относительно центра масс, кг·м^2:")
		print(tostring(body.inertia))

		local i_xx, i_yy, i_zz = body.inertia[1][1], body.inertia[2][2],
			body.inertia[3][3]

		print()
		print(("  I_xx = %.1f (крен, вокруг продольной оси)"):format(i_xx))
		print(("  I_yy = %.1f (тангаж)"):format(i_yy))
		print(("  I_zz = %.1f (рыскание)"):format(i_zz))
		print(("  Отношение I_yy/I_xx = %.2f: по тангажу машина в %.1f раза "
			.. "инертнее, чем по крену"):format(i_yy / i_xx, i_yy / i_xx))

		----------------------------------------------------------------------
		-- Как длина влияет на инертность
		----------------------------------------------------------------------
		print()
		print("Удлинение фюзеляжа при той же массе блока:")
		print(text.row {
			{ "блоков", 10 }, { "масса, кг", 14 }, { "I_yy, кг·м^2", 16 },
			{ "I_yy/m", 12 },
		})

		local length_curve = {}

		for _, count in ipairs({ 3, 5, 7, 9, 11, 15, 21 }) do
			local test = voxel.describe(
				voxel.aircraft { fuselage = count, span = P.span }, true)

			length_curve[#length_curve + 1] = { count, test.inertia[2][2] }

			print(text.row {
				{ tostring(count), 10 },
				{ ("%.1f"):format(test.mass), 14 },
				{ ("%.1f"):format(test.inertia[2][2]), 16 },
				{ ("%.3f"):format(test.inertia[2][2] / test.mass), 12 },
			})
		end

		print()
		print("Момент инерции растёт быстрее массы: масса линейна по числу")
		print("блоков, а инерция — примерно как куб длины. Поэтому длинная")
		print("машина «вязкая» по тангажу, хотя весит ненамного больше.")

		----------------------------------------------------------------------
		-- Центробежные моменты
		----------------------------------------------------------------------
		local asymmetric = voxel.describe(voxel.aircraft {
			fuselage = P.fuselage, left = P.span, right = 1,
		}, true)

		print()
		print("Несимметричная машина (крылья 3 и 1), тензор инерции:")
		print(tostring(asymmetric.inertia))
		print(("Центробежный момент I_xz = %.4f — не ноль, значит момент "
			.. "вокруг одной оси раскручивает и другую")
			:format(asymmetric.inertia[1][3]))

		ctx.show({
			{ label = "I_yy(длина)", mark = "*", points = length_curve },
		}, {
			title = "Момент инерции растёт быстрее массы",
			xlabel = "длина фюзеляжа, блоков",
			ylabel = "I_yy, кг·м^2",
			height = 15,
		})

		ctx.save({
			{ label = "I_yy", points = length_curve },
		}, {
			title = "Момент инерции в зависимости от длины",
			xlabel = "длина фюзеляжа, блоков",
			ylabel = "I_yy, кг·м^2",
		}, {
			headers = { "blocks", "i_yy" },
			rows = length_curve,
		})

		----------------------------------------------------------------------
		local suite = check.new("момент инерции")

		suite:close("цепочка точечных масс равна m*s^2*(N^2-1)/12",
			inertia_points[3][3], discrete, 1e-12,
			"замкнутая сумма ряда квадратов; расхождение только от округления")

		suite:close("точечная модель отличается от тонкого стержня в 1 - 1/N^2",
			discrete / thin_rod, 1 - 1 / P.rod_blocks ^ 2, 1e-12,
			"точное отношение, следует из тех же двух формул")

		suite:close("блоки с собственной инерцией дают ровно брус m*(L^2+s^2)/12",
			inertia_cubes[3][3], solid_box, 1e-12,
			"цепочка соприкасающихся кубов И ЕСТЬ однородный брус, поэтому "
			.. "совпадение обязано быть точным. Тонкий стержень тут не "
			.. "эталон: он пренебрегает поперечным размером, а у блока "
			.. "он равен продольному")

		suite:close("теорема Штейнера совпадает с прямым пересчётом",
			shifted[3][3], direct[3][3], 1e-12,
			"два независимых способа посчитать одну величину")

		suite:close("брус вокруг конца даёт m*(L^2/3 + s^2/12)",
			rigid.parallel_axis(inertia_cubes, mass, offset)[3][3],
			mass * (length * length / 3 + size * size / 12), 1e-12,
			"m*(L^2+s^2)/12 + m*(L/2)^2 = m*(L^2/3 + s^2/12), тождество")

		suite:is_true("тензор инерции симметричен",
			(function()
				for i = 1, 3 do
					for j = 1, 3 do
						if math.abs(body.inertia[i][j] - body.inertia[j][i])
								> 1e-12 then
							return false
						end
					end
				end

				return true
			end)(),
			"симметрия следует из определения; несимметричный тензор означал "
			.. "бы ошибку в коде")

		suite:is_true("у симметричной машины центробежный момент I_yz равен нулю",
			math.abs(body.inertia[2][3]) < 1e-12,
			"крылья расположены симметрично относительно плоскости y-x, "
			.. "поэтому вклады по +z и -z сокращаются")

		suite:is_true("у несимметричной машины центробежные моменты не нули",
			math.abs(asymmetric.inertia[2][3]) > 1e-9,
			"перекос крыла нарушает симметрию, и вращение по одной оси "
			.. "начинает подмешиваться в другую")

		suite:is_true("моменты инерции положительны",
			i_xx > 0 and i_yy > 0 and i_zz > 0,
			"диагональные элементы — суммы m*r^2, они не могут быть "
			.. "отрицательными")

		suite:is_true("выполняется неравенство треугольника для главных моментов",
			i_xx + i_yy >= i_zz and i_yy + i_zz >= i_xx
				and i_xx + i_zz >= i_yy,
			"фундаментальное свойство тензора инерции любого реального тела; "
			.. "его нарушение означало бы физически невозможную конструкцию")

		return suite
	end,
}
