# Visual Benchmark: Premium Vertical Slice

_2026-10-27. Scope: atrium lobby, East Wing corridor, shop template, day/night look, UI panels. Nothing here has been viewed in Roblox Studio by me; judge it from your screenshots._

## 1. Audit of the previous build (main weaknesses, by impact)

| # | Weakness | Why it hurt | Fix in this slice |
|---|---|---|---|
| 1 | Flat lighting | High-noon sun and high ambient flattened every form; night was a purple tint with nothing lit by colour | Re-lit presets (warm sun angle chosen to fall through the dome, lower ambient, stronger contrast); 16 coloured night uplights; floor sheen at night |
| 2 | Primitive hero silhouettes | Palms, fountain and columns are what the eye lands on first, and they were boxes and cylinders | Generated smooth meshes (palm, fountain, fluted column, planter-bench) via the AssetRegistry; procedural fluting as a fallback |
| 3 | Empty shop interiors | Three shelf units in a painted box; nothing to see through the glass | Rebuilt shop: lit display windows with category hero pieces, blade sign, feature wall with logo, feature fixture, cabinet, mouldings, light troughs |
| 4 | Dead public spaces | No seating, carts, ads, wayfinding or "air" | Ring benches, kiosk carts, directory totem, hero neon sign, hanging signs, ad lightboxes, runner, soffits, flower beds, dust and spore particles, sun shafts, fountain jets |
| 5 | UI read as flat fills | Uniform panel colour | Glass sheen gradient on every panel (global) |

## 2. Benchmark definition
The slice passes when, in **your** screenshots:
1. From spawn you see the fountain, palms, dome and the **NIGHT SHIFT** neon sign in one frame, with readable depth (foreground seating, midground fountain, background balcony).
2. Day reads warm and inviting: sunlight patterns on the floor, a soft haze, visible shafts and dust.
3. Night reads violet and electric blue: columns and pilasters washed with coloured light, neon reflected as sheen on the floor, readable walkways, glowing eyes.
4. Shop windows are worth looking into from the corridor, and the blade signs identify shops from down the hall.
5. Your laptop holds playable FPS. Measure it; I can't.

## 3. Art-direction specification

### Colour palette
Source of truth: `src/shared/Config/Palette.luau`.
- **Warm neutrals:** marble whites `#EAE4DA`/`#D6C4AC`, gold `#D8AE60`, walnut `#B27C50`/`#6C462C`.
- **Night neons:** pink `#FF40C8`, cyan `#40DCFF`, purple `#9848FF`. Each shop has its own accent.
- **Rule:** neon is pastel by day and saturated at night. Warm light belongs to the day and the flashlight; cool and violet light belongs to the night.

### Material palette
| Surface | Material | Notes |
|---|---|---|
| Floors | Marble (light) + dark marble runners/inlays + grout lines | `ReflectiveFloor` tag: 0.06 by day → 0.16 by night |
| Columns, planters | Marble | Fluted, with gold rings |
| Trims, rails, posts | Metal (gold) | Thin. Used as accent lines, never as large areas |
| Storefront frames, fascia | Metal (dark) | Recessed signage plane |
| Shop floors and fixtures | WoodPlanks / Wood | Showroom marble inlay at the centre |
| Glass | Glass, 0.55–0.65 transparency | Never casts shadows |
| Soft goods | Fabric | Plush, apparel, rugs, canopies |

### Architectural style
"Retro-luxe 1980s mall": a symmetrical atrium under a geodesic dome, a ring balcony with glass rails, marble and brass detailing, and lit fascia signage. Shops follow one kit: kickplate → glass → transom → fascia → lightbox sign, plus a blade sign.

### Lighting strategy (Future technology)
| Role | Day | Night |
|---|---|---|
| Key | Sun, about 52° elevation, through the dome; ribs cast patterns | Moon plus coloured uplights on columns and pilasters |
| Fill | Ambient `#5C524E` (lowered for contrast) | Ambient `#2C1E56`, kept readable |
| Accent | Window spots, pendants, cove troughs (`DayLight`/`DayNeon`) | Neon strips (`NightNeon`), hero sign glow |
| Atmosphere | Density 0.26, warm haze, shafts and dust | Density 0.36 violet, spores, floor sheen |
| Post | Bloom 0.4 (threshold 1.8), contrast +0.12 | Bloom 0.85 (threshold 1.1), contrast +0.22 |

Shadow-casting lights: one per shop (the centre pendant) plus the sun/moon. All other lights are shadowless.

### Model requirements
| Object class | Technique |
|---|---|
| Architecture (walls, slabs, balcony, ceilings) | Parts. Flat, cheap, collision-accurate |
| Hero props (palm, fountain, column, planter-bench) | **MeshParts** from `scripts/meshgen.py` (done), or Blender replacements |
| Furniture, fixtures, storefront kit, merchandise | Parts now. Blender kit in the next pass (`ASSETS.md`) |
| Creatures | Procedural rig now. Blender rig and Animator animations later |

### Texture requirements
Built-in materials only for now (no uploads needed). The next step is MaterialVariants for marble and wood: 1024² colour, normal and roughness maps. Signage stays SurfaceGui text, which needs no texture memory.

### Animation requirements
Escalator treads, fountain jets and lurker eyes are animated locally (done). Crawler skitter, lean, lunge, shiver and dissolve are procedural (done). Authored clips for crawlers, customers and the flashlight hold are listed in `ASSETS.md`.

### Performance budgets (slice)
| Budget | Target | This slice (estimate from code; confirm in Studio) |
|---|---|---|
| Parts (whole map) | ≤ 6,000 | About +1,200 over the previous build. **The startup log prints the real number** |
| Mesh triangles per hero asset | ≤ 10k | 3.7k–9.9k |
| Active lights | ≤ 60 at a time | Day and night sets are mutually exclusive; faded lights are now *disabled*, not just dimmed |
| Shadow-casting lights | ≤ 8 | 6 (one per shop) |
| Particles | ≤ 600 alive | Dust/spores about 260, fountain about 300, all off with Reduced Effects |
| Highlights | ≤ 31 | Up to 14 (enemy hit flash) |

## 4. What was built (file map)
| Area | Where |
|---|---|
| Lighting presets | `src/shared/Config/LightingPresets.luau` |
| Atrium detail layer | `src/server/World/LobbyDetail.luau` (grout, promenade ring, fluting, uplights, rail posts, fountain jets, ring benches, 2 kiosk carts, directory, **hero neon sign**, hanging signs, sun shafts, particles) |
| Corridor detail layer | `src/server/World/CorridorDetail.luau` (runner, soffit beams, cove troughs, 2 hanging signs, 8 ad lightboxes, 8 uplights, flower beds, shafts, particles) |
| Shop template | `src/server/World/ShopUnit.luau` (rebuilt storefront and interior; gameplay contract unchanged) |
| New props | `src/server/World/Props.luau` (sunShaft, ambientVolume, uplight, hangingSign, lightbox, ringBench, kioskCart, directoryTotem) |
| Mesh pipeline | `scripts/meshgen.py` → `art/meshes/*.obj`; `AssetRegistry` auto-materials and base alignment |
| Client ambience | `src/client/Controllers/AtmosphereController.luau` (new); `LightingController` now disables faded lights |
| Monsters | eye trails (`ShadowCrawler`); hit flash, chase lean and burn shiver (`EnemyVisualController`) |
| UI | glass sheen on all panels (`Components.panel`) |
| Spawn | now faces the fountain and hero sign (`Layout.PlayerSpawn`) |

## 5. Where it still falls short of the reference images
Honest gaps. These are inherent to the current asset pipeline, not bugs:
1. **Characters and creatures.** The key art shows sculpted, expressive models. In game the creatures are still procedural rigs; a Blender-sculpted creature with authored animation is the biggest remaining gap.
2. **Surface detail.** References imply textured marble, wood grain and reflections. Built-in materials plus Future lighting get partway; MaterialVariants (texture uploads) are needed for the rest.
3. **Reflections.** True mirror-like floor reflections of neon aren't possible in Roblox. The night sheen and coloured light pools approximate them.
4. **Shattered-glass and smoke drama** (key art 1) are event VFX. They belong to the boss phase (later).
5. **Furniture and storefront kit** are still Parts. Better than before, but a Blender kit with bevels will read noticeably smoother.
6. **Icons** are still emoji. A custom icon sheet needs image uploads.

## 6. Visual review checklist (please screenshot each)
Take these with Studio's graphics quality at **Automatic** and also at **level 5** (to approximate your laptop).
1. **Spawn view, day:** fountain, palms, dome, hero sign.
2. **Same view, night:** coloured column washes, floor sheen, neon sign.
3. **Atrium floor by day, looking down:** sun patterns from the dome ribs, grout lines, promenade ring.
4. **Corridor looking east, day:** runner, soffits, hanging sign, lightboxes, blade signs.
5. **Corridor at night:** pilaster uplights, ad glow, readable path.
6. **Through a shop window from the corridor:** hero display and spot light.
7. **Inside a shop:** feature wall, feature fixture, counter, crates.
8. **A Shadow Crawler at night, close:** eye trails, and the hit flash while you burn it.
9. **Shop panel open:** the UI sheen.
10. **Shift+F5 stats overlay** at day and at night (FPS), plus the startup log line `[MallBuilder] built N parts`.
