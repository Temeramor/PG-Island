# Источники, гайды и готовые референсы

Этот список включает использованные принципы и полезные проекты для дальнейшего изучения. В репозиторий не копировались готовые модели, текстуры или исходные файлы перечисленных проектов.

## Островная форма и берег

- **Sebastian Lague — Procedural Landmass Generation (Unity, E02–E21; E11 — Falloff Map).** Хорошее пошаговое введение: шумовая карта, falloff-маска и контроль высоты у краёв. GitHub: <https://github.com/SebLague/Procedural-Landmass-Generation>. Видео E11: <https://www.youtube.com/watch?v=COmtTyLCd6I>. Репозиторий MIT.
- **Red Blob Games — Making maps with noise functions.** Объясняет частоту, октавы, распределение высот и то, почему форму острова разумно отделять от деталей рельефа. <https://www.redblobgames.com/maps/terrain-from-noise/>
- **Red Blob Games — Island shaping.** Практический разбор функций reshaping для изолиний и островного силуэта, включая distance-field-подход. <https://www.redblobgames.com/maps/mapgen2/island-shaping.html>
- **Red Blob Games — Mapgen2.** Интерактивный генератор островных карт с открытым JavaScript-кодом; полезен для проверки сидов, берегов, высот и биомов. <https://www.redblobgames.com/maps/mapgen2/>. Исходники: <https://github.com/redblobgames/mapgen2> (Apache-2.0).
- **Red Blob Games — Mapgen4.** Более сложный интерактивный генератор, показывающий влияние дождя, испарения, ветра, рек и биомов. <https://www.redblobgames.com/maps/mapgen4/>
- **Heman — prideout/heman.** C99 single-header библиотека с simplex FBM, генерацией острова/архипелага, SDF, нормалями и AO. MIT. Это полезный кодовый референс, но для Godot/GDScript пришлось бы собирать C-код; в этот проект библиотека не встроена. <https://github.com/prideout/heman> · <https://heman.readthedocs.io/en/latest/generate.html> · <https://prideout.net/heman/>

## Шум, холмы и горы

- **Inigo Quilez — Domain Warping.** Искажение координат другим полем шума для менее радиальных, более органичных берегов и рельефа. <https://iquilezles.org/articles/warp/>
- **Inigo Quilez — Advanced noise / morenoise.** Шум с производными и контролем вклада последующих октав; полезен для более спокойных долин и структурированных склонов. <https://iquilezles.org/articles/morenoise/>
- **The Book of Shaders — Chapter 13: Fractal Brownian Motion.** Объясняет fBm, turbulence, ridge-подобные конструкции и суммирование октав. <https://thebookofshaders.com/13/>
- **Godot FastNoiseLite.** Встроенный класс генерации Simplex, Perlin, Value, Cellular, FBM, Ridged и Domain Warp. Используется в runtime-генераторе маски без внешнего аддона. <https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html>

## Эрозия и гидрология

- **Rune Skovbo Johansen — Fast and Gorgeous Erosion Filter (2026).** Направленные борозды и гребни строятся как специальный шум, выровненный по градиенту склона; метод не является симуляцией потоков воды и пригоден для вычисления по точкам/GPU. Статья: <https://blog.runevision.com/2026/03/fast-and-gorgeous-erosion-filter.html>. Godot community prototype: <https://forum.godotengine.org/t/fast-and-gorgeous-erosion-filter/136436>. В проекте использована самостоятельная упрощённая реализация принципа, а не дословный порт фильтра.
- **Sebastian Lague — Hydraulic Erosion.** Классическая симуляция капель и переноса осадка; полезна как отдельный этап bake heightmap. <https://github.com/SebLague/Hydraulic-Erosion>
- **UnityTerrainErosionGPU.** Compute Shader-пример гидравлической и термической эрозии. Unity-ориентирован, но полезен для изучения потока и осадка. <https://github.com/bshishov/UnityTerrainErosionGPU>
- **GuilBlack/Erosion.** Compute-shader прототип клеточной эрозии. <https://github.com/GuilBlack/Erosion>
- **Godot Compute Shader Heightmap Demo.** Проект из Godot Asset Library с обработкой heightmap compute shader; полезен как стартовый пример GPU-обработки в Godot 4.7. В Asset Library есть исходная версия 4.2, а в официальном Godot Asset Store опубликована версия с минимальной версией Godot 4.7. <https://godotengine.org/asset-library/asset/2784> · <https://store.godotengine.org/asset/godot-foundation/compute-shader-heightmap-demo/>

## Вода и подводная часть

- **GPU Gems 1 — Effective Water Simulation from Physical Models.** Классический разбор волн Герстнера и нормалей поверхности. <https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-1-effective-water-simulation-physical-models>
- **Chrisknyfe/boujie_water_shader.** Godot water shader с Gerstner waves, refraction, depth fog и foam; MIT. <https://github.com/Chrisknyfe/boujie_water_shader>
- **LesusX/Water-Shader.** Godot 4 MIT-проект с волнами, caustics и пеной. <https://github.com/LesusX/Water-Shader>
- **emilje/godot-water-shader.** Godot 4 MIT-проект с Gerstner waves, Jacobian/shore foam и depth fade. <https://github.com/emilje/godot-water-shader>
- **Godot spatial shader reference.** Документация по vertex/fragment стадиям, depth texture и экранным данным. <https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html>

## Важные примечания

- Для проекта нужен только Godot 4.7.2; все runtime noise-функции и материалы находятся в проекте, а FastNoiseLite встроен в движок.
- Compute-shader проекты Unity и C-библиотека Heman приведены как исследовательские референсы, но не требуются для запуска.
- Фильтр Runevision указан как вдохновение для структуры борозд; текущая версия — облегчённая самостоятельная аппроксимация, а не идентичная реализация исходного фильтра.
