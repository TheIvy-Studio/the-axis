-- the Axis · physics lab
-- Источники. Каждая формула в лаборатории ссылается на ключ из этой таблицы.
--
-- Правило проекта: формула без источника в код не попадает. Если источник —
-- вывод из более простых законов, это отмечено полем `derived` и вывод
-- расписан в комментарии рядом с реализацией.

local R = {}

R.si_brochure = {
	title = "SI Brochure, 9th edition (2019)",
	org = "BIPM / NIST SP 330",
	url = "https://www.bipm.org/en/publications/si-brochure",
	note = "Определения базовых единиц СИ. Стандартное ускорение свободного "
		.. "падения g0 = 9.80665 м/с^2 закреплено 3-й ГКМВ (1901).",
}

R.us_standard_atmosphere = {
	title = "U.S. Standard Atmosphere, 1976 / ISO 2533",
	org = "NOAA / NASA / USAF",
	url = "https://www.ngdc.noaa.gov/stp/space-weather/online-publications/"
		.. "miscellaneous/us-standard-atmosphere-1976/",
	note = "Плотность воздуха на уровне моря rho0 = 1.225 кг/м^3 при 288.15 K "
		.. "и 101325 Па.",
}

R.nasa_drag_equation = {
	title = "Modern Drag Equation",
	org = "NASA Glenn Research Center · Beginner's Guide to Aeronautics",
	url = "https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/"
		.. "modern-drag-equation/",
	quote = "D = .5 * Cd * r * V^2 * A",
	note = "D — сила сопротивления, Cd — безразмерный коэффициент, r — "
		.. "плотность воздуха, V — скорость относительно воздуха, A — "
		.. "характерная площадь. Вся сложная зависимость от формы тела, "
		.. "вязкости и сжимаемости спрятана в Cd.",
}

R.nasa_falling_object = {
	title = "Falling Object with Air Resistance",
	org = "NASA Glenn Research Center · Beginner's Guide to Aeronautics",
	url = "https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/"
		.. "falling-object-with-air-resistance/",
	quote = "F = W - D ; a = (W - D) / m ; D = Cd * (r * V^2 * A) / 2 ; W = m * g",
	note = "Баланс сил при падении. Страница даёт только баланс: замкнутого "
		.. "решения v(t) на ней нет.",
}

R.nasa_flight_equations_drag = {
	title = "Flight Equations with Drag",
	org = "NASA Glenn Research Center · Beginner's Guide to Aeronautics",
	url = "https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/"
		.. "flight-equations-with-drag/",
	quote = "V_t = sqrt(2*m*g / (Cd*r*A)) ; "
		.. "y = (V_t^2 / 2g) * ln((V_0^2 + V_t^2) / (V^2 + V_t^2))",
	note = "Предельная скорость и путь по вертикали. Для подъёма NASA даёт "
		.. "решение через tan, для снижения — приведённую логарифмическую "
		.. "форму. Эквивалентная форма через tanh выводится в experiments/"
		.. "04_air_resistance.lua и там же численно сверяется с этой.",
}

R.nasa_banking_turns = {
	title = "Banking Turns",
	org = "NASA Glenn Research Center · Beginner's Guide to Aeronautics",
	url = "https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/"
		.. "banking-turns/",
	note = "Подъёмная сила перпендикулярна траектории и плоскости крыльев; "
		.. "при крене она раскладывается на вертикальную составляющую против "
		.. "веса и горизонтальную, которая и разворачивает машину. Страница "
		.. "качественная, поэтому радиус разворота выводится из этого "
		.. "разложения в experiments/10_turn_radius.lua.",
	derived = true,
}

R.nasa_lift_equation = {
	title = "The Lift Equation",
	org = "NASA Glenn Research Center · Beginner's Guide to Aeronautics",
	url = "https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/"
		.. "the-lift-equation/",
	quote = "L = Cl * A * .5 * r * V^2",
	note = "Структурно совпадает с уравнением сопротивления: сила = "
		.. "коэффициент × скоростной напор × площадь.",
}

R.mit_16_07_l26 = {
	title = "Lecture L26 — 3D Rigid Body Dynamics: The Inertia Tensor",
	org = "MIT OpenCourseWare 16.07 Dynamics (Fall 2009)",
	url = "https://ocw.mit.edu/courses/16-07-dynamics-fall-2009/"
		.. "pages/lecture-notes/",
	note = "Тензор инерции набора точечных масс и теорема Гюйгенса — "
		.. "Штейнера (parallel axis theorem).",
}

R.mit_16_07_l28 = {
	title = "Lecture L28 — 3D Rigid Body Dynamics: Euler's Equations",
	org = "MIT OpenCourseWare 16.07 Dynamics (Fall 2009)",
	url = "https://ocw.mit.edu/courses/16-07-dynamics-fall-2009/resources/"
		.. "mit16_07f09_lec28/",
	note = "Уравнения Эйлера: I*dw/dt + w x (I*w) = M. Нелинейны из-за "
		.. "гироскопического члена w x (I*w).",
}

R.verlet_1967 = {
	title = "Computer 'Experiments' on Classical Fluids. I.",
	org = "L. Verlet, Physical Review 159, 98 (1967)",
	url = "https://doi.org/10.1103/PhysRev.159.98",
	note = "Исходная схема Верле.",
}

R.swope_1982 = {
	title = "A computer simulation method for the calculation of equilibrium "
		.. "constants... (velocity Verlet)",
	org = "W. C. Swope et al., J. Chem. Phys. 76, 637 (1982)",
	url = "https://doi.org/10.1063/1.442716",
	note = "Скоростная форма Верле, которая и используется в играх: хранит "
		.. "скорость явно, поэтому её удобно ограничивать и читать.",
}

R.hairer_geometric = {
	title = "Geometric Numerical Integration, 2nd ed.",
	org = "E. Hairer, C. Lubich, G. Wanner (Springer, 2006)",
	url = "https://doi.org/10.1007/3-540-30666-8",
	note = "Симплектические методы (полунеявный Эйлер, Верле) не сохраняют "
		.. "энергию точно, но сохраняют близкий гамильтониан, поэтому "
		.. "ошибка энергии ограничена и не растёт со временем.",
}

R.hairer_odes = {
	title = "Solving Ordinary Differential Equations I: Nonstiff Problems",
	org = "E. Hairer, S. P. Nørsett, G. Wanner (Springer, 1993)",
	url = "https://doi.org/10.1007/978-3-540-78862-1",
	note = "Классический РК4 (таблица Бутчера), порядок точности и область "
		.. "устойчивости.",
}

R.baraff_rigid = {
	title = "An Introduction to Physically Based Modeling: Rigid Body "
		.. "Simulation II — Nonpenetration Constraints",
	org = "D. Baraff, SIGGRAPH course notes, Carnegie Mellon University",
	url = "https://graphics.pixar.com/pbm2001/",
	note = "Импульсный отклик на столкновение: j = -(1+e) * v_rel.n / "
		.. "(1/m1 + 1/m2 + вращательные члены).",
}

R.anderson_aero = {
	title = "Fundamentals of Aerodynamics, 6th ed.",
	org = "J. D. Anderson (McGraw-Hill, 2016)",
	url = "https://www.mheducation.com/highered/product/"
		.. "fundamentals-aerodynamics-anderson/M9781259129919.html",
	note = "Теория тонкого профиля: Cl = 2*pi*alpha для малых углов атаки в "
		.. "несжимаемом потоке. Отсюда наклон линии подъёмной силы 2*pi на "
		.. "радиан ≈ 0.11 на градус.",
}

R.etkin_dynamics = {
	title = "Dynamics of Flight: Stability and Control, 3rd ed.",
	org = "B. Etkin, L. D. Reid (Wiley, 1996)",
	url = "https://www.wiley.com/en-us/Dynamics+of+Flight%3A+Stability+and+"
		.. "Control%2C+3rd+Edition-p-9780471034186",
	note = "Продольная статическая устойчивость, запас устойчивости, "
		.. "производные демпфирования по крену Lp и по рысканью Nr.",
}

R.faa_phak = {
	title = "Pilot's Handbook of Aeronautical Knowledge, FAA-H-8083-25C, "
		.. "Chapter 5 (Aerodynamics of Flight)",
	org = "U.S. Federal Aviation Administration",
	url = "https://www.faa.gov/regulations_policies/handbooks_manuals/"
		.. "aviation/phak",
	note = "Перегрузка в развороте n = 1 / cos(phi), рост скорости сваливания "
		.. "как sqrt(n).",
}

R.gaffer_integration = {
	title = "Fix Your Timestep! / Integration Basics",
	org = "G. Fiedler (Gaffer On Games)",
	url = "https://gafferongames.com/post/fix_your_timestep/",
	note = "Инженерная практика: фиксированный шаг физики с накопителем и "
		.. "интерполяция для отрисовки. Не источник формул, а источник "
		.. "архитектурного решения.",
}

--- Печатает библиографию.
function R.print()
	local keys = {}

	for key in pairs(R) do
		if type(R[key]) == "table" then
			keys[#keys + 1] = key
		end
	end

	table.sort(keys)

	print("Источники:")

	for _, key in ipairs(keys) do
		local ref = R[key]
		print(("  [%s] %s — %s\n      %s"):format(key, ref.title, ref.org, ref.url))
	end
end

return R
