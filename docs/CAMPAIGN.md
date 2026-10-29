# Campaign: Unique Day/Night Levels

_2026-10-28. Implemented: campaign framework + **all of Chapter 1 (Levels 1–7, incl. the Shadow Queen boss)**. Levels 8–42 are planned ("coming soon" in game). Nothing here has been run in Studio yet; see `TESTING.md` §C (1–2), §C2 (3–4), §C3 (5–7)._

## 1. Audit (before this change)
| Area | What existed |
|---|---|
| Clock | `GameStateService`: Intermission → (Day 150 s → Dusk → Night 120 s → Dawn) forever; server-wide `NightNumber` |
| Nights | Identical every time: waves + the same 3 fuse boxes; only stats grew (`EnemyConfig.Scaled`) |
| Day goals | 4 one-time tutorial flags (claim, stock, serve, upgrade) |
| Progress | XP/levels, upgrades, collectibles, stats. **No levels, no completion rules, no failure**: waiting out the timer was the only "progress" |

## 2. How it fits together
```
GameStateService (shared clock, never stops)
  └─ phase hook ──▶ MissionService picks the level at sunrise, sets that level's Day/Night lengths
MissionService
  ├─ one objective tracker per stage (CampaignLogic, unit-tested)
  ├─ level modules (src/server/Levels/*): spawn/clear stage props, e.g. PowerGrid
  ├─ GetNightRules() ──▶ NightService (waves, breakers, blackout, patrols, guards)
  └─ persists data.Campaign; MissionState / MissionResult remotes to clients
Game systems ──MissionEvents.record(player, "Served")──▶ MissionService
```
| File | Role |
|---|---|
| `src/shared/Campaign/CampaignConfig.luau` | All 42 levels: names, teasers; for implemented ones objectives, rules, durations, rewards |
| `src/shared/Campaign/CampaignLogic.luau` | Pure rules: objective tracking, unlocks, vote pick, outcomes, rewards |
| `src/server/Services/MissionService.luau` | Runs the active level; credit, rewards, persistence, votes, Studio helpers |
| `src/server/Levels/PowerGrid.luau` | Level 2 mechanic (depot, panels, lamps, lamp light pools, patrol points) |
| `src/server/Levels/MissingDelivery.luau` | Level 3 day: clue trail, storage cages, stolen crates, delivery van |
| `src/server/Levels/Impostors.luau` | Level 3 night: real vs Phantom shoppers, stalking, unmasking by flashlight |
| `src/server/Levels/SecuritySystem.luau` | Level 4: cameras, terminals, alarms, barricades; night strike groups and lures |
| `src/server/Levels/Carry.luau` | Shared "carry one item" helper (fuses, lamps, crates, planks) |
| `src/client/UI/Screens/CameraFeed.luau` | Security camera viewer (Level 4 nights) |
| `src/server/Util/MissionEvents.luau` | Event bus from game systems to missions |
| `src/client/MissionClient.luau`, `UI/Screens/CampaignPanel.luau` | Objective snapshot store; campaign map (key **M**) |
| `tests/Campaign.spec.luau` | 14 Lune tests (content validation + rules) |

### Objective kinds
| Kind | Completes when | Example |
|---|---|---|
| `Count` (Player or Team scope) | its event reaches `Target` | "Repair the electrical panels (4)" (Team) |
| `Survive` | the stage ends | "Survive until dawn" |
| `Avoid` (Player or Team, with `Allow`) | the stage ends with the event happening at most `Allow` times | "Shoppers lost (max 2)" (Team), "Don't get knocked down" |

Every objective is driven by a real game event (`CampaignConfig.Events`); there are no text-only objectives. A new mechanic means a new level module plus events, with no changes to the core.

## 3. Level 1 vs Level 2: what actually differs
| | Level 1 | Level 2 |
|---|---|---|
| **Day objective** | *First Shift*: claim, order stock, serve 3, buy an upgrade (personal) | *Power Failure*: **carry** spare fuses from a maintenance depot to **4 sparking panels** around the mall (incl. the upper level and the far East Wing); **carry and place 3+ emergency lamps** (team) |
| Day environment | normal day | day lights **flicker** until all panels are fixed; depot, panels and glowing lamp rings appear |
| Day length | 150 s | 240 s |
| **Night challenge** | *First Contact*: equip the flashlight, burn a crawler, survive | *Total Blackout*: **restore 3 breakers** (5 s hold each) before dawn |
| Night lighting | standard night | **Blackout preset** (near-black); mall neon and uplights off; each restored breaker re-powers **its zone** (atrium / upper level / East Wing); the 3rd brings everything back and stuns all crawlers |
| Enemies | small waves (≤ 4 alive), no breakers to fight over | **3 guards** start at the breakers; 60 % of crawlers **patrol** halls and breakers instead of raiding shops; sight −25 % in the dark |
| Day → night link | none | lamps placed in the day become **light pools** that burn crawlers (lamps near the breakers make repairs safer; the 5-lamp bonus means a safer night) |
| Failure | night: no crawler burned | night: breakers not all restored by dawn |
| Optional | serve 6; team defeats 6; don't get downed | place all 5 lamps; serve 3; power back before midnight; burn 3; don't get downed |
| Reward (first clear) | $150 · 200 XP | $250 · 300 XP |

The unit test "day 2 / night 2 share no required objective events with day 1 / night 1" enforces that the required objectives never repeat.

## 3b. Levels 3 and 4
| | Level 3 | Level 4 |
|---|---|---|
| **Day** | *The Missing Delivery*: **investigation**. A 3-clue trail (only the current clue exists) runs from the empty van in the plaza, through the atrium, to the upper level. The last clue names one of **4 storage cages** (random each time). Then **carry the 4 stolen crates** back to the van; each crate also gives the carrier's shop +6 stock | *Security Upgrade*: **repair 4 cameras** (one on the upper level), **activate 3 terminals**, **arm 2 alarms**, and **barricade your own shop door** with planks from the hardware depot (personal) |
| **Night** | *Impostors*: 9 identical shoppers, **5 real, 4 Phantoms**. Phantoms blend in, then **stalk** a real shopper (who panics: "😰 Someone's following me!"); they **glitch** and **stare** at you. 1.5 s of beam **unmasks** one into a pale **Phantom Shopper** enemy; burn it. Lighting a real shopper for 0.8 s is a false accusation | *Mall Under Attack*: every 30 s a **strike group** marches on one **terminal**; a 🚨 alert names it. Terminals have health bars. **View Cameras** at a terminal shows the repaired cameras. **Armed alarms lure** every crawler within 90 studs for 8 s (25 s cooldown). **Barricades absorb raids** before stock is lost |
| Day → night link | the cleared day unlocks the level; recovered stock helps your shop | everything you set up is what you have: no cameras = no feeds, unarmed alarms can't sound, no barricade = raids hit stock |
| Failure | more than 2 real shoppers taken, or fewer than 4 Phantoms destroyed | more than 1 terminal destroyed |
| Optional | search all cages; carry 2 crates; lose no shoppers; never light a real shopper | barricade 3 shops; lose no terminals; repel 4 attacks; use an alarm; check the cameras |
| New enemy | **Phantom Shopper**: pale, translucent, cyan eyes; 30 HP, faster wind-up (0.5 s) and short cooldown, still slower than players | none (crawlers get a new behaviour: marching on objectives, being lured) |
| Reward | $350 · 400 XP | $450 · 500 XP |

## 3c. Levels 5, 6 and 7
Each day and night introduces a mechanic no earlier level used. The spec test "no implemented level repeats a required objective event" enforces that no required objective is reused.

| | Day | Night |
|---|---|---|
| **5** | *Restricted Access*: **timing hazards plus a code puzzle**. 3 glass booths (NE atrium, SW atrium, mid East Wing), each with 3 laser gates blinking on staggered timers (zap: 15 damage and knock-back). The access card at the back shows one digit. The vault (NW atrium) keypad wants the digits in a random colour order (keypad UI). Inside, the security records explain tonight | *The Stalker*: **stealth**. An unkillable blind hunter that tracks sound. The server measures each player's real movement: walking is heard from 45 studs, sneaking (Ctrl / C / 🤫, speed 7) from 10, standing still is silent, jumping from 30. It hunts anyone it hears within 18 studs, and a catch is telegraphed (0.9 s). Counter: **lockers** (hide up to 25 s), **radios** (lure it for 8 s), sneaking. Objective: silence 4 music boxes (3 s hold); getting caught more than twice fails. Red emergency lighting, a noise meter and a heartbeat when it's within 35 studs |
| **6** | *Final Preparations*: **free-roam collection, crafting, scanning**. 14 random scrap piles collected by walking over them (team pool); the workbench crafts floodlight kits (3 scrap each) carried to 3 tower spots; 3 wall markings are invisible until held in a flashlight beam for 2 s, and they reveal the boss's lore | *Rescue Mission*: **escort and extraction**. 4 cocooned shoppers (with guards) around the mall; cut one free (3 s) and it follows you, and if you fall anyone can lead it on. Hunter crawlers target escorted and waiting shoppers (80 HP). Bring 3 into the EVAC ring and lose at most 1. In the last 30 s the van is announced, and you must be in the ring at dawn. Day-6 floodlights burn crawlers around the ring |
| **7** | *The Warning*: **zone capture plus a light puzzle**. 3 light cannons charge while players stand in their rings (20 s solo, faster together). North of the fountain, rotating mirrors steers a visible beam; reaching the crystal reveals the boss and gives everyone present the **Prism Lens** (persisted equipment: +50 % light damage vs bosses) | *The Shadow Queen*: **boss** (rules in `Levels/QueenLogic`, unit-tested). HP 600 + 300 per player; she circles the fountain in a bubble shield that blocks all light. A charged cannon (hold E 1 s) drops it for 10 s, refills every flashlight and stuns her brood; while it's down no other cannon can fire. Cannons recharge on their own (25 s, faster with people in the ring), and lit rings burn crawlers. Phase 1: slow 3 s telegraphed slams, 1 crawler at a time solo. Phase 2 (below 66 %): double slams and darkness pulses (2 s warning, never during a shield window) that lock the cannons. Phase 3 (below 33 %): a sweeping floor beam to jump, with a "JUMP!" cue. Crawlers come from portals at least 24 studs from players and are always slower than players (tiers 2–4). Boss bar with live shield state and countdowns, damage numbers, hit flash. Victory brings dawn about 12 s later. First clear also pays the **Chapter 1 reward** ($1,000 · 1,000 XP · title "Queen Slayer") and marks the chapter complete |

## 3d. Chapter 2: the Haunted Food Court (Levels 8–14)
A new wing west of the atrium (`World/FoodCourt` and `World/FoodCourtDetail`, coordinates in `Layout.FoodCourt`). Each level is one module in `src/server/Levels/`; its pure rules (balance by player count, grids, puzzles) are in `Levels/FoodCourtRules` and `Levels/ChefLogic`, unit-tested in `tests/Chapter2.spec.luau`. The new monsters live in `src/server/Enemies/` and plug into `EnemyService` through `Kind` hooks (Build, Think, OnLit, OnKilled); their ability timings are in `Shared/Config/MonsterTuning`.

| | Day | Night |
|---|---|---|
| **8** | *Grand Reopening*: **clean-up and restore**. Mops from a janitor cart; scrub 8 of 12 black slime puddles; reopen 4 of 6 restaurants (shutter up, sign flickers on) | *Kitchen Nightmare*: **exorcism**. Appliances get possessed (3 at once solo, up to 6) and throw knives down telegraphed lanes (one volley per 1.6 s at most, server-wide). Light on one suppresses it and exorcises it (4 s of beam, shared). **Possessed Carts** aim (red lane, 1 s) and charge at 32 studs/s, then spin out dizzy |
| **9** | *Live Wires*: **timing**. Cables cycle LIVE (shock) / SAFE (3.2 s): splice in the safe window. Then two breakers 74 studs apart: pull one, then the other before the on-screen timer ends (10 s solo, 8 s in a team; re-pulling restarts it; failing resets both) | *Grease Fire*: **spreading hazard and escape**. A fire grid (8-stud cells, aligned to the kitchen wall, crossing it only at doorways) spreads over the kitchen and hall (cap 55 cells); new cells smoulder 2.5 s (warning) before flaming; extinguishers (8 sprays, a cross of 5 cells each, foam stays wet 25 s); 3 gas mains slow and then stop it and unlock the dock exit; escape onto the landing (personal); dawn 10 s after everyone is out |
| **10** | *Special Delivery*: **deduction**. Inspect labels against the manifest, check UV handprints with the flashlight, deliver (E) or quarantine (Q): 8 of 10 right. Logbook in the truck cab | *Return to Sender*: **hidden enemies**. **Parcel Mimics** disguised among decoy boxes (wake when you're near or light them, pounce at a circle, split into 2 **Parcel Mites**); 4 nests hatch more until burned. Day mistakes add mimics |
| **11** | *Cold Trail*: **light-revealed trail**. Invisible frost footprints, a lever frozen in ice, the false wall into the **hidden freezer** (cold meter, freeze at full), chip out 3 logbooks | *Deep Freeze*: **unkillable pursuer**. The **Frost Wraith** (light only slows it) chills you with its aura and breath; heat lamps hide you; melt the iced north exit with light (the noise lures it); escape (personal) |
| **12** | *Under the Floor*: **hot/cold scanner**. Basement maze (seeded): a 📡 meter leads to anomalies that appear up close; chalk arrows (pointing at the heart) persist into the night | *The Shifting Maze*: **changing layout**. Walls rearrange every 22 s (3 s red warning; every layout keeps all cells connected); crawlers patrol; 4 corner seals open the heart's portal (escape, personal) |
| **13** | *Fresh Air*: **duct crawl plus a logic puzzle**. Repair 3 fans at the ends of crawl ducts; airflow panel: 5 dampers in a ring, each flips 3 vents (every start provably solvable) | *Toxic Bloom*: **area denial**. Gas spreads between 6 zones; a personal gas meter; purge switches (30 s shield); oxygen tanks; **Spore Bloaters** exhale gas and burst into clouds when burned |
| **14** | *Patient Zero*: **rhythm plus crafting**. Sample growths between spits; brew the antidote in order (chop, boil, bottle); peek into the sealed kitchen (cutscene) | *The Gorging Chef*: **boss** (`ChefLogic`). Greased until he eats a **laced** dish at ORDER UP (cook → lace → serve); a plain dish heals him, an empty pass makes him ravenous. Sick for 12 s: burn him. Cleaver lanes, pan circles; phase 2 grease pools (slow) and **Meatballs**; phase 3 stove flares. HP 400 + 200 per player. A cinematic intro; victory brings dawn about 12 s later and the **Chapter 2 reward** ($2,000 · 2,000 XP · title "Head Chef of the Night"), once |

**Fairness rules the tests enforce:** every chaser is slower than a player (16); every telegraph can be stepped out of in half its warning time; flashlight tasks fit one battery; solo and team counts are capped (`FoodCourtRules`); bonuses that sound like "never X" are recorded as events (perfect sort, clean escape, clean air), so idling never earns them.

**Achievements** (`Shared/Campaign/AchievementConfig`): one-time cash and XP for feats (most tied to a level's optional objective) plus one per chapter. Saved in `data.Campaign.Achievements`, paid by `MissionService` after a stage (and on load for progress already made, e.g. Queen Slayer).

## 4. Completion, failure, retry
- **Day** (checked at dusk): if your required day objectives are done, `DayCleared[level]` is saved. This is permanent, so a failed night never forces you to redo the day.
- **Night** (checked at dawn): if the required night objectives are done and the day is cleared (now or earlier), the level is complete.
- **Fail:** the level stays your "next" level and is replayed at a later sunrise. The dawn banner says why (`LEVEL FAILED` or `DAY NOT CLEARED`).
- **Rewards:** full cash and XP on the first clear; 25 % on replays. Each optional objective gives +50 XP, once ever.
- **The clock never decides progress.** Waiting does nothing; only the objectives count.

## 5. Multiplayer rules
| Concept | Scope | Where |
|---|---|---|
| Day/night clock | server | `GameStateService` |
| Active level (mission) | server, fixed for one Day + Night | `ReplicatedStorage.LevelId` |
| Campaign completion, DayCleared | **per player**, persisted | `data.Campaign` |
| Player level / XP | per player | unchanged |
| Unlocked chapters | per player, derived from completion | campaign map |

- **Mission selection:** at each sunrise the server plays the level with the most votes. Your vote defaults to your own next level; change it in the campaign map (M). Ties go to the earliest level, so newer players aren't skipped ahead. Free Shift loses ties.
- **Party progression:** everyone plays the same level. You get credit only if that level is unlocked for you. Otherwise you're a **guest**: cash and XP still count, but no level credit, and the HUD says so.
- **Joining mid-round:** joining during the **day**, you can still clear it (team objectives already done count). Joining during the **night**, you can help, but there's no level credit that night (`LateJoin`), so nobody gets credit for a night they skipped.
- **Replays:** vote for any cleared level (reduced rewards).
- **Free Shift:** the classic endless loop (fuses every night, night-count scaling). It's the default after your last available level.
- **Existing saves:** the schema goes v1 → v2. Players who had finished the old tutorial day *and* survived a night get Level 1 credited (no rewards paid), so they start at Level 2.

## 6. Studio helpers
Set these as Workspace attributes in the Server view.

| Attribute | Effect |
|---|---|
| `MissionTest_Level` (string, e.g. `L02`) | plays this level from the next sunrise; credit is granted even if locked (Studio DataStore only) |
| `MissionTest_CompleteStage` (bool) | marks the current stage's **required objectives** complete. This only touches objectives: the world isn't changed, so e.g. the blackout lights stay off |
| `QueenTest_Phase` (number 2/3) | Level 7: the Queen starts in that phase |
| `FireTest_CloseValves` (bool) | Level 9: the night starts with the gas off and the exit open |
| `ChefTest_Phase` (number 2/3) | Level 14: the Gorging Chef starts in that phase |
| `FastPhases` / `SkipPhase` | as before. FastPhases scales level lengths too (Day 2 becomes about 72 s, too short to finish by hand; test Day 2 at normal speed) |

## 7. Six-chapter plan
Chapter 1 levels 3–7 follow your brief exactly. Each later level's mechanic is a new module on the same framework.

| Ch | Levels | Area | Days → Nights (summary) | Boss |
|---|---|---|---|---|
| 1 | 1–7 | East Wing | First Shift/First Contact · Power Failure/Total Blackout · Missing Delivery/Impostors · Security Upgrade/Mall Under Attack · Restricted Access/The Stalker · Final Preparations/Rescue Mission · The Warning/**The Shadow Queen** | Shadow Queen |
| 2 | 8–14 | **The Haunted Food Court (built)** | Grand Reopening/Kitchen Nightmare · Live Wires/Grease Fire · Special Delivery/Return to Sender · Cold Trail/Deep Freeze · Under the Floor/The Shifting Maze · Fresh Air/Toxic Bloom · Patient Zero/**The Gorging Chef** | The Gorging Chef |
| 3 | 15–21 | Underground Parking | mapping/headlight weapons · battery carry/stealth · cart puzzle/chase · substation/multi-level blackout · lost cars/rescue · barricades/defense · warning/boss | The Concrete Guardian |
| 4 | 22–28 | Abandoned Cinema | projector/haunted screens · reels/illusions · code puzzle/sound stealth · ushers/phantom audience · secret passages/timed puzzle · cursed reel/booth siege · premiere/boss | The Phantom Projectionist |
| 5 | 29–35 | Rooftop | traversal/wind · lightning rods/strikes · skylights/flyers · signal fires/rescue · crane/hail cover · beacon/storm peak · calm/boss | The Storm Wraith |
| 6 | 36–42 | Secret Laboratory | elevator/escape · lab notes/breach · keycards/adaptive enemies · revelations/mirror copies · reactor/meltdown escape · allies/nest assault · finale/multi-stage boss | The Night Manager |

Full per-level names and teasers: `CampaignConfig.luau`.

## 8. Limitations (honest)
- **Levels 15–42** (Chapters 3–6) are configuration and planning only. Clearing Level 14 shows "Level 15 … coming in a future update", and the server then defaults to Free Shift.
- **Chapter 2 has not been played in Studio.** Every prop position comes from layout math; walls, doorways and the basement ramp (38°) need a walk-through (`TESTING.md` §C4).
- The **Gorging Chef**, the five new monsters and the food court props are built from Roblox parts in code; sculpted meshes are listed in `ASSETS.md`. The Chef walks through solid props (no collision, so nobody gets stuck under him).
- Chapter 2 **audio** is still placeholder (`AudioConfig`): no sizzling fire, freezer hum, gas hiss or chef roar yet.
- **No audio assets yet.** The Stalker is about sound, but the game has no real sound IDs (placeholders in `AudioConfig`), so the noise meter and heartbeat pulse carry it visually. Adding footstep, music-box and radio sounds is the biggest feel upgrade available.
- **The Queen** is built from Roblox parts in code (crown, eyes, veil-wings, legs) with code-driven poses; a sculpted, rigged mesh is in `ASSETS.md`'s list.
- The **Prism Lens** and the **"Queen Slayer" title** are saved but not yet shown anywhere besides toasts (no inventory or nameplate UI yet).
- **Achievements** are paid and saved, but there's no achievements screen yet: you see banners and toasts, and the count is in the campaign data sent to the client.
- Day/night **music** for blackout and level stingers are still placeholders (`AudioConfig`).
- **Blackout zones** are by position: x ≥ 70 is the East Wing, y ≥ 18 is the upper level, everything else the atrium. Lights in unusual places may belong to the "wrong" zone.
- Positions for Levels 2–4 props (panels, lamp rings, van, clues, cages, cameras, terminals, alarms, barricades) come from layout math, not Studio. A prop clipping a wall or planter is possible; report the spot.
- Night shoppers use the default R15 walk animation and Roblox pathfinding; one may occasionally get stuck on a bench.
- The camera viewer is client-side: it shows what's really there, but players in other places don't see who is watching.
