# Status Report: Premium Visual Slice

_Last updated: 2026-10-27._

## Where things stand
| Stage | State |
|---|---|
| Foundation + gameplay slice | ✅ confirmed working by you in Studio |
| Phase 1 fixes (soft-lock, persistent goals, guide marker) | ✅ confirmed by you ("gameplay tested successfully") |
| **Premium visual slice** (this update) | ⏳ static checks pass; **not yet viewed in Studio** |
| Phase 2 core systems (inventory, missions, achievements…) | not started; queued after visual sign-off |

## Static checks (`scripts/check.sh`)
StyLua ✅ · selene 0/0 ✅ · luau-lsp no type errors ✅ · Rojo build ✅ · `scripts/meshgen.py` produces 4 OBJ meshes ✅ (triangle counts and bounds checked).

## This update
Full detail in `VISUAL_BENCHMARK.md` (audit, spec, budgets, gaps) and `ASSETS.md` (mesh import and asset specs).

**Modified:** `LightingPresets`, `Layout` (spawn facing), `Lobby` (detail hook, mesh hooks for Column/PlanterBench/Fountain), `Corridor` (detail hook), `ShopUnit` (storefront and interior rebuilt, same gameplay contract), `Props` (8 new props), `AssetRegistry` (auto-materials, base alignment, scale), `LightingController` (disables faded lights, per-light night brightness), `EnemyVisualController` (hit flash, lean, shiver), `ShadowCrawler` (eye trails), `Components` (panel sheen), client `init`.

**Added:** `LobbyDetail.luau`, `CorridorDetail.luau`, `AtmosphereController.luau`, `scripts/meshgen.py`, `art/meshes/*.obj`, `docs/VISUAL_BENCHMARK.md`.

**Gameplay untouched:** shop prompts and names, product slots, nav points, collision clearances along customer routes, services, data and remotes. Regression check V-8 in `TESTING.md` covers this.

## Missing external assets
The four hero meshes need a one-time import (`ASSETS.md` §A). Still needed: Blender creature rig, storefront kit, merchandise set, kiosk, MaterialVariant textures, icon sheet, all audio (`ASSETS.md` §B–D).

## Risks to check first in Studio
| Risk | What to look for | Fallback |
|---|---|---|
| Part count / FPS on the laptop | V-1, V-12 | Reduced effects; cut ring benches / grout (detail layers are isolated modules) |
| Sun shafts don't line up with the dome light | V-3 | Tweak `ClockTime` in `LightingPresets` (shafts follow the sun) |
| A customer snags on a new prop | V-8 | Report the shop and spot; props are placed off the nav routes by design |
| Importer merges or renames mesh objects | V-11 | Rename the parts with prefixes (`ASSETS.md` §A step 4) |
| Hero pieces facing the wrong way in windows | V-7 | One-line angle fix |

**Next:** your screenshots and FPS numbers. Then either polish the slice further or expand the look to the remaining areas, and only then Phase 2.
