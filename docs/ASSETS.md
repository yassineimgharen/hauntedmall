# 3D / Audio / Animation Asset Plan

## Honest status
The current world is **procedural "blockout-plus"**. It has correct scale, real materials, trims, glass, neon and full lighting, built from Roblox parts. It is a good stage for gameplay and lighting, but it is **not** equivalent to professionally modeled meshes. The pipeline below replaces it piece by piece without code changes.

## How replacement works (`AssetRegistry`)
1. Model in Blender (or build in Studio).
2. Import with Studio's **3D Importer** (FBX/OBJ/GLTF). Group the result into a **Model** with the exact name from the table below.
3. Set the pivot (PrimaryPart or Pivot) at **base center, facing −Z**.
4. Right-click the model → **Save to File** → `assets/<Name>.rbxm` in this repo.
5. Rojo syncs it to `ServerStorage.Assets`. Every place that prop is built now uses your model.

Budgets: hero props ≤ 5k triangles, small props ≤ 1k, textures 512² (1024² for hero props), one PBR SurfaceAppearance per material where possible. Use `CollisionFidelity = Box` or `Hull` for props, and set `RenderFidelity = Automatic`.

## Asset list

| Priority | Name (exact) | Used for | Method | Notes |
|---|---|---|---|---|
| A | `PalmTree` | Atrium + plaza palms | Blender | 2–3 variants; frond cards with alpha |
| A | `Fountain` | Atrium centerpiece | Blender | Pivot at basin center on the floor; keep the particle attachment points |
| A | `GlassDome` | Atrium roof | Blender | Pivot at dome base center, y = ceiling; glass + steel ribs |
| A | `ShadowCrawler` | Enemy | Blender rig → Studio | Must contain `HumanoidRootPart`, `Humanoid`, Motor6Ds named `BodyJoint`, `Hip1..6`, `Knee1..6` (or replace with Animator animations) |
| A | `Bench` | Seating | Blender | Must include a `Seat` part |
| B | Storefront kit | Shop fronts, facades | Blender modular kit | Mullions, header, sign board, shutter |
| B | Shelf kit + merchandise | Shop interiors | Blender | Plush, folded tees, boxed gadgets, ~10 items per category |
| B | `PottedPlant` | Dressing | Blender | |
| B | Escalator | Escalators | Blender | Treads stay separate parts so they keep animating |
| B | Register, crates, lease stand | Shop | Blender | |
| C | Food court kit, arcade cabinets | Phase 4 areas | Blender | Avoid the image-3 look: beveled, emissive screens, decals |
| C | Night Stalker, Phantom Shopper, Security Nightmare, Mall Warden | Phase 3+ | Blender rig + Animation Editor | |

Free tools: Blender (free), Roblox Studio Animation Editor (free). For textures, prefer your own or CC0 sources (ambientCG, Poly Haven), and keep a `LICENSES.md` entry for each.

## Animation list
| Asset | Animations | Tool |
|---|---|---|
| Shadow Crawler | idle, skitter, lunge-attack, stun, emerge | Procedural today; Animation Editor later |
| Customers | walk, idle (Roblox defaults today); browse, pay, cheer | Animation Editor |
| Player | flashlight hold, sweep, repair-fuse | Animation Editor, uploaded under your account or group |

## Audio list (all placeholders today: see `AudioConfig.luau`)
| Slot | Mood | Source |
|---|---|---|
| Music.Day | upbeat mall lounge / city-pop | Creator Store (Roblox-licensed) or commissioned |
| Music.Night | low synth drone, heartbeat pulse | same |
| Ambience.MallDay | crowd murmur, fountain | same |
| Ambience.MallNight | electrical hum, distant clanks | same |
| Sfx | UI click, purchase, level up, power down/up, monster spawn/hit, player hurt | same |

Only use audio you have the rights to: Roblox-uploaded library tracks, your own uploads, or properly licensed packs. Paste the `rbxassetid://` into `AudioConfig`.
