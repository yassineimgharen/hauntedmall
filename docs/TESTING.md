# Testing in Roblox Studio (Windows laptop)

## One-time setup on Windows (no admin rights needed)

1. **Install Git for Windows** if it isn't installed, then clone your GitHub repo.
2. **Install Rokit** (a user-local toolchain manager):
   - Download `rokit-*-windows-x86_64.zip` from https://github.com/rojo-rbx/rokit/releases
   - Extract it, open a terminal in that folder, and run `.\rokit.exe self-install`. Reopen the terminal afterwards.
3. In the repo folder run `rokit install`. This installs the pinned Rojo, selene and StyLua from `rokit.toml`.
4. Run `rojo plugin install` to install the Rojo plugin into Studio.

## Every test session

```powershell
git pull
rojo build default.project.json -o NightShift.rbxl   # fresh place file
rojo serve                                            # keep running for live sync
```

1. Open `NightShift.rbxl` in Studio.
2. In the **Rojo** plugin panel, click **Connect**. Code edits pushed from Ubuntu sync live after you `git pull`.
3. Optional fast loop: select **Workspace** → Properties → Attributes → add a boolean `FastPhases` = true. The day becomes 45 s and the night 60 s.
4. Press **Play (F5)**.

To test **saving**, publish the place once (File → Publish to Roblox, kept private). Then go to Game Settings → Security and turn on **Enable Studio Access to API Services**. Without this the game uses a memory store and the HUD shows a yellow warning.

To skip a phase while playing, switch to the **Server** view (Test tab → Current: Server) and set the Workspace attribute `SkipPhase` = true.

## Test checklist (please report pass/fail on each)

### A. Boot & visuals
- [ ] Output shows `[MallBuilder] built N parts` and `[NightShift] server ready` with no red errors. **Report N.**
- [ ] The title screen shows the NIGHT SHIFT logo over a slow camera orbit of the atrium. PLAY unlocks after a moment.
- [ ] Atrium: glass dome, balcony ring with neon underglow, fountain with spray, palms, benches, escalators with moving steps, 16 decorative storefronts.
- [ ] Both escalators can be ridden up to the balcony.
- [ ] Entrance plaza: marquee sign, canopy, palms, street lamps.

### B. Day loop (target: understood in the first minute)
- [ ] The goals panel lists 4 goals. The East Wing sign is visible from spawn.
- [ ] Walking to an empty shop shows a **Claim Shop** prompt on the lease stand. Claiming changes the sign to "<you>'s Toy Shop/Boutique/Gadget Hub" and lights the neon trim in the shop's accent color.
- [ ] The **Order Stock** prompt at the crates costs $30, products appear on the shelves, and the stock bar updates.
- [ ] About 3 s later the first customer walks in from the plaza, browses, and waits at the register with a 💬 bubble.
- [ ] Pressing **Serve Customer** at the register gives "+$12 ★" above the register (with tip). If you don't serve, they self-checkout after about 7 s for less money.
- [ ] Press **B** for the shop panel. Buying an upgrade deducts cash, updates the dots, and persists after rejoining.
- [ ] Other players can't see or use your Restock/Serve prompts.

### C. Night loop (target: satisfying within five minutes)
- [ ] At dusk the lights stutter and die, the sky sweeps to night, neon saturates, customers fade away, and the flashlight auto-equips.
- [ ] Banners: "THE MALL IS CLOSED", then "NIGHT 1".
- [ ] Shadow Crawlers emerge from the floor with purple smoke. Their legs animate as they move.
- [ ] Holding the mouse button (or the 🔦 button on touch, or R2 on gamepad) shows a light cone. Enemies in it spark and lose health, and the battery drains and then recharges.
- [ ] Getting hit flashes a red vignette with camera shake, and health drops. Death respawns you at the atrium after 5 s.
- [ ] Unattended shops get raided: the owner gets a warning and shelves empty.
- [ ] Fuse boxes (atrium east wall, balcony north wall, corridor end) spark red. Holding E for 3 s repairs one (it turns green). All 3 stun every shadow for 5 s with a "POWER RESTORED" banner.
- [ ] Lurker eyes appear in dark corners at night, blink, and vanish when you approach.
- [ ] At dawn every enemy dissolves, a sunrise plays, and the **Shift Report** shows kills, fuses, cash, XP and a possible rare find.

### D. Multiplayer (Test tab → Clients and Servers → 2 players; 3 max on 8 GB RAM)
- [ ] Each player can own one shop. Claimed shops show the owner's name to everyone.
- [ ] Two players beaming the same enemy both get kill credit.
- [ ] A player leaving frees their shop.

### E. Persistence (API access on)
- [ ] Earn cash, buy an upgrade, stop Play, Play again: cash, upgrades, level and stock are restored.

### F. Performance (please report numbers)
- [ ] Press Shift+F5 for the FPS and stats overlay. Report FPS in the atrium by day, and at night with about 10 enemies.
- [ ] Ctrl+F6 opens the MicroProfiler. Screenshot it if FPS drops below 45.
- [ ] Test tab → Device: emulate an iPhone/Android phone and check that the UI fits and the 🔦 button works.
- [ ] Try Studio's graphics quality slider at low levels to approximate weak devices.

## What to send back
1. The pass/fail list above
2. Part count, FPS numbers, and any red Output errors (copy the full text)
3. Screenshots: atrium by day, atrium at night, inside a shop, a crawler up close
4. Your verdict on visuals and fun, which gates moving on to Phase 3
