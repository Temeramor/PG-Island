# PG-Island — Godot 4.7.2 Procedural Island Generator

A self-contained Godot project that procedurally generates a randomly shaped island with a **target land area of 4 km²**, mountainous interior, irregular coastline, continental shelf and deep-ocean bathymetry.

The project has **no mandatory third-party addon dependency**. It uses Godot's built-in FastNoiseLite, ArrayMesh, ShaderMaterial, StaticBody3D and PlaneMesh, so it can be opened and run without downloading plugin code.

## Requirements

- Godot Engine **4.7.2**
- The project is configured for the Compatibility renderer for portability.

## Run

1. Clone or download this repository.
2. Open the folder containing project.godot in Godot 4.7.2.
3. Press F5.
4. Press **Generate new island** or **R** to create another seed.

## What is generated

- A random, asymmetric coastline built from angular harmonics and seeded noise.
- A target land area of 4,000,000 m². A binary search calibrates the coastline scale against generated height samples; the displayed area is a raster estimate and varies slightly with grid resolution.
- Broad mountainous massifs, ridges, foothills and smaller-scale terrain variation.
- A continuous terrain surface extending below sea level to form a continental shelf and deep seabed.
- Vertex-colour terrain zones for sand, vegetation, rock, alpine terrain and underwater depth.
- A procedural ocean material with animated waves.
- A trimesh collision body for the terrain.

## Project layout

    project.godot
    scenes/
      main.tscn
    scripts/
      main.gd
      procedural_island.gd
    shaders/
      terrain.gdshader
      ocean.gdshader

## Main generator parameters

Select the Island node in scenes/main.tscn:

| Parameter | Default | Meaning |
|---|---:|---|
| seed | 18427 | Reproducible island shape |
| land_area_km2 | 4.0 | Target land area |
| world_size | 3200 m | Width/depth of terrain and bathymetry tile |
| resolution | 256 | Height samples per side |
| peak_height | 460 m | Main elevation scale |
| ocean_depth | 260 m | Maximum seabed depth |
| coastline_roughness | 32 m | Small-scale shoreline irregularity |

The 4 km² figure refers to **land above sea level**, not the square terrain tile. The surrounding tile also contains the shallow shelf and deep ocean floor. The area is estimated from the generated raster; increase resolution for a finer boundary measurement and smoother silhouette.

## Notes and next steps

This is a baseline procedural generator, not a photogrammetry asset pack. It creates coherent macro-geology from seeded noise and exposes the data needed for further art direction. For a production world, the next layers to add are:

1. Hydraulic erosion and sediment/deposition passes.
2. Flow accumulation and river carving.
3. Slope/height-based splat maps and physically based ground textures.
4. Foliage placement using biome masks and MultiMeshInstance3D.
5. Chunked LOD/streaming for larger worlds.
6. Shore foam, shallow-water depth tint, underwater fog and caustics.

Optional integrations to evaluate separately:

- [Terrain3D](https://github.com/TokisanGames/Terrain3D) for editor sculpting, texture painting, foliage instancing and terrain LOD.
- [Waterways](https://github.com/Arnklit/Waterways) for spline-based river meshes.
- [Voxel Tools](https://github.com/Zylann/godot_voxel) if caves, overhangs or destructible volumetric terrain are required.

These are deliberately not bundled: check compatibility and licensing against the exact plugin release before adding them to the project.

## Area accuracy

The generator uses a grid-based binary search to match the requested land area. The reported value is a discrete estimate, not a geospatial survey measurement. Actual rendered boundary area depends on grid resolution and should be treated as approximately 4 km². For tighter area tolerances, increase resolution or add a sub-cell coastline integration pass.
