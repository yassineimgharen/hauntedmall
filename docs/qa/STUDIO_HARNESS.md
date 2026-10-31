# Studio harness: running it on the Windows laptop

The Lune tests run the real server code, but in a fake engine. This harness checks what only Roblox can show: real collisions, `PathfindingService`, raycasts, Humanoid walking, welds and conveyors.

**Current build: harness version 3.** The first line of a run says `[QA] Night Shift Studio harness version 3 starting`. A different number, or no version at all, means an old place file is open.

Studio runs reported so far, neither on this version: 39 passed, 1 failed; then six failures and a disconnect at L08 (below). That second run's `0, 0, 0` line and its ignored `QA_EscalatorsOnly` match the build before version 2, so it almost certainly used an old place file. In the fake engine (`tests/StudioHarness.spec.luau`) only the harness's logic is tested.

## Run it

1. **Close Studio first.** Studio keeps the file it opened, so rebuilding underneath it changes nothing. Then, in the repo folder:

   ```powershell
   git pull
   git log -1 --oneline
   Remove-Item NightShiftQA.rbxl -ErrorAction SilentlyContinue
   rojo build qa.project.json -o NightShiftQA.rbxl
   ```

2. Open that `NightShiftQA.rbxl` from that folder. Leave **Enable Studio Access to API Services** off: the harness refuses to run if it is on, so it can't touch saved data.
3. Optional: select **Workspace** and add attributes. A new build has none, so add them after every rebuild:

   | Attribute | Type | What it does |
   |---|---|---|
   | `QA_EscalatorsOnly` | boolean, ticked | Only the one-off checks and escalator rides |
   | `QA_From` | string, like `L08` | Resume: start at that level, run the rest, skip the rides |
   | `QA_Levels` | string, like `L12,L14` | Only these levels |
   | `QA_Walk` | number | Prompts per stage a character walks to. Default 3; 0 is fastest |
   | `QA_Riders` | number | Wait for this many players and ride together. Use **Test → Clients and Servers**, and read the **Server** window |
   | `QA_StageLimit` | number | Seconds a stage may take before it's given up on. Default 420 |

4. Press **Play (F5)**, keep Output open and don't move the character. Dragging the camera with the right mouse button is fine, and every 10 minutes or so it may stop an idle disconnect.
5. Check the first `[QA]` line for the version and your settings. Then wait for `[QA] DONE`, or `[QA] PARTIAL` if the run stopped early.
6. Copy all the `[QA]` lines back to me.

If a run dies, the Output has a `[QA] RESUME` line, or look for the last `[QA] LEVEL` line. Put that level in `QA_From` and press Play again.

## What the results mean

- **PASS / FAIL:** it was measured. FAIL is a problem to investigate, and may still be the harness's.
- **INCONCLUSIVE:** it couldn't be measured this time, such as a monster blocking every try. Not a pass, and not evidence of a bug.
- **`[QA] STAT`:** time, memory and instance count after each stage, to show a leak or a run nearing the memory limit.
- **`[QA] CLIENT`:** the helper script in the client: when it loaded, and when Roblox called it idle.

## The 2026-10-31 run: six failures and a disconnect

| Failure | Verdict | Why |
|---|---|---|
| Escalators `0, 0, 0` | Harness, old build | Only the old build can print that line |
| `QA_EscalatorsOnly` ignored | Old build | The old build doesn't have that setting |
| L01 Night 49.7 away; L03 Night 28.0 and 76.0 away | Inconclusive, harness flaw confirmed | The old walk carried on with a dead character's body and never said why it stopped. Monsters can kill it at night. Now: damage off while walking, retries, and it reports where it stopped and on what |
| L05 Day spawn at (-60, 3, 60) | Harness false alarm | The vault's wall really is within half a stud of the marker, but only monsters use it, only at night, and the vault is gone by then. Now checked at night only, and it names what it hits |
| L05 Night `Serve Customer`, `Order Stock` NoPath | Inconclusive | In the built geometry, every shop is open at the harness's agent size. Roblox's navmesh updates after parts change, and that stage had just changed many, but this is unproven. Now: retries at 5 and 15 s, a narrower agent, then a failure naming the shop and start point |
| Disconnect at L08 | Inconclusive | Nothing in the game's code kicks a player in this mode. Idle disconnect after 20 minutes and running out of memory on 8 GB are both possible. The old harness then waited forever for a character, which is why there was no `DONE`. Now: a summary and a resume line at once, plus client heartbeats and memory figures to settle it |

## Escalator check

A real result now comes in three layers:

1. **Server rider:** a test character the server simulates, with no client involved, on both belts. This is Roblox's physics acting on the belt directly. If this fails, the belts are broken.
2. **Client's view:** the helper script reports the belt speed the client sees, since a player's physics runs there. If layer 1 passes and this fails, the speed isn't replicating.
3. **Player rides:** standing, walking with the belt and against it. It first waits up to 90 s for gravity to move the character. A client that never starts is INCONCLUSIVE, because no ride was measured.

| Ride | Passes when |
|---|---|
| Standing, server rider or player | Reaches the end at 60–130% of belt speed, climbing or descending the right way, and ends up standing at the far end |
| Walking with the belt | Reaches the end at 1.5 × belt speed or more |
| Walking against it | Reaches the end, slower than the walking speed of 16 |
| All of them | No step over 6 studs between samples, under 1 stud sideways, under 1.5 studs of bounce. Standing riders also slip back under 0.5 studs |

These limits are first estimates and have not been checked against the real engine. Each result line prints the measured numbers, so a limit that is wrong can be told from a bad ride.

The published game never contains this script: `default.project.json` doesn't include it, and a test checks that.

## What it checks

| Check | How |
|---|---|
| Every enabled prompt has a route | The real `PathfindingService`, from the character to within activation range |
| Line of sight on prompts that need it | Real raycast from where the path ends |
| A real character gets there | `Humanoid:MoveTo` along the path, with real collisions, for the farthest few prompts of each stage |
| Monster spawn points | At night: floor below them, nothing fixed inside them |
| NPCs and monsters move | Real Humanoids, sampled over 15 s |
| Bosses | L07 and L14: weak points on the body (welds really hold), a beam raycast really hits them |
| L12 ramp | A real path down the basement ramp (BUG-01) |
| Escalators | Both belts: a server-simulated rider, the belt speed the client sees, and player rides. Speed, climb, stepping off, teleports, jitter |
| Remotes | All created |
| World sanity | No parts at impossible positions |

## What it can't check

Whether things look right, whether a level is fun or fair, UI, sound, and holding prompts: a server script can't press E. Those are the manual checks in `docs/TESTING.md`, §QA.

## Profiling (Studio)

No performance numbers exist yet: nothing here was measured on a real machine. To get them:

1. In Studio: **Test → Start** with 1 server and 2 to 4 players if the laptop can take it, else press **Play**.
2. Open **View → Script Performance**. Note the Activity % of `ServerScriptService.Server` during: a day with customers, the busiest night (L04 or L06), and both bosses.
3. Press **Ctrl+F6** for the MicroProfiler. Pause at a spike and look for `Heartbeat` and `Pathfinding` bars.
4. Press **Shift+F5** for frame rate and **Shift+F2** for the summary. **View → Developer Console (F9) → Memory** shows memory: compare the end of night 1 with the end of night 3 on one level; it shouldn't keep climbing.
5. Send me the numbers. On the i5 with 8 GB, Studio itself takes a lot of memory, so treat them as an upper bound.

See `docs/qa/QA_REPORT.md` for the code review and where to look first.
