# Status Report

_Last updated: 2026-10-28._

## Current: Shadow Queen boss fix (Level 7 night)
Static checks ✅ · unit tests 57/57 ✅ (21 Shadow Queen, 19 campaign, 17 receipts) · Rojo build ✅ · **Studio verification pending** (`TESTING.md` §B7).

**Root causes found (from the code, before your report could be reproduced):**
1. The server tested the flashlight against **one invisible point** 2 studs under the scaled crawler's centre, with the normal 20° cone. Her glowing face and crown sat about 30° away from that point, so aiming at her face did nothing; only aiming at her lower body counted (`tests/ShadowQueen.spec.luau` reproduces this).
2. Her **spawn point and one of her waypoints were the fountain centre**, so whenever she was over it, that point sat inside the (procedural) fountain's solid centre column and the line-of-sight ray was blocked.
3. All her parts were non-queryable, so the **mouse aim ray passed through her** to the floor or wall behind.
4. Brood crawlers were **night tier 6**: walk speed 15.5 against your 16, 17.5 damage, 3 per summon, up to 10 alive, spawned 10 studs from the Queen (often next to you). Her slams also **ignored the hit grace**, so they stacked with bites.
5. The `Shake` effect was sent but **never handled** on the client, and the bar didn't update between hits clearly enough to see damage.

**Added:** `Levels/QueenLogic` (pure rules: shield, cannons, phases, damage, brood, spawns), `Shared/Util/LightCone` (sphere-vs-cone test), client `BossFxController` (damage numbers, hit flash, BLOCKED, camera shake), `tests/ShadowQueen.spec.luau`.
**Changed:** `Levels/ShadowQueen` (new model, orbit, poses, fair attacks, brood, victory → early dawn), `CombatService` (multi-part light targets, `Recharge`), `EnemyService` (`HitPlayer` with shared hit grace and 3 s respawn protection, `Stun`), `GameStateService` (`ShortenPhase`), `CampaignLogic.claimChapter` (used by `MissionService`), `BossBar`, `UIController`, `CampaignConfig` (L07 hint and marker).
**Next (after your test):** Chapter 2 (Food Court), once Level 7 plays well.

---

## Previous: Campaign Levels 5–7 (Chapter 1 complete)
Static checks ✅ · unit tests 36/36 ✅ (19 campaign incl. mirror puzzle, 17 receipts) · Rojo build ✅ · **Studio verification pending** (`TESTING.md` §C3; §C and §C2 are also still untested).

**Added:** `Levels/RestrictedAccess` (laser booths, vault keypad), `Levels/Stalker` (sound-hunting AI, noise, lockers, radios, music boxes), `Levels/Preparations` (scrap, workbench, floodlights, flashlight-scanned markings), `Levels/Rescue` (cocoons, escort, EVAC ring), `Levels/ShadowQueen` (cannon capture, mirror puzzle, Prism Lens, 3-phase boss), `Levels/MirrorGrid` (pure, tested), `Levels/NpcMover` (shared pathing), client `StealthController`, `KeypadPanel`, `BossBar`, lighting presets Hunt and Queen.
**Changed:** `CampaignConfig` (L05–L07, chapter reward), `MissionService` (BeforeNightEnd hook, chapter rewards, equipment/title sync), `NightService` (no-wave nights, per-level preset), `DataService` (Equipment, Title, Campaign.Chapters), `Impostors` (uses NpcMover), `Carry` (floodlight kit), `PromptController` (locker occupancy), `LightingController`, `UIController`, `Net` (`SubmitCode`).
**Next (after your test):** Chapter 2 (Food Court, Levels 8–14). It needs a new area to be built; best started once Chapter 1 has been played.

---

## Previous: Campaign Levels 3–4
Static checks ✅ · unit tests 34/34 ✅ (17 campaign, 17 receipts) · Rojo build ✅ · **Studio verification pending** (`TESTING.md` §C2; Levels 1–2 in §C are also still untested).

**Added:** `Levels/MissingDelivery` (clues, cages, crates, van), `Levels/Impostors` (real vs Phantom shoppers), `Levels/SecuritySystem` (cameras, terminals, alarms, barricades, strike groups), `Levels/Carry` (shared carrying), `CameraFeed` UI, Phantom Shopper enemy.
**Changed:** `CampaignConfig` (L03, L04, events), `CampaignLogic` (team "lose at most N" objectives), `EnemyService` (goals, lures, phantom builder), `ShadowCrawler` (phantom variant), `CombatService` (flashlight reveals registered targets), `CustomerService` (shared NPC factory), `ShopService` (stock gifts, raid shields), `NightService`/`MissionService` (phantom kills, failure toasts), `PowerGrid` (uses `Carry`), HUD, prompts, guide marker, `UIController`.
**Next (after your test):** Levels 5–7 (Restricted Access / The Stalker, Final Preparations / Rescue Mission, The Warning / The Shadow Queen boss).

---

## Previous: Campaign foundation + Levels 1–2
Static checks ✅ · unit tests 31/31 ✅ (14 campaign, 17 receipts) · Rojo build ✅ · **Studio verification pending** (`TESTING.md` §C).

**Added:** `Campaign/CampaignConfig` (42 levels, 6 chapters), `Campaign/CampaignLogic`, `MissionService`, `Levels/PowerGrid`, `Util/MissionEvents`, `MissionClient`, `CampaignPanel`, Blackout lighting preset, `tests/Campaign.spec.luau`, `docs/CAMPAIGN.md`.
**Changed:** `GameStateService` (level-driven phase lengths), `NightService` (rules per level: waves, breakers, blackout, guards, patrols), `EnemyService` (patrol, sight scale), `DataService` (schema v2, `Campaign`, Level 1 credit for veterans), `Shop/ProgressionService` (objective events), HUD (mission objectives, level titles), guide marker, prompts (carry-gated), lighting (zones, flicker), `UIController` (campaign window, key M, results).
**Fixed in passing:** `CombatService.luau` had been corrupted outside this session (7 lines replaced by dots); restored from git with your OK.
**Not built yet:** levels 3–42, chapter rewards, achievements, equipment unlocks (see `CAMPAIGN.md` §8).
**Next (after your test):** Phase 3 = Levels 3–4 (Missing Delivery / Impostors, Security Upgrade / Mall Under Attack).

---

## Previous: Focused fixes (spiders, escalators, closed shops)
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

## Previous: Monetization Phase 1 (secure foundation)
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
