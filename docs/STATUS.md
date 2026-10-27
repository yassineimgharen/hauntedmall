# Status Report

_Last updated: 2026-10-27._

## Current: Focused fixes (spiders, escalators, closed shops)
Static checks ✅ · unit tests 17/17 ✅ · Rojo build ✅ · **Studio verification pending** (`TESTING.md` §F).

| Issue | Root cause | Change |
|---|---|---|
| Spiders unescapable | Crawler speed 17 > player 16; bites landed instantly with no warning; no per-player damage limit (4 crawlers ≈ 40 dmg/s); no night scaling; no spawn protection | Night-1 speed 12.5, bite 10 with 0.6 s telegraphed wind-up (dodgeable), 1.8 s cooldown, 1.1 s per-player hit grace, knockback, warning flash, night scaling with caps (speed never above 15.5), smaller early waves, 3 s spawn ForceField |
| Escalators decorative only | Ramp was static collision; treads only animated visually | Ramp is now an anchored **conveyor** (`AssemblyLinearVelocity`): west carries up, east carries down, 7 studs/s; treads synced; ▲ UP / ▼ DOWN signs |
| "Closed shops" | Intentional: 16 atrium storefronts are decorative, reserved for a future expansion; never interactive or unlockable yet | Kept closed; added a "What's this?" info prompt on each, plus the Food Court gate |

Difficulty curve (solo, from `EnemyConfig`):

| Night | Crawler speed | Bite | HP | Sight | Wave | Max alive | Fastest possible down (10 hits ≥ 1.1 s apart) |
|---|---|---|---|---|---|---|---|
| 1 | 12.5 | 10 | 45 | 45 | 3 | 7 | ≈ 9.9 s |
| 3 | 13.7 | 13 | 57 | 55 | 7 | 11 | ≈ 7.7 s |
| 6+ | 15.5 (cap) | 17.5 | 75 | 70 | 13 | 14 | ≈ 5.5 s |

---

## Current: Monetization Phase 1 (secure foundation)
| Item | State |
|---|---|
| Static checks (StyLua, selene, luau-lsp, Rojo build) | ✅ pass |
| Receipt-processor unit tests (Lune, 17 scenarios, mutation-checked) | ✅ 17/17 |
| Studio run of the test store | ⏳ **not yet run.** `TESTING.md` §M |
| Real purchases | 🔒 closed by design (`Enabled = false`, Ids 0) |

**Added:** `MonetizationService`, `Monetization/ReceiptProcessor`, `DevStorePanel`, `tests/ReceiptProcessor.spec.luau`, `docs/MONETIZATION.md`, Lune in the toolchain.
**Changed:** `MonetizationConfig` (central catalog), `DataService` (serialised saves, `SaveNow`, `IsActive`, purchase ledgers), `ProgressionService.AddCash` (purchased vs earned cash), `Net` (`RequestPurchase`), server bootstrap, `UIController`, `check.sh`, `install-tools.sh`, `rokit.toml`.
**Next (after your test):** Phase 2: VIP benefits, cash-pack store, premium store UI. See `MONETIZATION.md` §7.

---

## Previous: Premium Visual Slice

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
