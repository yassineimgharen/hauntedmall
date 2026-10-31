# Studio harness: running it on the Windows laptop

The Lune tests run the real server code, but in a fake engine. This harness checks what only Roblox can show: real collisions, `PathfindingService`, raycasts, Humanoid walking, welds and conveyors.

**First real run (reported 2026-10-31): 39 passed, 1 failed.** The failure was `an escalator carries a character: 0,0,0`; see [Escalator check](#escalator-check). The rewritten check has not run in Studio yet. In the fake engine (`tests/StudioHarness.spec.luau`) only its logic is tested.

## Run it

1. Pull and build the QA place. It is the normal game plus one script:

   ```powershell
   git pull
   rojo build qa.project.json -o NightShiftQA.rbxl
   ```

2. Open `NightShiftQA.rbxl` in Studio. Leave **Enable Studio Access to API Services** off. The harness refuses to run if it is on, so it can't touch saved data.
3. Optional: to test only some levels first, select **Workspace** and add attributes:
   - `QA_Levels` (string), for example `L12,L14`. A first run on these two takes a few minutes.
   - `QA_Walk` (number), how many prompts per stage a real character walks to. The default is 3; 0 is fastest.
   - `QA_EscalatorsOnly` (boolean, ticked), only the one-off checks and escalator rides, about 2 minutes.
   - `QA_Riders` (number), wait for this many players and ride together. Use it with **Test → Clients and Servers**, and read the results in the Server window.
4. Press **Play (F5)**, keep the Output window open and don't move the character. The script steers it, and skips phases by itself.
5. Wait for `[QA] DONE: n passed, m failed`. A full run over all levels takes about 20 minutes (an estimate; it hasn't been timed).
6. Copy the lines starting `[QA] FAILED` back to me, or all the `[QA]` lines.

The published game never contains this script: `default.project.json` doesn't include it, and a test checks that.

## What it checks

| Check | How |
|---|---|
| Every enabled prompt has a route | The real `PathfindingService`, from the character to within activation range |
| Line of sight on prompts that need it | Real raycast from where the path ends |
| A real character gets there | `Humanoid:MoveTo` along the path, with real collisions, for the farthest few prompts of each stage |
| Monster spawn points | Floor below them, nothing solid inside them |
| NPCs and monsters move | Real Humanoids, sampled over 15 s |
| Bosses | L07 and L14: weak points on the body (welds really hold), a beam raycast really hits them |
| L12 ramp | A real path down the basement ramp (BUG-01) |
| Escalators | Every rider, both escalators: standing, walking with the belt, walking against it. Speed, climb, stepping off, teleports, jitter |
| Remotes | All created |
| World sanity | No parts at impossible positions |

## Escalator check

The first version of this check could not tell a broken escalator from a client that hadn't started. It ran as soon as the save data loaded, moved the character from the server, waited 1.5 s and compared positions. A character is simulated by its client, so with no client physics running yet the server sees it stay exactly where it was put. A delta of exactly zero means physics never touched the character: even a dead belt would leave gravity settling it on the slope. So that result says nothing about the belts either way. The old pass rule was also too weak: any rise counted, so a bounce would have passed.

The check now waits (up to 90 s) until gravity moves the character, and fails with its own message if that never happens. Then it times a full ride with samples every 0.1 s:

| Ride | Passes when |
|---|---|
| Standing | Reaches the end at 60–130% of belt speed, climbing or descending the right way, and ends up standing at the far end |
| Walking with the belt | Reaches the end at 1.5 × belt speed or more |
| Walking against it | Reaches the end, slower than the walking speed of 16 |
| All of them | No step over 6 studs between samples, under 1 stud sideways, under 1.5 studs of bounce. Standing riders also slip back under 0.5 studs |

These limits are first estimates and have not been checked against the real engine. Each result line prints the measured numbers, so a limit that is wrong can be told from a bad ride.

| What Output says | What it means |
|---|---|
| `...client is simulating the character` fails | The client never started within 90 s. No ride was measured, and it says nothing about the belts |
| `carries a standing character` fails with speed near 0 | Physics is running but the belt isn't carrying anyone: a game bug |
| Fails on biggest step, sideways or bounce | A carried rider that teleports or jitters |
| `stepped off false` | The rider got stuck or fell at the far end |

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
