# Status Report

_Last updated: 2026-10-28._

## Current: Level 10 fixes (Special Delivery / Return to Sender)
Static checks ✅ · unit tests 136/136 ✅ (79 Chapter 2, 21 Shadow Queen, 19 campaign, 17 receipts) · Rojo build ✅ · **Studio verification pending** (`TESTING.md` §L10).

**Confirmed from the code (no Studio run):**
1. **The day could become impossible.** One call per parcel and only correct calls counted, so 3 wrong calls capped it at 7 of the required 8 (and enough wrong calls locked the logbook too).
2. **Delivered parcels stayed solid and invisible,** with their tape floating. The truck's door was rotated 90°. A wrong call at 5 sorted repeated the "cab open" toast. Gamepad Y was both Quarantine and "open shop".
3. **Pounces hit through walls** (sight isn't required within 25 studs) and damage landed even if the mimic never arrived; at long range it couldn't cover the distance in time.
4. **The disguise didn't work:** only mimics had tape and labels, and they smoked and glowed purple while "hidden".
5. **Mimics could spawn inside walls** (random 5-stud offset beside corridor walls).
6. **Solo nests rarely hatched:** two sleeping mimics filled the cap of 2. Awake creatures with nobody nearby walked off to raid shops.

**Checked and fine:** the reward and unlock logic, nest light targets, objective events, and the save fallback (only its message was wrong).

**Fixed:**
- Wrong calls still cost you (a hatchling, no perfect bonus), but the parcel comes back with its UV showing.
- Labels say whether the sender is on the manifest and what to do after the UV check; popups for each result; handprints on the sides too; logbook label and a locked prompt with no hold.
- Pounce needs line of sight, its warning scales with distance, and it only hurts if the mimic really arrives.
- Real parcels look identical to mimics; sleeping mimics are anchored with no smoke or light (cheaper too); teeth, scrap burst, stand-up and gaping-flap animation; cardboard death puff.
- Fixed, tested spawn spots. Nests hatch awake mimics and only awake creatures count toward the cap. Creatures hunt the nearest player rather than shops.
- After the last nest, sleepers wake; once all are dead, dawn comes 10 s later.
- All levels: dusk and dawn messages now name exactly which objectives are missing.
- Studio save message now says no action is needed.

**Files:** `Levels/Deliveries.luau`, `Levels/FoodCourtRules.luau`, `Enemies/ParcelMimic.luau`, `Shared/Config/MonsterTuning.luau`, `Shared/Campaign/CampaignConfig.luau`, `Shared/Campaign/CampaignLogic.luau` (`unfinished`), `Services/MissionService.luau`, `Services/DataService.luau` (message), client `MonsterAnimations.luau`, `EnemyVisualController.luau`, `UI/Screens/Hud.luau`, `tests/Chapter2.spec.luau`, docs.

**Not changed, worth knowing:** Possessed Carts (Level 8) and Meatballs still use the default AI, so a cart with nobody nearby can wander toward owned shops.

---

## Previous: Level 9 fixes (switchboard, fire visuals, completion)
Static checks ✅ · unit tests 125/125 ✅ (68 Chapter 2, 21 Shadow Queen, 19 campaign, 17 receipts) · Rojo build ✅ · **Studio verification pending** (`TESTING.md` §L9).

**Your report: the day ended with "Reset the main switchboard" unchecked.** The completion logic itself worked: pulling both breakers within the window recorded the objective (now covered by tests). What made it near-impossible to finish:
1. **The guide arrow never pointed at the second breaker.** After you pulled one, it wasn't marked done, so the arrow kept targeting the breaker you were standing at, and the arrow hides within 7 studs. Nothing pointed down the corridor.
2. **No visible timer.** The 8-second window only appeared in a toast. Breaker A snapped back silently until a "too slow" toast, so walking back and forth never succeeded.
3. **Solo was tight:** 74 studs is 4.6 s of sprinting, plus the hold and turning round, inside 8 s.
4. **Day progress blocks the level (by design).** With the switchboard missed, the day isn't cleared, so completing the night gave "DAY NOT CLEARED" at dawn, Level 10 stayed locked and Level 9 stays your next level. Nothing said so during the night.

**Fire was hard to see:** the Inferno lighting was orange ambient light plus an orange tint plus thick orange fog, around orange fire tiles. Also a **real bug**: the grid's column 9 straddled the kitchen wall, so fire spread straight through it.

**Fixed:**
- **Breakers:**
  - Solo window 10 s (8 s in a team).
  - An on-screen countdown bar for everyone, and big labels on both breakers that count down.
  - A pulled breaker hands the guide arrow to the other one.
  - Banners for armed, success, "too slow" (with a retry hint) and timer restarted.
  - Pulling a held breaker restarts its timer.
- **Fire:**
  - Grey smoky lighting so the flames stand out.
  - Cells smoulder (dark red with smoke, harmless) for 2.5 s before bursting into flame.
  - Fire crosses the kitchen wall only at its doorways.
  - Fewer but bigger and brighter flames, black smoke on a third of the cells, light on a quarter (cheaper than before per cell).
  - Burnt floor stays charred.
  - Sprays show foam and steam, and foam marks the floor while it can't reignite.
  - Popups for fires out, sprays left, and "you're burning".
- **Night and completion:**
  - Gas-main labels are visible through walls and hide when shut; the toast lists the mains still open.
  - A green light column marks the exit once it opens.
  - Escaping gives a personal message: "completes at dawn", or a warning that the day isn't cleared.
  - Dawn comes 10 s after everyone is out.
  - The HUD's night hint says when the level can't complete (day not cleared) or is done and waiting for dawn. This hint applies to every level.

**Files:** `Levels/KitchenFire.luau`, `Levels/FoodCourtRules.luau` (switchboard state machine, smoulder stage, wall-aware spread, landing and all-escaped checks), `Shared/Config/LightingPresets.luau` (Inferno), `Shared/Campaign/CampaignConfig.luau` (L09 hint), client `MeterController.luau` (countdown), `UI/Screens/Hud.luau` (night hints), `tests/Chapter2.spec.luau`, `docs/TESTING.md` §L9.

---

## Previous: Chapter 2, the Haunted Food Court (Levels 8–14)
Static checks ✅ · unit tests 117/117 ✅ (60 Chapter 2, 21 Shadow Queen, 19 campaign, 17 receipts) · Rojo build ✅ · **Studio verification pending** (`TESTING.md` §C4).

**Added:** the food court wing (`World/FoodCourt`, `World/FoodCourtDetail`, `Layout.FoodCourt`); levels `GrandReopening`, `KitchenFire`, `Deliveries`, `HiddenFreezer`, `ShiftingMaze`, `Ventilation`, `GorgingChef`; pure rules `FoodCourtRules`, `ChefLogic`; monsters `PossessedCart`, `ParcelMimic` (and Mite), `FrostWraith`, `SporeBloater`, `Meatball` on a shared `Enemies/Rig`; `Util/Telegraph` (floor warnings); `Shared/Config/MonsterTuning`; `Shared/Campaign/AchievementConfig`; client `MonsterAnimations`, `MeterController` (cold/gas/signal meters), `CinematicController`, `FoodCourtFxController`; 7 lighting presets; `tests/Chapter2.spec.luau`.
**Changed:**
- `EnemyService`: per-type `Kind` hooks, `Burn` with `LightScale`, AI helpers.
- `CombatService`: the flashlight goes through `Burn`.
- `MissionService`: modules registered, achievements paid, campaign state carries achievements.
- `NightService`: level `SpawnTag`, floor warnings cleared at dawn.
- `DataService` and `CampaignLogic`: chapter keys are now strings ("1"); old numeric keys are migrated on load. A save holding only chapter 2 would otherwise be a sparse array, which DataStores can reject.
- `Lobby`: west doorway. The Level 2 west panel, a pair of lurker eyes and the wainscot moved out of the opening.
- Client: `BossBar` (Chef status), `BossFxController`, `UIController` (generic Banner/Popup/WorldPopup, payload-driven boss banners), `GuideController` (multi-step markers), `StealthController` (`MoveScale` slows), `EnemyVisualController` (per-type animations).
- `Carry` (mop, extinguisher, dishes); `CampaignConfig` (L08–L14, chapter 2 name).
**Balance found by tests during development:** the Level 9 breaker window grew from 7 s to 8 s (solo sprint 5.6 s); the Chef's HP and hunger cycle were cut (the simulated solo kill fell from 192 s to 135 s of a 240 s night).
**Next:** your Studio pass of §C4, then fixes. Chapter 3 only after Chapter 2 plays well.

---

## Previous: Shadow Queen boss fix (Level 7 night)
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
