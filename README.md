# Procedural Island (Godot 4.3+)

Остров целиком генерируется кодом и шейдерами. Нет моделей, текстур и внешних аддонов: одна плоская сетка (PlaneMesh) выгибается в вершинном шейдере по формуле высоты, цвет считается во фрагментном шейдере.

## Запуск

1. Godot 4.3 или новее (Forward+ или Mobile).
2. Project Manager → Import → выбрать `project.godot` → Run (F5).

Управление: ПКМ + мышь = осмотр, WASD = движение, Q/E = вниз/вверх, Shift = быстрее, колесо = скорость, R = новый остров, Esc = отпустить мышь. Под водой включается синий туман.

## Что внутри

- `main.gd` создаёт сцену: небо, солнце, сетку земли, сетку океана, камеру.
- `shaders/terrain.gdshader` даёт форму острова, рельеф, дно и раскраску.
- `shaders/water.gdshader` даёт волны, поглощение света глубиной, преломление и пену у берега.

Параметры (радиус, высота, крутизна склонов, цвета, линия снега и т.д.) видны в инспекторе у материала: `Terrain → Mesh → Material → Shader Parameters`. Через `@export` в `main.gd` меняются детализация сетки (`subdivisions`) и сид.

## Откуда взяты приёмы

| Что | Источник |
|---|---|
| Маска острова (falloff-кривая `x^a / (x^a + (b - b·x)^a)`) | Sebastian Lague, Procedural Landmass Generation, E11 |
| Неровный берег через domain warping | Inigo Quilez, https://iquilezles.org/articles/warp |
| Холмы: fBm с аналитическими производными, затухание октав по крутизне (эффект эрозии) | Inigo Quilez, https://iquilezles.org/articles/morenoise |
| Горы: ridged multifractal (abs, инверсия, квадрат) | The Book of Shaders, глава 13 |
| Отдельно форма острова и отдельно рельеф | Red Blob Games, island shaping / terrain from noise |
| Смещение вершин и пересчёт нормалей в шейдере | Документация Godot, "Your first 3D shader" |
| Волны Герстнера | GPU Gems, глава 1 |
| Структура воды, глубина, пена | godotshaders.com "Water shader 3D (Godot 4.3)", Chrisknyfe/boujie_water_shader (MIT) |
| Хэш без синуса | Dave Hoskins, shadertoy 4djSRW |

Формулы переписаны в собственную реализацию и не копируют чужие файлы целиком.

## Дальше

- Если сетка тяжёлая для видеокарты, уменьшите `subdivisions` (например, до 384).
- Для ещё более реалистичных склонов: фильтр эрозии Rune Skovbo Johansen (https://blog.runevision.com/2026/03/fast-and-gorgeous-erosion-filter.html). Его центральная функция под лицензией CC BY-NC-SA, поэтому я её не встраивал.
- Для настоящей симуляции эрозии: Sebastian Lague Hydraulic-Erosion или Mei et al. (compute shader), запекается в карту высот.
