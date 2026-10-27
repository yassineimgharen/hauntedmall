# Status Report: Phase 1 (gameplay verification and bug fixing)

_Last updated: 2026-10-27. Previous slice (foundation + vertical slice): built, and partly confirmed by you in Studio._

## Static checks (`scripts/check.sh`, run on Ubuntu)
| Check | Result |
|---|---|
| StyLua format | ✅ |
| selene lint | ✅ 0 errors / 0 warnings |
| luau-lsp types (Roblox definitions) | ✅ no errors |
| Rojo 7.7.1 build | ✅ |
| Roblox Studio runtime of **this update** | ⏳ **not run.** Needs your test (`TESTING.md` §P1) |

## What changed in this update
See `AUDIT.md` §3 for causes. Summary:
- **Fixed:** economy soft-lock (partial orders and an emergency delivery)
- **Fixed:** shift goals now persist on the server and never un-tick; older saves are backfilled
- **Fixed:** decorative shutters are always labelled "COMING SOON"
- **Added:** objective marker, step hints, "Daily Routine" goals, $100 one-time training bonus, customer-waiting toast, faster customers
- **Added:** separate `_Studio` DataStore so Studio tests can't touch live saves

Files touched: `EconomyConfig`, `GameConfig`, `DataService`, `ProgressionService`, `ShopService`, `CustomerService`, `NightService`, `Props`, `Hud`, `ShopPanel`, `UIController`, client `init`, and the new `GuideController`.

## Confirmed working by you (previous build)
Mall loads, main menu, spawn, movement, exploration, shop claiming, day/night cycle, monster spawning, HUD and goals, upgrade purchases.

## Still unverified in Studio (top risks first)
| Risk | Fallback if it fails |
|---|---|
| Customers never appear (`CreateHumanoidModelFromDescription` failing on the server) | Output shows `[CustomerService] could not create customer rig`; then ship a rig in `assets/` |
| Crawler legs don't animate (client `Motor6D.Transform` on a server-owned NPC) | Switch to Animator with Studio-authored animations |
| Crawler floats or sinks | Tune `EnemyConfig…HipHeight` |
| Flashlight damage or cone alignment | Tune `CombatService` `BEAM_OFFSET` |
| Frame rate at night on the laptop | Cut corridor lights / shadows |

## Not started (by plan)
Phase 2 core systems (inventory, missions, achievements, reputation, merchandise choice), Phase 3 visual upgrade, Phase 4 monsters and boss, Phase 5 monetization. **Waiting for your Phase 1 test results before starting Phase 2.**
