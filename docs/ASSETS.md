# 3D / Texture / Animation / Audio Asset Plan

## Status
- **Architecture** (walls, slabs, balcony, ceilings): Roblox Parts. This is the right technique for them: flat, cheap, accurate collision.
- **Hero props: four real meshes generated** by `scripts/meshgen.py` (smooth-shaded OBJ, in `art/meshes/`). They need a one-time import in Studio (below) to replace the part-built versions.
- **Everything else** (furniture, fixtures, merchandise, creatures) is still procedural Parts. It is better detailed now, but **not** equivalent to modelled assets. It is listed below with exact specs.

## A. Importing the generated hero meshes (one time, about 10 minutes)
On the Windows laptop, after `git pull`:

1. Open the place in Studio. Go to **Home → Import 3D** (or **File → Import 3D**) and pick `art/meshes/PalmTree.obj`.
2. In the import preview:
   - set the scale / file units to **Studs**, so the size is unchanged
   - keep the objects **separate**: do not merge meshes, so you get one MeshPart per object (`Bark_Trunk`, `Leaf_FrondsA`, …)
   - turn **Anchored** on
3. Import. A Model appears in Workspace. Rename it **exactly** `PalmTree`.
4. Check that the part names start with a material prefix (`Bark_`, `Leaf_`, `LeafDark_`, `Marble_`, `MarbleWarm_`, `Gold_`, `Wood_`, `Soil_`, `Water_`). If your importer version renamed them, rename them back; that prefix is how the game assigns materials.
5. Right-click the model → **Save to File…** → save into the repo as `assets/PalmTree.rbxm`. Then delete the model from Workspace.
6. Repeat for `Fountain.obj`, `Column.obj` and `PlanterBench.obj`, naming them `Fountain`, `Column`, `PlanterBench`.
7. Commit the four `.rbxm` files and push. With `rojo serve` running, stop and press Play again: the atrium now uses the meshes everywhere. The procedural fluting and ring benches turn themselves off when `Column` / `PlanterBench` assets exist.

You don't need to set pivots. `AssetRegistry` aligns each model's bounding-box base to the spot, and applies palette materials by name prefix (add attribute `KeepLook = true` on a part to keep your own textures). The meshes upload to your Roblox account during import, which is normal and lets them load in your experience.

| Generated mesh | Triangles | Scale (studs) | Where it's used |
|---|---|---|---|
| `PalmTree` | 9,876 | about 13 × 18 × 13 (scaled per site) | atrium planters, plaza, corridor |
| `Fountain` | 7,648 | Ø 23.4 × 12.2 | atrium centre (spray stays procedural) |
| `Column` | 7,680 | Ø 4.4 × 48 | 8 atrium balcony columns |
| `PlanterBench` | 3,744 | Ø 9 × 2.8 | 6 seating islands around the fountain |

## B. Assets still needing Blender (prioritised by visual gain)

All dimensions in studs (1 stud ≈ 28 cm). The pivot doesn't matter (base is auto-aligned). Name parts with material prefixes or use SurfaceAppearance with `KeepLook = true`.

| Pri | Asset name (exact) | Purpose | Geometry budget | Textures | Scale | Integration |
|---|---|---|---|---|---|---|
| A | `ShadowCrawler` | Enemy model with authored look | ≤ 6k tris, rigged | 1× 1024² (body, emissive eyes) | 4 L × 3 H | `assets/`; must keep `HumanoidRootPart`, `Humanoid`, Motor6Ds `BodyJoint`, `Hip1..6`, `Knee1..6` (or ship Animator clips, section C) |
| A | Storefront kit (`ShopFront`) | Mullions, kickplate, fascia, lightbox with bevels | ≤ 3k tris | trim sheet 1024² | 31 W × 20 H × 1.5 D | replaces the storefront section of `ShopUnit.luau` (code hook to add) |
| A | `Mannequin`, `PlushBear`, `GadgetDisplay` | Window and fixture hero pieces | ≤ 2k each | 512² each | 7.5 H / 4 H / 4 W | replaces `heroMannequin` / `heroPlush` / `heroGadget` |
| B | Merchandise set (10 per category) | Shelf stock items | ≤ 300 each | shared 1024² atlas | ≤ 2 × 2 × 2 | stock slot builder `PRODUCT_BUILDERS` |
| B | `KioskCart` | Atrium carts | ≤ 3k | 1024² | 7.4 × 9 × 4.4 | `Props.kioskCart` |
| B | `Bench` | Mall bench (must include a `Seat` part) | ≤ 1.5k | 512² | 6 × 3.5 × 2 | already hooked in `Props.bench` |
| B | `PottedPlant` | Dressing | ≤ 1.5k | 512² alpha leaves | Ø 3 × 4 | already hooked |
| B | `GlassDome` | Dome with bevelled steel ribs | ≤ 8k | none (built-in Glass/Metal) | Ø 92 × 45 | already hooked |
| C | Escalator shell | Balustrades, truss | ≤ 4k | 1024² | 7.4 × 24 × 42 | treads stay animated parts |
| C | Food court and arcade kits | Phase 4 areas | per prop ≤ 3k | trim sheets | — | new area builders |
| C | Night Stalker, Phantom Shopper, Security Nightmare, Mall Warden | Roster | ≤ 8k each (boss ≤ 15k) | 1024²–2048² | — | `src/server/Enemies/` |

**Textures to upgrade the built-in materials** (MaterialVariant, uploaded via the Material Manager): Marble (colour + normal + roughness, 1024², tiling 8 studs), WoodPlanks (walnut, 1024²), DiamondPlate (escalator treads). Use CC0 sources (ambientCG, Poly Haven) and log each in a `LICENSES.md`.

**Icons:** one 1024² sheet of 64 px glyphs (cash, XP, stock, shop, settings, flashlight, battery, fuse, moon, sun, trophy) in white on transparent, uploaded as an image. This replaces the emoji in `Hud`/`ShopPanel`.

## C. Animation list
| Asset | Clips | Status | Tool |
|---|---|---|---|
| Shadow Crawler | idle, skitter, lunge, stun, emerge, dissolve | **procedural, done** (client Motor6D) | Animation Editor later, for nuance |
| Customers | walk, idle | Roblox default clips | — |
| Customers | browse, pay, cheer, flee | missing | Animation Editor (R15) |
| Player | flashlight hold, sweep, repair-fuse | missing | Animation Editor; publish under your account or group |
| Environment | escalator treads, fountain jets, eyes, neon flicker, shafts, dust | **done** (local) | — |

## D. Audio list (all still placeholders: `AudioConfig.luau`)
| Slot | Mood | Integration point |
|---|---|---|
| Music.Day / Music.Night | city-pop lounge / low synth drone | `AudioController` crossfades on phase |
| Ambience.MallDay / MallNight | crowd and fountain / electrical hum | same |
| Sfx.UIClick, Purchase, LevelUp | UI feedback | `Components.button`, `UIController` |
| Sfx.PowerDown / PowerUp | dusk and dawn stingers | `AudioController` |
| Sfx.MonsterSpawn, MonsterHit, PlayerHurt | combat | `UIController` Effect handler |
| Missing slots to add | register "ka-ching", crawler skitter loop, fountain loop (3D sound on the fountain part) | small code hooks |

Only use audio you hold rights to (Roblox-uploaded library, your own uploads, licensed packs). Never paste an ID you haven't checked in the Creator Store.
