-- the Axis · physics lab
-- Твёрдое тело: центр масс, тензор инерции, уравнения Эйлера, импульсы.
--
-- Это ровно та часть, которой не хватало в моде: конструкция там крутилась
-- вокруг геометрической середины и наклонялась по эвристике, а не по моменту
-- силы. Здесь всё считается честно и проверяется против аналитики.
--
-- Источники: [mit_16_07_l26] (тензор инерции, теорема Штейнера),
-- [mit_16_07_l28] (уравнения Эйлера), [baraff_rigid] (импульсный отклик).

local vec3 = require("lab.vec3")
local mat3 = require("lab.mat3")

local M = {}

--------------------------------------------------------------------------------
-- Центр масс
--------------------------------------------------------------------------------
--
--     r_cm = sum(m_i * r_i) / sum(m_i)                            [м]
--
-- Точка, движение которой описывается вторым законом Ньютона так, будто вся
-- масса собрана в ней. Именно поэтому свободное тело вращается вокруг центра
-- масс, а не вокруг чего-либо ещё.
--
-- Единицы: [кг·м]/[кг] = [м]. Сходится.
--------------------------------------------------------------------------------
function M.centre_of_mass(points)
	local total = 0
	local weighted = vec3.zero

	for _, point in ipairs(points) do
		total = total + point.mass
		weighted = weighted + point.position * point.mass
	end

	if total <= 0 then
		error("суммарная масса должна быть положительной", 2)
	end

	return weighted / total, total
end

--------------------------------------------------------------------------------
-- Тензор инерции набора точечных масс
--------------------------------------------------------------------------------
--
--     I_xx = sum m*(y^2 + z^2)      I_xy = -sum m*x*y
--     I_yy = sum m*(x^2 + z^2)      I_xz = -sum m*x*z
--     I_zz = sum m*(x^2 + y^2)      I_yz = -sum m*y*z
--
-- Матрица симметрична. Внедиагональные элементы (центробежные моменты)
-- отвечают за то, что момент силы вокруг одной оси раскручивает тело вокруг
-- другой; у несимметричной конструкции они не нули, и игнорировать их —
-- значит терять именно те эффекты, ради которых всё затевалось.
-- [mit_16_07_l26]
--
-- Единицы: [кг·м^2]. Сходится.
--
-- Допущение: масса собрана в точках. Для воксельной конструкции это
-- приближение, а не истина: у блока есть собственный момент инерции
-- относительно своего центра, для куба со стороной s это (1/6)*m*s^2 по
-- каждой оси. Учитывается через `include_own_inertia` — для тела из многих
-- блоков вклад мал (он не растёт с плечом), но для конструкции из двух-трёх
-- блоков даёт заметную разницу.
--------------------------------------------------------------------------------
function M.inertia_tensor(points, origin, node_size)
	origin = origin or vec3.zero

	local xx, yy, zz = 0, 0, 0
	local xy, xz, yz = 0, 0, 0

	for _, point in ipairs(points) do
		local r = point.position - origin
		local m = point.mass

		xx = xx + m * (r.y * r.y + r.z * r.z)
		yy = yy + m * (r.x * r.x + r.z * r.z)
		zz = zz + m * (r.x * r.x + r.y * r.y)

		xy = xy - m * r.x * r.y
		xz = xz - m * r.x * r.z
		yz = yz - m * r.y * r.z

		if node_size then
			-- Собственный момент инерции однородного куба: (1/6)*m*s^2
			local own = m * node_size * node_size / 6

			xx = xx + own
			yy = yy + own
			zz = zz + own
		end
	end

	return mat3.new {
		{ xx, xy, xz },
		{ xy, yy, yz },
		{ xz, yz, zz },
	}
end

--------------------------------------------------------------------------------
-- Теорема Гюйгенса — Штейнера
--------------------------------------------------------------------------------
--
--     I_new = I_cm + m * ( (d.d)*E - d (x) d )
--
-- где d — вектор от центра масс до новой оси, E — единичная матрица,
-- (x) — внешнее (диадное) произведение. [mit_16_07_l26]
--
-- Единицы: [кг·м^2] + [кг]·[м^2] = [кг·м^2]. Сходится.
--------------------------------------------------------------------------------
function M.parallel_axis(inertia_cm, mass, offset)
	local d = offset
	local dd = vec3.dot(d, d)

	local shift = mat3.new {
		{ mass * (dd - d.x * d.x), mass * (-d.x * d.y),      mass * (-d.x * d.z) },
		{ mass * (-d.y * d.x),     mass * (dd - d.y * d.y),  mass * (-d.y * d.z) },
		{ mass * (-d.z * d.x),     mass * (-d.z * d.y),      mass * (dd - d.z * d.z) },
	}

	return inertia_cm + shift
end

--------------------------------------------------------------------------------
-- Момент силы
--------------------------------------------------------------------------------
--
--     tau = r x F                                                [Н·м]
--
-- r — плечо от центра масс до точки приложения. Отсюда сразу следует то, что
-- в моде было сделано неверно: сила, приложенная В центре масс, даёт r = 0 и
-- нулевой момент. Собственный вес приложен ровно в центре масс, значит вес
-- НЕ вращает свободное тело. Наклон создаёт только несимметрия внешних сил.
--
-- Единицы: [м]·[Н] = [Н·м] = [кг·м^2/с^2]. Сходится.
--------------------------------------------------------------------------------
function M.torque(lever, force)
	return vec3.cross(lever, force)
end

--------------------------------------------------------------------------------
-- Уравнения Эйлера
--------------------------------------------------------------------------------
--
--     I * dw/dt + w x (I*w) = tau
--     dw/dt = I^-1 * (tau - w x (I*w))                           [рад/с^2]
--
-- Записаны в связанных с телом осях, где I постоянен. [mit_16_07_l28]
--
-- Член w x (I*w) — гироскопический. Он нелинеен и отвечает за то, что
-- несимметричное тело, раскрученное вокруг промежуточной оси инерции,
-- кувыркается само по себе без всякого внешнего момента (теорема о теннисной
-- ракетке). Проверяется в experiments/12_angular_velocity.lua.
--
-- Единицы: [кг·м^2]^-1 · [Н·м] = [1/с^2]. Сходится (угол безразмерен).
--------------------------------------------------------------------------------
function M.angular_acceleration(inertia, inertia_inverse, omega, torque)
	local spin = vec3.cross(omega, inertia * omega)

	return inertia_inverse * (torque - spin)
end

--- Момент импульса L = I*w, [кг·м^2/с].
function M.angular_momentum(inertia, omega)
	return inertia * omega
end

--- Кинетическая энергия вращения T = 0.5 * w . (I*w), [Дж].
function M.rotational_energy(inertia, omega)
	return 0.5 * vec3.dot(omega, inertia * omega)
end

--- Кинетическая энергия поступательного движения T = 0.5*m*v^2, [Дж].
function M.translational_energy(mass, velocity)
	return 0.5 * mass * vec3.length_squared(velocity)
end

--------------------------------------------------------------------------------
-- Импульсный отклик на столкновение
--------------------------------------------------------------------------------
--
-- Для двух тел без учёта вращения [baraff_rigid]:
--
--     j = -(1 + e) * (v_rel . n) / (1/m1 + 1/m2)                  [кг·м/с]
--
--     v1' = v1 + (j/m1)*n
--     v2' = v2 - (j/m2)*n
--
-- e — коэффициент восстановления, от 0 (полностью неупругий удар) до 1
-- (абсолютно упругий). Величина эмпирическая, физического «правильного»
-- значения у неё нет: это свойство пары материалов.
--
-- Единицы: [кг·м/с] / [1/кг] → [кг·м/с]. Сходится, j — импульс силы.
--
-- Неподвижная стена моделируется бесконечной массой: 1/m2 = 0.
--
-- Границы: удар мгновенный и точечный, трения нет (см. `friction_impulse`),
-- вращение не учитывается. Полная форма с вращением добавляет в знаменатель
-- члены n.(I^-1 (r x n)) x r — она нужна, когда удар приходится далеко от
-- центра масс и должен закручивать тело.
--------------------------------------------------------------------------------
function M.collision_impulse(v1, v2, normal, inverse_mass1, inverse_mass2,
		restitution)
	local relative = vec3.dot(v1 - v2, normal)

	-- Тела расходятся — импульс не нужен. Без этой проверки объекты
	-- «прилипают»: каждый кадр им добавляется импульс на разлёт.
	if relative > 0 then
		return 0
	end

	local denominator = inverse_mass1 + inverse_mass2

	if denominator <= 0 then
		return 0
	end

	return -(1 + restitution) * relative / denominator
end

--------------------------------------------------------------------------------
-- Кулоновское трение при ударе
--------------------------------------------------------------------------------
--
--     |j_t| <= mu * |j_n|                                        (конус трения)
--
-- Касательный импульс гасит скольжение, но не может превысить mu * нормальный
-- импульс. Если требуемый для полной остановки скольжения импульс меньше
-- порога — контакт «залипает», иначе скользит с трением. [baraff_rigid]
--------------------------------------------------------------------------------
function M.friction_impulse(tangential_speed, normal_impulse, inverse_mass_sum,
		friction)
	if inverse_mass_sum <= 0 then
		return 0
	end

	-- Импульс, полностью останавливающий проскальзывание
	local required = -tangential_speed / inverse_mass_sum
	local limit = friction * math.abs(normal_impulse)

	if math.abs(required) <= limit then
		return required
	end

	return required > 0 and limit or -limit
end

--------------------------------------------------------------------------------
-- Проверка размерностей
--------------------------------------------------------------------------------

function M.dimension_selftest()
	local U = require("lab.units")
	local D = U.D
	local results = {}

	local function case(name, expression, expected)
		local ok, value = pcall(expression)

		results[#results + 1] = {
			name = name,
			ok = ok and U.same(value, expected),
			got = ok and tostring(value.d) or ("ошибка: " .. tostring(value)),
			expected = tostring(expected),
		}
	end

	local mass = U.Q(500, D.mass)
	local r = U.Q(2, D.length)
	local force = U.Q(1000, D.force)
	local inertia = U.Q(800, D.inertia)
	local omega = U.Q(1.5, D.angular_velocity)
	local velocity = U.Q(20, D.velocity)

	case("тензор инерции m*r^2", function() return mass * r ^ 2 end, D.inertia)
	case("момент силы r*F", function() return r * force end, D.torque)
	case("угловое ускорение tau/I",
		function() return r * force / inertia end, D.angular_acceleration)
	case("момент импульса I*w",
		function() return inertia * omega end, D.angular_momentum)
	case("энергия вращения I*w^2/2",
		function() return U.Q(0.5) * inertia * omega ^ 2 end, D.energy)
	case("импульс m*v", function() return mass * velocity end, D.momentum)
	case("импульс силы = импульс тела",
		function() return force * U.Q(0.1, D.time) end, D.momentum)

	return results
end

return M
