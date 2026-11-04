# Sources, references and licensing notes

The repository contains an original Godot implementation of publicly described techniques. No third-party model, image, heightmap, plugin, or source file is bundled. The links below are references for the algorithms and for further study; the license of each external repository applies to that repository, not automatically to this project.

## Island silhouette, coast and height fields

- **Red Blob Games — Making maps with noise functions.** Noise octaves, height distributions and terrain shaping: <https://www.redblobgames.com/maps/terrain-from-noise/>
- **Red Blob Games — Island shaping.** Signed distance fields and separating island shape from height: <https://www.redblobgames.com/maps/mapgen2/island-shaping.html>
- **Red Blob Games — Mapgen2.** Interactive source project; Apache-2.0: <https://www.redblobgames.com/maps/mapgen2/> · <https://github.com/redblobgames/mapgen2>
- **Red Blob Games — Mapgen4.** Interactive exploration of procedural terrain, drainage, rain, rivers, and biome layers: <https://www.redblobgames.com/maps/mapgen4/> · <https://github.com/redblobgames/mapgen4> (Apache-2.0). Mapgen4 is an educational visual generator rather than a physically accurate terrain simulator.
- **Sebastian Lague — Procedural Landmass Generation.** Step-by-step Unity project covering noise, falloff maps, mesh construction and terrain texturing; GitHub repository is MIT: <https://github.com/SebLague/Procedural-Landmass-Generation> · <https://www.youtube.com/playlist?list=PLFt_AvWsXl0eBW2EiBtl_sxmDtSgZBxB3>
- **Heman — prideout/heman.** Single-header C99 utility for procedural heightmaps, simplex FBM, island generation, signed-distance fields, normals and AO; MIT: <https://github.com/prideout/heman> · <https://heman.readthedocs.io/en/latest/generate.html>
- **Godot FastNoiseLite.** Built-in noise implementation; Simplex, FBM, ridged fractal and domain-warp controls: <https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html>

## Hills, ridges, procedural noise and shaders

- **Inigo Quilez — Domain Warping.** Coordinate warping by another noise field: <https://iquilezles.org/articles/warp/>
- **Inigo Quilez — Morenoise.** Noise with derivatives and slope-aware octave contribution: <https://iquilezles.org/articles/morenoise/>
- **The Book of Shaders — Chapter 13: Fractal Brownian Motion.** fBm, turbulence and octave summation: <https://thebookofshaders.com/13/>
- **Godot 4.7 spatial shader reference.** Vertex/fragment stages, depth and screen textures: <https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html>

## Erosion and drainage

- **Rune Skovbo Johansen — Fast and Gorgeous Erosion Filter (30 March 2026).** Gradient-aligned procedural gullies and ridges that can be evaluated independently per point: <https://blog.runevision.com/2026/03/fast-and-gorgeous-erosion-filter.html>. The published filter is MPL-2.0. This project implements a lightweight original multi-scale approximation of the slope-aligned principle; it is not a port of the full advanced filter.
- **Henry1 — Godot community prototype for the Fast and Gorgeous Erosion Filter.** Public discussion and GDScript prototype: <https://forum.godotengine.org/t/fast-and-gorgeous-erosion-filter/136436>. Used as a reference for slope-aligned stripe construction, not copied verbatim.
- **Sebastian Lague — Hydraulic Erosion.** Particle-based hydraulic erosion simulation; MIT: <https://github.com/SebLague/Hydraulic-Erosion>. The Godot filter adapts the droplet direction, sediment-capacity, erosion-brush and deposition workflow; it does not copy Unity-specific source files.
- **80 Level — Fast Terrain Erosion Filter That Emulates Erosion Without Simulation.** Overview of Rune Skovbo Johansen's 2026 filter and its released implementation: <https://80.lv/articles/fast-terrain-erosion-filter-that-emulates-erosion-without-simulation>.
- **UnityTerrainErosionGPU.** Unity compute-shader implementation of hydraulic and thermal erosion inspired by shallow-water equations: <https://github.com/bshishov/UnityTerrainErosionGPU>
- **Godot Compute Shader Heightmap Demo.** Official Godot Foundation example for compute-shader heightmap generation; inspect the release page for the current project version and license: <https://godotengine.org/asset-library/asset/2784> · <https://store.godotengine.org/asset/godot-foundation/compute-shader-heightmap-demo/>

## Water, waves and underwater rendering

- **GPU Gems 1 — Effective Water Simulation from Physical Models.** Gerstner wave model and surface normals: <https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-1-effective-water-simulation-physical-models>
- **Chrisknyfe/boujie_water_shader.** Godot water shader with Gerstner waves, refraction, Fresnel, depth fog and shore foam; MIT: <https://github.com/Chrisknyfe/boujie_water_shader>
- **LesusX/Water-Shader.** Godot 4 water shader including caustics and foam; MIT: <https://github.com/LesusX/Water-Shader>
- **emilje/godot-water-shader.** Godot 4 Gerstner water and shoreline effects: <https://github.com/emilje/godot-water-shader>

## How the references are used here

- Separate coastline SDF and elevation fields: Red Blob Games.
- Domain warp, Simplex FBM and ridged details: Inigo Quilez, The Book of Shaders and Godot FastNoiseLite.
- Multi-scale slope-aligned channels/ridges: the filter adapts the published ideas of blended cosine/sine ridges, slope masking and multiple octaves from Rune Skovbo Johansen; it is not a verbatim port of the MPL-2.0 implementation.
- Hydraulic erosion and sediment transport: a small deterministic droplet simulation adapts the algorithmic workflow described in Sebastian Lague's MIT project.
- Thermal erosion: a conservative local talus-relaxation pass moves material between adjacent land cells.
- GPU surface displacement, depth sampling and procedural layer shading: Godot spatial shader documentation.
- Gerstner waves and screen-space water composition: GPU Gems and the Boujie Water Shader feature set.
- Sebastian Lague, Heman and UnityTerrainErosionGPU are additional source-code references; none of their code is required to run this project.
