# Procedural Island — Natural Terrain Generator

The island is generated entirely in code and shaders. No external models, textures or add-ons are required.

## Run

1. Open `project.godot` in Godot 4.3+ with the Forward+ renderer.
2. Run the project (F5).

Controls: RMB + mouse to look, WASD to move, Q/E down/up, Shift to move faster, mouse wheel to adjust speed, R to generate a new island, Esc to release the mouse. The camera starts above the island and can fly freely.

## Terrain design

- **Island footprint:** a warped, irregular coastline inside a 3.6 km terrain field. The target land area is approximately 4 km²; the exact area varies slightly with the random shoreline seed.
- **Relief:** broad lowlands and rolling hills are always present. Mountain ranges are independently enabled per seed, so some islands remain low and hilly while others develop a broken central spine.
- **Elevation:** land height is hard-clamped to 0–200 m. There is no snow layer or snowline.
- **Coast:** low-gradient beaches use sand tones; steep coastal faces and exposed slopes use layered rock. The underwater shelf follows the same warped coastline before descending into a deeper seabed.
- **Materials:** large-scale color variation, mid-scale geology and fine grain are layered separately to avoid a single noisy texture.

## Implementation notes

The terrain shader separates the island silhouette from the elevation field. Domain-warped distance shapes the coastline; slope-aware fBm creates rolling terrain; ridged multifractal noise forms broken mountain crests; broad drainage cuts interrupt the ridges. The same heightfield drives both displacement and normal reconstruction.

The generator is intentionally self-contained. It does not copy third-party shader files. The slope-aware fBm is inspired by Inigo Quilez's morenoise work; island falloff and shape/relief separation follow approaches discussed by Sebastian Lague and Red Blob Games.

## Performance

The terrain is a single 640 × 640 vertex grid evaluated in the vertex shader. If performance is limited, reduce `subdivisions` in `main.gd` (for example, to 480). The water mesh can be reduced independently with `water_subdivisions`.

## Important tuning values

In `shaders/terrain.gdshader`:
- `island_radius`, `coast_warp`, `coast_detail`: island footprint and shoreline irregularity.
- `mountain_chance`: probability of a mountain range for a given seed.
- `mountain_strength`: relief strength when a range is present.
- `max_height`: hard land-height ceiling (default 200 m).
- `hill_strength`: rolling relief independent of mountains.
