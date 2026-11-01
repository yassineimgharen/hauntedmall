# Studio harness: running it on the Windows laptop

The Lune tests run the real server code, but in a fake engine. This harness checks what only Roblox can show: real collisions, `PathfindingService`, raycasts, Humanoid walking, welds and conveyors.

**Current build: harness version 5.** The first `[QA]` line says `harness version 5 starting`. A different number means an old place file is open.

Version 5 and its L13 geometry fix haven't run in Studio yet. In the fake engine (`tests/StudioHarness.spec.luau`) only the harness's logic is tested.

## Two ways to run

| | **Run (F8)** | **Play (F5)** |
|---|---|---|
| What runs | Server only: no player, no client, no rendering | Server plus a real client |
| Who walks | A rider the server simulates, built with the game's `Rig`, sized and collision-grouped like a player | Your character |
| Checks | Prompt routes and line of sight, spawn points, collisions, walks, L12 ramp, belts, plus NPCs where any appear | All of those, plus monsters, bosses, the client's view of the belts, player rides |
| Can freeze or disconnect | No client to freeze or lose | Yes: that's what stopped earlier runs |

Run mode is the cheap way to cover all 14 levels. Anything it can't do says `SKIPPED`, which is never a pass.

## Run it

1. **Close Studio first.** Then, in the repo folder:

   ```powershell
   git pull
   git log -1 --oneline
   Remove-Item NightShiftQA.rbxl -ErrorAction SilentlyContinue
   rojo build qa.project.json -o NightShiftQA.rbxl
   ```

2. Open that `NightShiftQA.rbxl`. Leave **Enable Studio Access to API Services** off: in Play mode the harness refuses to run if it is on, and Run mode loads no player data.
3. Select **Workspace** and add attributes if you want them. Changing one doesn't need a rebuild; a rebuild loses them.

   | Attribute | Type | What it does |
   |---|---|---|
   | `QA_Batch` | number, 1–7 | Two levels: 1 = L01,L02 ... 7 = L13,L14. The run names the next batch |
   | `QA_Levels` | string, like `L12,L14` | Only these levels |
   | `QA_From` | string, like `L08` | Start at that level of the list |
   | `QA_Stage` | string, `Day` or `Night` | Only that stage |
   | `QA_EscalatorsOnly` | boolean, ticked | Only the one-off checks and belts |
   | `QA_Walk` | number | Prompts per stage a character walks to. Default 3; 0 is fastest |
   | `QA_Riders` | number | Wait for this many players and ride together. **Test → Clients and Servers**; read the **Server** window |
   | `QA_SessionLimit` | number | Play only: stop cleanly between levels after this many seconds. Default 900; 0 = never |
   | `QA_StageLimit` | number | Seconds a stage may take in all. Default 420 |

4. Press **F8** or **F5**. In Play, don't move the character.
5. Check the first `[QA]` line: version 5, the right `MODE`, your settings.
6. Wait for `[QA] DONE` or `[QA] PARTIAL`, then copy the Output.

## What the results mean

- **PASS / FAIL:** it was measured. FAIL is a problem to investigate, and may still be the harness's.
- **INCONCLUSIVE:** it was attempted and couldn't be measured, such as a time limit or a monster blocking every try. Not a pass, and not evidence of a bug.
- **SKIPPED:** this mode can't try it. Run it in Play.
- **`[QA] COVERAGE`:** at the end, every stage planned for the session: `COMPLETE`, `PARTIAL` or `NOT RUN`.
- **`[QA] CLIENT SILENT`, `CLIENT BACK`, `STALL`, `CLIENT-LOCAL`, `CLIENT-ERROR`, `STAT`:** evidence about freezes and disconnects.

A stage's clock is held while it's checked (`HoldPhase`, Studio only), so a slow check can't run out the day or night. If a stage ends anyway, the walk says so and is inconclusive. Every check has a time limit, and a stuck check costs only that check. Results print the moment they happen, so a run that dies keeps them.

## Keeping results across sessions

Save each session's Output as a text file in `qa-results/`, such as `batch3-play.txt`. Then `.tools/bin/lune run scripts/qa-studio-report.luau` merges them into `docs/qa/STUDIO_RESULTS.md`: per stage and mode, whether it's complete, with every failure, inconclusive result and disconnect. A later file's result for a check replaces an earlier one's.

If Studio itself dies, the lines should still be in its log files. This hasn't been tried on your laptop:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Roblox\logs\*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | Select-String "\[QA\]"
```

## Reported Studio runs

### Harness version 4 (`c5ca33d`), Run mode (F8): 196 passed, 2 failed, 1 inconclusive, 22 skipped, 36m53s

The first run to cover all 14 levels, with no disconnect. Verdicts come from the pasted failure lines and the code: the full Output log didn't reach me, so nothing else in that log has been reviewed.

| Issue | Verdict | Why |
|---|---|---|
| L10 Night: `NPCs and monsters move on their own`, 0 of 2 moved | **Harness bug, fix unconfirmed in Studio** | With nobody online L10 starts exactly 2 mimics, disguised and anchored until a player comes near. Hatched ones arrive 16 to 24 s in, then stand still with no player to hunt. The check counted what was there when it started and expected it to walk. Pathfinding was never involved. With a player, the old check would also have failed for the same reason |
| L13 Day: FanRoom2 and FanRoom3 `Replace Belt`, NoPath | **Game bug (level geometry), fixed; fix unconfirmed in Studio** | Those doors look at the fan's edge, 2.5 studs in. Room 1's door faces the fan, with 6 studs of floor. A character may squeeze past (a 2.7-stud gap, not tried) and the prompts have a 12-stud range with no line-of-sight rule, so by the numbers they work from the doorway, but the three fans are required, and the rooms shouldn't depend on that. Fans 2 and 3 now face their doors, like fan 1 |
| L05 Night: walk to `Hide`, the stage ended | **Harness bug, fix unconfirmed in Studio** | L05's night has no early end and no player to end it, and the harness only skips between stages, so its 200 s clock ran out mid-check. This run's lines have no timings, so that comes from ruling out everything else. The harness now holds a stage's clock while it checks it. No game logic problem found |

Also found while fixing these, in my test tools: the fake engine never lifted a monster to its hip height, so L11's wraith (hip height 3, spawned at height 3) never walked in any simulated run. Real Roblox lifts it. It's fixed, so L11's simulated nights are harder now and test more.

### Harness version 3 (`3a28b45`): 21 passed, 1 failed, stopped after 7m45s

| Issue | Verdict | Why |
|---|---|---|
| `Escalator2 (down): real physics carries a server-owned rider` at about 55 studs/s | **Harness bug, fix unconfirmed in Studio** | The rider was built by hand and left at the default R6 rig, which needs leg parts to stand, instead of `Rig.humanoid`'s R15. The belt runs at 7, so the extra speed isn't the belt's; gravity on a 30° slope is about 98 studs/s², enough for that speed in under a second. Real players passed on the same belt |
| `lacking capability LocalUser` | **Harness bug, fixed** | `VirtualUser` isn't allowed in a LocalScript. Removed |
| Disconnect during L01 Day | **Inconclusive** | See below |
| `HttpError: DnsResolve` | **Not explained** | Failed name lookups for assets. A local session doesn't need DNS to connect, so nothing ties this to the disconnect yet |

**The disconnect.** The last heartbeat was 307 s old at 7m45s, so the client went quiet at about 2m38s, five minutes before the connection dropped. A walk needing a second try fits a client that had stopped, since a client moves its own character, but it doesn't prove it.

| Possible cause | Status |
|---|---|
| Inactivity | Unlikely for this stop: 7m45s is well short of the 20-minute idle disconnect |
| Client freeze | Best fit, unproven. The Output should now show `CLIENT-LOCAL` lines stopping too, and any `froze` line |
| Network between server and client | Open. `CLIENT-LOCAL` lines still printing while the server says `CLIENT SILENT` would point here |
| Memory | No figures in the report. `CLIENT-LOCAL` and `STAT` lines now give them |
| Game client code | Every client loop was read and yields, so none hangs by itself. That's a code review, not a measurement |

### Earlier

- **Version 2 or older, stopped at L08, six failures:** that run's `0, 0, 0` line and ignored `QA_EscalatorsOnly` match the build before `d6e2ca8`, so it almost certainly used an old place file. L05 Day's spawn failure was a false alarm: the vault's wall is within half a stud of a marker that only monsters use, only at night, when the vault is gone. L01, L03 and L05 Night stayed inconclusive.
- **First run:** 39 passed, 1 failed, the escalator check before it could tell a loading client from a broken belt.

## Escalator check

1. **Server rider:** no client involved, on both belts. It's the game's own rig, so if it fails the belts or that rig have a real problem.
2. **Client's view (Play):** the helper script reports the belt speed the client sees, since a player's physics runs there.
3. **Player rides (Play):** standing, walking with the belt and against it, after waiting up to 90 s for gravity to move the character.

| Ride | Passes when |
|---|---|
| Standing, server rider or player | Reaches the end at 60–130% of belt speed, climbing or descending the right way, and ends up standing at the far end |
| Walking with the belt | Reaches the end at 1.5 × belt speed or more |
| Walking against it | Reaches the end, slower than the walking speed of 16 |
| All of them | No step over 6 studs between samples, under 1 stud sideways, under 1.5 studs of bounce. Standing riders also slip back under 0.5 studs |

These limits are first estimates, not checked against the real engine. Each result prints the measured numbers, so a wrong limit can be told from a bad ride.

## What it checks

| Check | How |
|---|---|
| Every enabled prompt has a route | The real `PathfindingService`, from the character to within activation range, every stage. Missing routes retry after 5 and 15 s, then with a narrower agent |
| Line of sight on prompts that need it | Real raycast from where the path ends |
| A character gets there | `Humanoid:MoveTo` with real collisions. The level's own prompts first; mall fixtures once per level |
| Monster spawn points | At night: floor below them, nothing fixed inside them |
| NPCs and monsters move | Real Humanoids, including any that arrive during the check. Each gets 15 s, stopping as soon as one has moved. A sleeping mimic isn't expected to move; with no player, nor is a mimic or mite. With only those it says SKIPPED (Run) or waits up to 45 s for one to wake (Play) |
| Bosses | L07 and L14: weak points on the body (welds really hold), a beam raycast really hits them |
| L12 ramp | A real path down the basement ramp (BUG-01) |
| Belts | See above |
| Remotes | All created |
| World sanity | No parts at impossible positions |

The published game never contains the harness or its client helper: `default.project.json` doesn't include them, and a test checks that. The QA place also uses cheaper lighting (Voxel, no shadows) to go easier on an 8 GB laptop, so judge visuals in the normal place.

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
