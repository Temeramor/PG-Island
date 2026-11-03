# Procedural generation guide

## Coordinate system and target area

The terrain is a square sampling domain measured in metres. `world_size` is the width and depth of that domain. The island is the portion of the generated surface above sea level (Y = 0). The requested land area is set by `land_area_km2`.

The generator first evaluates an irregular polar coastline. It then uses a binary search over a radial scale factor to find a coastline whose rasterized land mask is closest to the requested area. This is why different seeds can have different silhouettes while keeping approximately the same land area.

The displayed area is a grid estimate. It is not an exact polygon-area calculation; increase `resolution` to reduce quantization and improve the coastline. At 256 samples per side, the project favors iteration speed. Use 512 or higher for a final bake after profiling.

## Shape layers

- Three angular harmonics create large bays, peninsulas and asymmetry.
- Seeded simplex noise perturbs the coastline.
- Low-frequency fractal noise creates broad elevation masses.
- Ridged noise creates mountain chains and peaks.
- Perlin detail adds foothill and surface variation.
- The same signed distance to the coast controls the transition from land to continental shelf and deep seabed.

## Material layers

The generator assigns vertex colours based on elevation and estimated surface slope. The terrain shader adds small-scale procedural colour variation. These are deliberately lightweight starter materials. Replace or extend them with tileable PBR textures, normal maps, roughness maps and slope/height splat masks for a higher-fidelity art pass.

## Performance notes

- Coastline calibration is a CPU grid pass and grows with resolution squared.
- Mesh generation creates one continuous surface and one trimesh collider.
- The ocean uses a subdivided plane and a lightweight animated shader.
- The current project is intended as a standalone island prototype, not an infinite-world streaming system.

## Recommended extension path

1. Add hydraulic erosion and sediment transport as an offline bake or compute-shader pass.
2. Derive flow accumulation from the height field, then carve river channels and create spline/mesh water surfaces.
3. Export height, slope, flow, shoreline and biome masks for use by terrain materials and foliage placement.
4. Scatter trees, rocks and grass with MultiMeshInstance3D using slope and biome masks.
5. Add chunked LOD and asynchronous generation if the playable area grows beyond a single island tile.
6. For caves and overhangs, use a voxel terrain system alongside the heightfield rather than forcing those shapes into a heightmap.

## Optional Godot integrations

- Terrain3D: https://github.com/TokisanGames/Terrain3D
- Waterways: https://github.com/Arnklit/Waterways
- Voxel Tools: https://github.com/Zylann/godot_voxel

The base project does not vendor these addons. Install a release explicitly compatible with the exact Godot version you use, and review its license before distributing the project.
