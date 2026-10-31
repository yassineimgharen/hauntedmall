# Studio harness: running it on the Windows laptop

The Lune tests run the real server code, but in a fake engine. This harness checks what only Roblox can show: real collisions, `PathfindingService`, raycasts, Humanoid walking, welds and conveyors.

**It has not been run yet.** Nothing in this repo has executed inside Roblox Studio. Only its logic has been smoke-tested in the fake engine (`tests/StudioHarness.spec.luau`).

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
| Escalators | A real character is carried by the conveyor |
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
