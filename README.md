# PG Island — procedural island plan

Godot 4.7.2 project. The first milestone is a top-down cartographic overview of a procedurally generated island.

## Run

Open this folder in Godot 4.7.2 and run the project (F6/F5). Press **R** to generate another island.

## Current scope

- Flat landmass only: no elevation, terrain, mountains, or textures yet.
- Procedural coastline from a warped signed scalar field, fractal noise, and randomized coastal inlets.
- The land mask is selected before the mesh is built.
- Horizontal land area is normalized to 4,000,000 m² (4 km²) using the occupied mask-cell count.
- Orthographic aerial camera and a restrained survey-style overlay.

## Generation notes

The implementation follows the mask-first approach described by Red Blob Games: construct a scalar field and threshold it into a land mask before any later elevation stage. Noise contributes coastal irregularity; randomized negative fields create bays and inlets, including strongly concave silhouettes. The current mesh is deliberately flat.

References:
- https://www.redblobgames.com/maps/terrain-from-noise/
- https://www.redblobgames.com/maps/terrain-from-noise/islands.html
- https://github.com/SebLague/Procedural-Landmass-Generation
- https://heman.readthedocs.io/en/latest/generate.html
