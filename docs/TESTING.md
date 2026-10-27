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

## §V: Visual slice review (test this build first)

1. `git pull`, then rebuild (`rojo build default.project.json -o NightShift.rbxl`) or reconnect `rojo serve`.
2. **Before importing meshes**, play once and take the screenshots in `docs/VISUAL_BENCHMARK.md` §6. These capture the procedural look.
3. Import the four hero meshes (`docs/ASSETS.md` §A), stop, press Play again, and retake screenshots 1–3. This shows what the mesh pipeline adds.
4. Use `FastPhases` = true to reach night quickly, or `SkipPhase` in Server view.

Pass/fail:
- [ ] V-1 Output shows `[MallBuilder] built N parts` with no red errors. **Report N** (budget ≤ 6,000).
- [ ] V-2 You spawn facing north: fountain, palms and the **NIGHT SHIFT** neon sign are in view.
- [ ] V-3 Day: sunlight falls through the dome onto the floor with rib shadows; light shafts and dust are faintly visible; the atmosphere is warm, not washed out.
- [ ] V-4 Dusk to night: lights stutter, then columns and corridor pilasters get purple/cyan uplight washes; floors gain a sheen; spores drift; neon is saturated; paths stay readable.
- [ ] V-5 Night to dawn: shafts and dust return; uplights switch off.
- [ ] V-6 Corridor: dark runner with brass edges, soffit beams, two hanging signs, glowing ad panels between shops, flower beds, blade signs readable from the corridor mouth.
- [ ] V-7 Shop: lit display windows (plush / mannequin / demo screen per category), feature wall with logo, feature fixture, counter badge, crates on a pallet with a 📦 STOCK sign.
- [ ] V-8 **Regression:** claim, order stock, customer walks in and is served, upgrade, survive a night, all as before. Customers must not get stuck on new props; watch one full customer trip.
- [ ] V-9 Crawler: magenta eye trails while moving; white flash and shiver while lit; leans when chasing.
- [ ] V-10 Settings → Reduced effects ON removes shafts, particles, uplights and the hero-sign glow; turning it OFF restores them.
- [ ] V-11 After the mesh import: palms, fountain, columns and planter benches look smooth with correct materials, sit on the floor (not floating or sunk), and the fountain still sprays.
- [ ] V-12 Performance: Shift+F5 FPS at spawn by day and at night with enemies, at graphics level Automatic and at level 5.

## §P1: Phase 1 fix verification

Get the update with `git pull`, then rebuild with `rojo build default.project.json -o NightShift.rbxl`, or keep `rojo serve` connected. Set `FastPhases` = true.

**Onboarding & markers**
- [ ] P1-1 After pressing PLAY, a floating **🛍️ CLAIM A SHOP** marker with a distance is visible through walls, pointing at the nearest free shop's lease stand.
- [ ] P1-2 The goals panel shows **▶ Claim a shop…** in gold with a hint underneath.
- [ ] P1-3 The atrium storefronts with shutters all say **COMING SOON / 🔒 future update**. No real shop has a shutter.

**Stock (the soft-lock fix)**
- [ ] P1-4 Claim a shop. The marker moves to your **📦 ORDER STOCK** crates. Press E there: +10 stock for $30, products appear, and the goal ticks ✅.
- [ ] P1-5 **Soft-lock test:** with a fresh save (or after spending cash down to about $20), order stock. You should get a *partial* order (e.g. 6 units for $18), not a refusal.
- [ ] P1-6 **Emergency test:** spend down to $0–2 with empty shelves, then order stock. Expect "🚚 The supplier fronted you a free delivery". Ordering again right away with empty shelves and no cash should be refused (10-minute cooldown).

**Customers & register**
- [ ] P1-7 During the Day phase, a customer appears within about 25 s of stocking, walks into **your** shop, browses, and waits at the register with 💬.
- [ ] P1-8 You get a toast "💬 A customer is waiting…" and the marker switches to **💬 SERVE CUSTOMER**.
- [ ] P1-9 Press E at the register: you see "+$12 ★" above the till and the Serve goal ticks ✅. If nobody serves, the customer self-checks out after about 7 s.
- [ ] P1-10 If customers **never** appear, copy any `[CustomerService]` lines from Output. That is the top risk.

**Goals persistence**
- [ ] P1-11 Finishing all four day goals shows "🎓 Training complete! +$100" exactly once, and the panel becomes **DAILY ROUTINE** with a "Night falls in m:ss" countdown.
- [ ] P1-12 Sell out your stock: the "Order stock" goal stays ✅ (it used to un-tick).
- [ ] P1-13 At night the marker shows **⚡ REPAIR FUSE** over the nearest broken fuse box. The goal panel hints how to use the flashlight.

**Regression** (things you already confirmed)
- [ ] P1-14 Menu, spawn, movement, claiming, day/night, monsters, HUD and upgrades still work.

## §P: Testing persistence safely (separate private experience)

Use a **dedicated test experience**, so test data never mixes with the experience players will join:

1. In Studio: **File → Publish to Roblox As… → Create new experience** (e.g. "Night Shift TEST"). Keep it **private**; this is the default for new experiences.
2. **Game Settings → Security → Enable Studio Access to API Services → ON**. This lets Studio read and write that experience's DataStores. What that means:
   - Studio uses the test experience's real DataStore service, with the same request limits as live servers.
   - In this build Studio writes to `NightShift_PlayerData_v1_Studio`, never to the live store name, so even turning this on in the production experience would not touch real saves. Keep production's setting **off** anyway.
3. Press Play. The yellow "Studio test mode" line should **not** appear. The Output should have no `[DataService]` warning.
4. Earn cash, buy an upgrade, order stock, finish some goals. **Stop**, then **Play** again:
   - [ ] P-1 Cash, level, XP, upgrades, shop stock (after you re-claim a shop) and goal ticks are restored.
   - [ ] P-2 Collectibles: survive a night, note the rare find, rejoin, and check the 🏆 count in the shop panel.
5. **Shutdown flush:** earn some cash, then stop within 5 s (before autosave). Play again → [ ] P-3 the cash was kept (saved by `PlayerRemoving` / `BindToClose`).
6. **Session locking** can't be tested from Studio: Studio uses the separate `_Studio` store, and a lock conflict needs two live servers. It is code-reviewed only. It goes in the Phase 6 private-beta plan (server-hopping between two live servers with the same account).

Purchase records and receipt de-duplication arrive with monetization (Phase 5) and will get their own test plan using Studio test purchases (no real Robux).

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
