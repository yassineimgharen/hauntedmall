# Night Shift QA report

Written for: the game's developer, deciding what to test next on the Windows laptop.

**Nothing here ran inside Roblox.** Automated results are in [RESULTS.md](RESULTS.md), one report per level is in [levels/](levels/), and how to run the engine checks is in [STUDIO_HARNESS.md](STUDIO_HARNESS.md).

## Final run

- `scripts/check.sh`, complete: **700 tests: 700 passed, 0 failed, 0 skipped, none timed out** (about 15 minutes). Format, lint and types clean, Rojo builds OK.
- Extended randomized run on new seeds: **28 passed, 0 failed.** An earlier run of these seeds caught BUG-11 (seed 1011); that's fixed and it now passes.
- Studio harness: **not run.** Manual playtest: **not done.**

BUG-02 and BUG-04 affect every level, so the per-level tables don't count them.

## How much each kind of result proves

| Label | What ran | What it can't show |
|---|---|---|
| Static analysis | StyLua, selene, luau-lsp, Rojo build | Anything about behaviour |
| Unit-tested | Pure rule modules under Lune | How the rules connect to the world |
| Integration-tested | The real server code booted in a fake engine, with mock DataStores and hostile remote calls | Real engine behaviour |
| Simulated gameplay | That same server with bots on foot over the real day/night clock | Physics, real pathfinding, client scripts, feel |
| Studio engine-tested | `tools/studio/NightShiftQA.server.luau` in Studio: **not run** | |
| Manually playtested | A person in Studio: **not done in this QA pass** | |

The fake engine (`tests/harness/Engine.luau`) checks every class and property against Roblox's reflection data and builds the real 4,776-part world. It computes raycasts and walkable floor from those parts. It does not model physics, real Humanoids, the real pathfinder, networking or any client script.

## Bugs fixed

Each has a test that failed or was added against the fault, and stays in the suite.

| ID | Severity | Bug | Root cause | Fix | Test |
|---|---|---|---|---|---|
| BUG-01 | Critical | **Level 12 was impossible:** nobody could reach the basement | The 700×700 ground plate covered the top of the ramp | Ground split into four plates around the ramp hole (`World/Lobby`) | `World.spec`, and all of L12 |
| BUG-03 | High | **With 7 or more players, the extras couldn't clear L01 or L04** | 6 shops but `MaxPlayers` is 10, and those objectives need your own shop | Once every shop is taken, a player without one has their shop tasks covered and is told so (`NeedsShop`, `CampaignLogic.coverShopChores`) | `Campaign.spec`, `Players.spec` teams of 8 |
| BUG-04 | High | **A damaged save field could break services for that player** | `reconcile` only filled in missing fields, so `Stats = 12` stayed and later reads failed | Wrong-typed fields are replaced with defaults; good fields stay | `Persistence.spec` |
| BUG-09 | High | **L06: dying or idling at the entrance earned evacuation** | The player spawn is 10 studs from the ring, inside its 12-stud radius, and only position at dawn was checked | You must have gone 30 studs out since you last spawned; the balcony above no longer counts either | `LevelRules.spec` |
| BUG-10 | High | **Boss health stayed at full-team size after players left** (and didn't rise if they joined) | HP was set once at the start | `BossScaling`: keeps the health fraction, joins apply at once, leaves after 10 s | `ShadowQueen.spec`, `Players.spec` |
| BUG-08 | High | **L06 alone was far harder than any other level** | See below | Hunts send 1 crawler at a solo player, still 2 at a team | `LevelRules.spec` |
| BUG-02 | Medium | Monsters with no route asked the pathfinder on every AI tick (5 per second each) | No retry limit after a failed path | At most once a second | `World.spec` |
| BUG-05 | Medium | L05's music boxes had no guide arrow | No `Marker` | Marker added | `World.spec`, `Levels.spec` |
| BUG-06 | Medium | L06 crawlers could appear beside a player (6 studs seen) | Hunt and guard spawns ignored players | 15-stud clearance | `Levels.spec`, `Properties.spec` |
| BUG-11 | Medium | L04's strike groups could land on someone at their approach point (4.7 studs seen); L10, L11, L12 and L13 had the same gap | Those spawns ignored players. Found by a randomized run (seed 1011, team of 8) | `EnemyService.PlayerNear`: pick another spot, or wait until the player has moved | `LevelRules.spec`, `Properties.spec` |
| BUG-07 | Medium | L13's arrow could point at a clean zone, where purging is refused | Nearest switch, whatever its gas | Switches with gas are marked and the arrow prefers them | `LevelRules.spec` |

Many early failures were in my bots or the fake engine, not the game (for example, a wall counted as line of sight, enemies blocking the walk grid). Those were fixed there and aren't listed.

## Investigations

**L06 respawn exploit.** Confirmed, BUG-09. Stepping 30 studs out and back after a respawn does still count. That takes about 4 seconds on purpose: someone killed near the end can still get back, and it costs more than it saves.

**Boss health when players leave.** Confirmed, BUG-10. With a team of 4 and 3 leaving as the fight starts, the survivor won L14 10 of 12 times against the old 1,200 HP (600 for a true solo). With scaling it's 12 of 12, the same as a true solo. L07 was 12 of 12 both ways.

There's no leave-and-rejoin profit:
- The health fraction is unchanged through any number of changes, so nothing is healed or lost.
- The total beam time needed per player falls with every extra player, so sending people away never finishes a boss sooner.
- A leave only applies after 10 s, so a quick reconnect changes nothing.

**L06 solo difficulty.** Evidence of an outlier, from the same seeds on every level:

| Solo profile | L06 before | Every other level, before | L06 after (20 seeds) |
|---|---|---|---|
| Skilled | 5/8 | 8/8 | 19/20 |
| Average | 1/8 | 7/8 to 8/8 | 18/20 |
| Newcomer | 0/8 | 0/8 to 8/8 (L14 0/8, L13 3/8) | 12/20 |

A team of 2 cleared 20 of 20 before the change. Each hunt sent 2 crawlers whatever the team size, so one player had to guard the ring and fetch the next shopper at once. Teams are unchanged. **These are bots, not people,** so please judge the feel in Studio.

## Balance notes, not changed

- **L14 and L13 for slow learners:** the Newcomer bot (no dodging, hesitant) cleared L14 0/8 and L13 3/8. It's reasonable for a finale to demand dodging, and both can be retried. Worth watching in real play.
- **L03 solo:** the bots search blind rather than reading the Phantoms' tells, so their results understate a real player.
- **L09's solo breaker sprint:** the Slow bot misses it. It's meant to be a sprint: 74 studs in a 10 s window.

## Performance review (code review only: nothing measured)

No frame times, memory or network figures exist yet. The only real counts are from the generated world: 4,776 parts, 161 lights, 20 particle emitters, 38 prompts in the base world. Check these first with the steps in [STUDIO_HARNESS.md](STUDIO_HARNESS.md).

| Risk | Where | Why it could matter | Status |
|---|---|---|---|
| Pathfinding | `EnemyService` navigate, up to 14 monsters | `ComputeAsync` every 3 s per monster chasing out of sight | Reduced by BUG-02; the top thing to profile |
| AI tick | `EnemyService`, 5 Hz per monster, staggered; clones the enemy list every frame | Small garbage every frame | Low; easy to change if it shows |
| Beam | `CombatService`, 10 Hz: raycasts per player × light targets | Grows with team size times targets | Worth checking at 8 players on L08 and L10 |
| Boss motion | `ShadowQueen`, `GorgingChef`: one `CFrame` each `Heartbeat` on a welded rig | Replication of a large rig | Profile both bosses |
| Fire | `KitchenFire`: up to 55 burning cells with flames and smoke emitters | The heaviest visuals, on an 8 GB laptop and low-end clients | Highest visual risk; check L09 night |
| Lights | 161 lights in the base world | Client frame rate | Check on the laptop |
| Remotes | `AimUpdate` capped at 20/s per player, `MissionState` only when changed, at most 4/s | Bounded by design | Low |
| Growth over time | Telegraphs and level folders are destroyed | `Properties.spec` checks the instance count doesn't keep growing across shifts (server side, simulated) | No growth found; real memory unmeasured |

## What remains untested

Everything needing the real engine or a client:
- real physics and collisions, including rising L12 walls pushing a character out, which the simulation only approximates
- the real pathfinder, Humanoid behaviour, escalators and doors
- all client scripts: HUD, guide arrow on screen, keypad, cameras, sneak input
- server `ParticleEmitter:Emit` replication (L09)
- visuals, audio, feel and real frame rates
- real DataStores and purchases (deliberately never touched)
