# PG Island — procedural island plan

Godot 4.7.2 project. The first milestone is a top-down cartographic overview of a procedurally generated island.

## Run

Open this folder in Godot 4.7.2 and run the project (F6/F5). Use **W/A/S/D** to move the aerial camera, **Space** to rise/zoom out, **Shift** to descend/zoom in, and **R** to generate another island.

## Current scope

- Procedural elevation with broad geological masses, rolling hills, warped mountain ridges, valleys, and fine slope detail.
- Height-band vertex colors: lowland greens, upland ochres, exposed rock, and pale high peaks.
- Procedural coastline from a warped signed scalar field, fractal noise, and randomized coastal inlets.
- The land mask is selected before the mesh is built.
- Horizontal land area is normalized to 4,000,000 m² (4 km²) using the occupied mask-cell count.
- Orthographic aerial camera with keyboard navigation and altitude-linked zoom, plus a restrained survey-style overlay.

## Generation notes

The implementation follows the mask-first approach described by Red Blob Games: construct a scalar field and threshold it into a land mask before any later elevation stage. Noise contributes coastal irregularity; randomized negative fields create bays and inlets, including strongly concave silhouettes. The terrain stage combines separate fBm fields for macro uplift, hills, ridged mountain structures, and fine detail. Domain warping is applied to the broad and medium coordinates; the fine layer remains comparatively stable. A softly bounded, randomly rotated mountain province gives the ridged noise a coherent mountain-chain region. Vertex colors visualize elevation bands, and shared grid-corner heights keep neighboring cell geometry continuous.

Terrain references:
- https://iquilezles.org/articles/warp/
- https://iquilezles.org/articles/morenoise/
- https://thebookofshaders.com/13/

Coastline references:
- https://www.redblobgames.com/maps/terrain-from-noise/
- https://www.redblobgames.com/maps/terrain-from-noise/islands.html
- https://github.com/SebLague/Procedural-Landmass-Generation
- https://heman.readthedocs.io/en/latest/generate.html
