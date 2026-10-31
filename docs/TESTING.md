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

## §QA: Full QA pass: test this first

Automated results and what they do and don't prove: `docs/qa/QA_REPORT.md`. None of it ran in Roblox, so these are what only you can check.

**1. Run the engine harness (about 20 minutes, or a few for two levels).** Steps are in `docs/qa/STUDIO_HARNESS.md`. Short version:

```powershell
git pull
rojo build qa.project.json -o NightShiftQA.rbxl
```

Open it, leave API access off, press Play, and send me the `[QA]` lines.

**2. By hand, in the normal place, with `MissionTest_Level` set on Workspace:**

- [ ] **L12:** walk down the basement ramp into the maze (it was sealed before). Stand on a red line as walls rise: you should be pushed out, not trapped.
- [ ] **L06 night, solo:** does it feel hard but fair now that hunts send one crawler? Rescue 3 and stand in the ring at dawn: the level clears.
- [ ] **L06 evacuation:** die in the last 30 s and stay at the spawn: a message tells you to head out, and you get no escape credit. Walk 30 studs out and back: you do.
- [ ] **L07 and L14 with 2 or more players:** one leaves mid-fight. About 10 s later the boss's health bar number drops but its percentage doesn't move. Rejoin: it goes back up.
- [ ] **L13 night:** the arrow goes to a switch where there's gas. **L05 night:** the arrow goes to music boxes.
- [ ] **L01 with 7 or more players, if you can (Test → Start):** the extras get the "shop tasks are covered" message.

**3. Profile:** the steps are in `docs/qa/STUDIO_HARNESS.md`. L09 night, L06 night and both bosses first.

**Running the automated tests:** `scripts/check.sh` runs everything (about 15 minutes); `scripts/check.sh --fast` skips the long simulations. Then `.tools/bin/lune run scripts/qa-report.luau` rewrites `docs/qa/`.

## §L10: Level 10 fixes (Special Delivery / Return to Sender): test this first

Setup: Workspace `MissionTest_Level` = `L10` (string) before Play, no `FastPhases`. Don't use `MissionTest_CompleteStage` if you want to test real completion. Studio saving is off (`StudioAccessToApisNotAllowed` in Output is expected, and the HUD says "saving is off"): leave API access off. Progress lasts for that Play session, so test Level 11 unlocking and replays within one session.

**Day: Special Delivery**
- [ ] L10-1 About 4 s in: banner "📦 MYSTERY DELIVERIES". The arrow leads to the loading dock (via a south restaurant's back door, then the service corridor). Ten parcels; a manifest board on the east wall behind the conveyor; the truck's side door is labelled "🔒 LOGBOOK: sort 5 more parcels".
- [ ] L10-2 Inspect a parcel (hold E 1.2 s): a label shows FROM (with "✓ on manifest" or "⚠ NOT ON MANIFEST"), TO, CONTENTS and "🔦 Shine your flashlight". A tip pops up the first time.
- [ ] L10-3 Press 1 and shine on it: "✓ UV CLEAN" or "☣ UV HANDPRINT!" floats up, the label's last line says what to do, and infected parcels show purple handprints on top and sides. Check a conveyor parcel too. The Avocados and Mozzarella parcels look legitimate but are infected.
- [ ] L10-4 Correct call: "📦 DELIVERED ✓" (it fades and **leaves nothing behind you can bump into**) or "☣ QUARANTINED ✓" (box turns red). The objective and toast count up (n/8). The arrow moves on to another parcel.
- [ ] L10-5 **Wrong call on purpose, 3 times or more:** "❌ WRONG CALL", a toast explains it, the parcel stays with its UV line showing, and 1.5 s later you can call it again. **You can still reach 8/8** (before this fix, 3 wrong calls made the day impossible).
- [ ] L10-6 After 5 correct: the truck door label turns gold, "📓 DRIVER'S LOGBOOK: READ ME". The door sits flat on the truck's side. Hold E 2 s: a banner and toast show the log. Before 5, the prompt says "Locked: sort n more". After 8: banner "DELIVERIES SORTED" if the log isn't read yet.
- [ ] L10-7 Leave something undone until dusk: the toast names exactly what's missing, e.g. "Sort the deliveries correctly (5/8)". The night's HUD hint warns the level can't complete.

**Night: Return to Sender**
- [ ] L10-8 Purple nest labels show through walls. The arrow leads to the nearest. Nests: loading dock, service corridor, Taco Eclipse, Lucky Wok. Hold your flashlight on one: the bar fills in about 6 s, "🔥 NEST BURNED!", toast "(n/4)", objective counts up.
- [ ] L10-9 Disguise: boxes around the hall all look **identical** (tape, label, flaps), no smoke, no glow, no movement beyond the faintest breathing. Walk up to them until one bursts: scraps fly, flaps open with teeth, it stands up on legs, shaking, with "😱 MIMIC!". Shining a light from afar also wakes it.
- [ ] L10-10 Standing behind a wall from a sleeping mimic shouldn't wake it (until you're within about 4 studs), and **it must never pounce or hurt you through a wall**.
- [ ] L10-11 Attacks: at mid range a purple circle fills under you while it crouches, then it leaps. Step out and you take nothing. Stay and you take about −16. Up close: flaps gape and eyes go red, then a bite.
- [ ] L10-12 Flashlight: sparks, flash and a health bar on the mimic; about 2 s to kill. It puffs cardboard smoke and two small mites appear (under 1 s to kill each). You can outrun everything.
- [ ] L10-13 Nests hatch awake mimics every ~25 s ("A Parcel Mimic hatched") up to 2 awake when solo. They come to you and don't wander off to the East Wing, even if you own a shop.
- [ ] L10-14 Burn the 4th nest: "🔥 ALL NESTS BURNED" and every sleeper wakes and hunts you. Kill them all: "✅ INFESTATION CLEARED", dawn about 10 s later. If you leave some alive, dawn just comes on time and the level still counts.
- [ ] L10-15 Dawn with day and night done: LEVEL COMPLETE (+$1,100 · 1,200 XP), "Level 11 unlocked". Day missing: "DAY NOT CLEARED". Nests missing: "LEVEL FAILED" naming what's missing. Keep playing in the same session: L10 again is "LEVEL REPLAYED" with a reduced reward.
- [ ] L10-16 FPS (Shift+F5) with several mimics awake. Please send the number.

**Short checklist for the Dell:** L10-3, **L10-5**, L10-6, L10-9, **L10-10**, L10-11, L10-12, L10-14, L10-15, L10-16.

## §L9: Level 9 fixes (switchboard, fire, completion)

Setup: Workspace `MissionTest_Level` = `L09` (string) before Play, no `FastPhases`. Play the day normally (don't use `MissionTest_CompleteStage` for the switchboard: it marks the objective but doesn't move the breakers).

**Day: Live Wires**
- [ ] L9-1 Each breaker in the maintenance corridor has a big label visible from far away: "🔒 BREAKER A · splice cables 0/5". It counts up as cables are spliced.
- [ ] L9-2 After the 5th cable: banner "🔌 CABLES SPLICED" telling you to pull BREAKER A and B; labels change to "⚡ BREAKER A · PULL" (gold), and the guide arrow points at the nearest breaker.
- [ ] L9-3 Pull one breaker (hold E 0.5 s): the handle flips, its light turns green, a banner "⚡ BREAKER A ON" appears, and a **countdown bar at the top of the screen** reads "⚡ PULL BREAKER B · 9.8s". Solo it's **10 s**, with 2+ players 8 s. The guide arrow now points at **the other** breaker, whose label counts down too.
- [ ] L9-4 **Success:** reach the other breaker in time: "✅ POWER RESTORED", the lights stop flickering, the countdown disappears, and the objective "Reset the main switchboard" ticks ✓. Solo, sprinting straight down the corridor should leave about 4 s to spare.
- [ ] L9-5 **Failure and retry:** wait out the timer: "⏱️ TOO SLOW: BREAKERS RESET", the handle flips back, and you can pull either breaker again straight away. Pulling the breaker that's already on restarts its timer ("TIMER RESTARTED").

**Night: Grease Fire**
- [ ] L9-6 Lighting is grey and smoky now (not all orange), so the fire stands out: bright orange-red floor glow, tall yellow-orange flames, black smoke columns, warm light from some cells.
- [ ] L9-7 Spread warning: a new cell first glows dark red with thin smoke for about 2.5 s (harmless), then bursts into flames. Fire crosses into the dining hall **only through the kitchen doorways**, not through the wall.
- [ ] L9-8 Standing in flames: −12 about once a second and "🔥 YOU'RE BURNING! GET OUT!". Burnt floor stays charred after the fire is gone.
- [ ] L9-9 Extinguisher: red cabinets labelled "🧯 EXTINGUISHER". Take one ("8 sprays"), then "Spray" (hold 0.4 s) at a fire: white foam and steam puff, "💨 3 FIRES OUT!", "🧯 7/8 sprays left". The foamed floor stays white for 25 s (can't reignite), then turns charred.
- [ ] L9-10 Gas mains: red labels visible through walls, e.g. "🔥 STORAGE GAS MAIN: ON". After shutting one, the toast lists the ones still open and that label turns green, then hides.
- [ ] L9-11 After the 3rd: "🚪 EXIT UNLOCKED", the dock barrier lifts and a **green light column** with "🚪 EMERGENCY EXIT" appears on the landing.
- [ ] L9-12 Walk onto the landing: "You escaped the fire!" plus a personal message: "the level completes at dawn", or a ⚠️ warning if your Day 9 wasn't cleared. The HUD hint says the same. When **everyone** is out: "🚪 EVERYONE'S OUT!" and dawn comes about 10 s later.
- [ ] L9-13 Dawn with day and night done: LEVEL COMPLETE (+$1,000 · 1,100 XP) and "Level 10 unlocked". Without the day cleared: "DAY NOT CLEARED" and Level 9 stays your next level. Replaying L09: "LEVEL REPLAYED", reduced reward.
- [ ] L9-14 FPS (Shift+F5) with the fire at its biggest. Please send the number.

**Short checklist for the Dell:** L9-3, **L9-4**, L9-5, L9-6, L9-7, L9-9, L9-11, L9-12, L9-13, L9-14.

## §C4: Chapter 2, the Haunted Food Court (Levels 8–14)

The food court is a new wing **west of the atrium**: walk through the big doorway under the gold "🍔 FOOD COURT ›" sign (west wall, opposite the East Wing).

**Setup for any level:** before Play, add the Workspace attribute `MissionTest_Level` = `L08` … `L14` (string). Don't use `FastPhases`. To skip a stage: Server view → `MissionTest_CompleteStage` = true, then `SkipPhase` = true twice (Day → Dusk → Night). Skipping a day only marks its objectives done; it doesn't change the world (for example, if you skip Level 11's day the false wall still opens at night). Extra helpers: `FireTest_CloseValves` = true (Level 9: the night starts with the gas off and the exit open) and `ChefTest_Phase` = 2 or 3 (Level 14: the boss starts in that phase).

**World (any level)**
- [ ] C4-1 Atrium west wall: a 24-wide doorway into a promenade, then the dining hall (checker-tile floor, skylight, a neon halo with "NIGHT BITES / FOOD COURT" signs, tables, booths). Six restaurants (3 north, 3 south) with lit signs and menus; the grand kitchen to the west; the walk-in freezer (NW), storage with a ⬇ BASEMENT ramp (SW), maintenance and service corridors, the loading dock with a truck, three green 🏃 EXIT doors and landings. Please report any **wall gaps, floating props or blocked doorways** with a screenshot and where you stood.
- [ ] C4-2 Crawl ducts: maintenance corridor north wall, storage west wall and dock west wall each lead (7 studs high) to a small fan room.

**Level 8: Grand Reopening / Kitchen Nightmare**
- [ ] C4-3 Day: every restaurant shutter is down and its sign dark. A yellow janitor cart near the promenade: "Take Mop". With a mop, slime puddles show "Scrub" (hold E 2 s), then a puddle fades with "✨ CLEAN!". Yellow switch boxes beside each shutter: "Reopen" (hold 2.5 s) raises the shutter and the sign flickers on. 8 puddles + 4 restaurants clears the day.
- [ ] C4-4 Night: all shutters fly open. Appliances turn purple, rattle, smoke and show "👻 POSSESSED" with a bar. A possessed one throws knives: a **pink lane** fills for 1.2 s, then knives fly down it (−12 if you're in it). Holding your flashlight on it fills its bar (4 s) and **stops it throwing while lit**. After about 25 s a possessed cart rolls out: it stops and shakes, a red lane shows its charge, then it races along it and spins out dizzy. 5 exorcisms + surviving clears the night.

**Level 9: Live Wires / Grease Fire**
- [ ] C4-5 Day: six yellow cable breaks with a label "⚡ LIVE 1.4s" (red, sparks) then "✅ SAFE 2.9s" (green). The Splice prompt only appears while SAFE; if it goes live while you're close you get zapped (−10). After 5, the two MAIN BREAKER levers in the maintenance corridor unlock: pull one, then the other within 8 s ("Too slow" resets them).
- [ ] C4-6 Night: fire cells (orange floor tiles with flames) spread from the kitchen over the hall. Standing in fire hurts (about −12 a second). Red 🧯 FIRE cabinets: take an extinguisher, then "Spray" (hold 0.4 s) puts out a cross of 5 cells. Three gas mains (kitchen west wall, storage east wall, freezer west wall): each slows the fire; after all 3 the dock exit's red "EXIT JAMMED" barrier lifts. Walk out onto the landing: "escaped the fire". The south restaurants never burn.

**Level 10: Special Delivery / Return to Sender**
- [ ] C4-7 Day: ten parcels at the dock, a manifest board on the east wall. "Inspect" (hold 1.2 s) shows a label. Shining your flashlight on a parcel adds "UV: clean ✓" or "☣ UV HANDPRINT!" (a purple handprint appears on it). Then **E = Deliver**, **Q = Quarantine**. Right calls count, wrong ones warn. After 5 the truck cab (side door) opens: "Read Logbook" shows a story banner.
- [ ] C4-8 Night: four pulsing purple nests (dock, service corridor, two restaurants) with bars: hold your flashlight on one (6 s). Ordinary-looking boxes around the hall: some are **Parcel Mimics** that burst open (legs, eyes, flapping lid) when you come close or light them, then pounce at a red/purple circle. Killed, each splits into two small mites. Infected parcels delivered by mistake in the day add mimics.

**Level 11: Cold Trail / Deep Freeze**
- [ ] C4-9 Day: sweep your flashlight over the floor at Frost Bite Creamery (north row, west end): glowing footprints appear and the arrow leads to the next one, through the back door, the maintenance corridor and the walk-in freezer to its west wall. A lever frozen in ice: light it (5 s) and the label says THAWED, then pull it: the wall section slides into the floor and reveals the hidden freezer (icicles, blue light). Inside, the 🥶 meter rises (about 25 s to full); full = frozen solid in an ice block for 2.5 s (−6). The heat lamp outside warms you fast. Chip 3 frozen logbooks (hold 3 s each): story toasts.
- [ ] C4-10 Night: a tall icy wraith comes out of the hidden freezer. Your light **doesn't hurt it**; it slows it and it shudders. Near it, the cold meter and blue screen edges rise. Frost breath shows a blue lane first. Standing in a heat lamp's orange ring makes it ignore you. The north exit at the end of the maintenance corridor is iced over: light it (about 20 s solo; the wraith comes to the noise), then walk out onto the landing.

**Level 12: Under the Floor / The Shifting Maze**
- [ ] C4-11 Day: take the storage room ramp down (it's steep, about 38°: tell me if you can't walk up or down it). The basement is a brick maze. A 📡 ANOMALY SIGNAL meter rises as you approach hidden anomalies; they appear (purple orb) within about 7 studs: "Record" (2 s). White chalk circles along the route: "Draw Arrow" leaves a glowing arrow pointing at the maze's centre.
- [ ] C4-12 Night: "THE MAZE IS SHIFTING" every ~22 s: red lines on the floor show where walls will rise, then walls rise and sink (camera shake). Crawlers prowl. Four purple seals in the far corners; after all four, the centre portal says "PORTAL OPEN": step in and you're back in the dining hall.

**Level 13: Fresh Air / Toxic Bloom**
- [ ] C4-13 Day: crawl to the three fan rooms (red light, "Replace Belt" 3 s, then the blades spin up). Then the AIRFLOW panel in the maintenance corridor: 5 gauges and 5 damper levers; each flip changes its gauge **and both neighbours** (ring). All five green clears it.
- [ ] C4-14 Night: green crack vents open, green fog thickens zone by zone, and the ☣️ meter and green screen edges rise in gas. Yellow PURGE switch per zone (hold 2.5 s) clears it for 30 s. Blue oxygen tanks: "Breathe" (−60% meter, 6 s cooldown). Floating spore bloaters swell (green circle) and exhale gas; burned, they burst into a cloud. The atrium and promenade have clean air.

**Level 14: Patient Zero / The Gorging Chef (boss)**
- [ ] C4-15 Day: five purple growths. A green circle fills before each spits (−10); "Take Sample" (2 s) only works between spits. With 4 samples, brew in Slice of Night (south middle restaurant): Chop → Boil → Bottle. Purple veins then glow to the grand kitchen's main door, sealed by a fleshy membrane: "Peek Inside" plays a short cutscene (letterbox, camera on the sleeping chef, "PATIENT ZERO").
- [ ] C4-16 Night: a cutscene (skippable with any key) shows the Gorging Chef (big chef: toque, cleaver, frying pan, glowing purple belly). Boss bar: "🧈 GREASED · ORDER UP IN 20s" and the pass status. Light on him: "🧈 GREASED" (blocked). The guide arrow walks you through: "🍳 COOK A DISH" (stove pots on the cooking lines, 2 s) → "🧪 LACE IT" (green vats near the doors, 1 s) → "🍽️ SERVE IT" (the serving pass by the west wall).
- [ ] C4-17 ORDER UP: he walks to the pass and eats. A laced dish makes him **SICK**: green glow, the bar turns green "🤢 SICK! BURN HIM NOW! (12s)", and your light now shows damage numbers. A plain dish heals him ("IT HEALED HIM"); an empty pass makes him RAVENOUS (red eyes, chases, chops faster).
- [ ] C4-18 Attacks: cleaver chop (red lane, then −22), thrown pans (red circles where you are and where you're running), phase 2 (66%) grease pools that slow you and meatballs, phase 3 (33%) both cooking lines flare (orange lanes). He never attacks while sick.
- [ ] C4-19 Victory: he shudders and topples. "CHEF DEFEATED", dawn about 12 s later, LEVEL COMPLETE, then "CHAPTER 2 COMPLETE +$2,000 · +2,000 XP · Title: Head Chef of the Night" and the 🏆 achievement banners (Food Court Hero; Queen Slayer if you didn't have it yet). Replaying L14 must **not** pay the chapter again.
- [ ] C4-20 Achievements: the first time a qualifying bonus is done, a gold "🏆 …" banner and toast appear with cash and XP. Rejoin: they're not paid twice.
- [ ] C4-21 Performance (Dell): Shift+F5 in Level 9's night with lots of fire, Level 13's night with fog, and Level 14's phase 3. Please send the FPS numbers.

**Short checklist for the Dell laptop:** C4-1, C4-3, C4-4, C4-6, C4-8, C4-10, C4-12, C4-14, C4-16, **C4-17**, C4-19, then C4-21. With 2 players (Test → Clients and Servers): C4-5 (levers split between two players) and C4-17 (one cooks, one burns).

## §B7: Shadow Queen boss fix (Level 7 night)

Setup: Workspace attributes `MissionTest_Level` = `L07` (string) before Play. **Don't** use `FastPhases` for this test: it shortens the boss night. To skip the day: Server view → `MissionTest_CompleteStage` = true, then `SkipPhase` = true twice (Day → Dusk → Night). If you skip the day, the cannons start empty but now recharge by themselves (about 25 s, faster standing in the ring). Optional: `QueenTest_Phase` = 2 or 3 (number) before the night starts her just past that phase's health threshold.

- [ ] B7-1 About 6 s into the night: "THE SHADOW QUEEN" banner. She's a new model (not a big crawler): crowned head with 6 glowing eyes, purple veil-wings, banded abdomen, legs dangling. She circles the fountain inside a purple bubble shield and faces the nearest player.
- [ ] B7-2 Boss bar: name and "PHASE 1/3", HP numbers on the bar, the purple "🛡️ SHIELDED: FIRE A LIGHT CANNON!" line and a hint naming how many cannons are ready. A gold arrow marker (🔆 FIRE CANNON) points to the nearest ready cannon.
- [ ] B7-3 Shine on her while shielded: "🛡️ BLOCKED" floats at her, the hint "fire a cannon first" appears (once as a toast), and the HP doesn't move.
- [ ] B7-4 Ready cannon: gold ring, glowing lens, label "🔆 READY: HOLD E". Hold E (1 s; gamepad X; mobile: tap/hold the prompt). A thick gold beam hits her and the bubble shatters with purple shards. Banner "SHIELD BROKEN!" and the bar turns green: "⚡ ATTACK NOW! SHIELD DOWN! (10s)" counting down. Your flashlight battery refills and crawlers freeze for 3 s.
- [ ] B7-5 **The core fix:** hold your flashlight on her (face, crown, body or tail all count): gold damage numbers float off her, she flashes white and jerks back, the bar blinks white and the HP number drops every hit.
- [ ] B7-6 In the last 3 s the bar turns gold: "⚠️ SHIELD RETURNING! (3s…)" and the bubble flickers. Then "Her shield is back up" and the HP stops dropping.
- [ ] B7-7 While her shield is down, other ready cannons show "READY (shield is down)" and won't fire: you can't waste them. Two players at two cannons at once: only one fires.
- [ ] B7-8 Phase 1: the first slam comes about 10 s after she appears: a red circle that fills up over 3 s while she rears up, then −20 and a purple shockwave and camera shake. The first crawlers arrive about 20 s in: solo just 1 (2 max alive), out of a purple portal far from you, never in a cannon ring. Crawlers that enter a lit cannon ring freeze and burn.
- [ ] B7-9 At 66% HP: roar, red eyes, "PHASE 2: GROWING DARKNESS" banner. "🌑 She's gathering darkness" plus "DARKNESS INCOMING" 2 s before the screen darkens; cannons then show "⛔ DARK" and the bar counts the darkness down. Darkness never starts while her shield is down. Double slams (solo: a second circle 1.2 s later where you dodged to).
- [ ] B7-10 At 33% HP: white-hot eyes, "FINAL PHASE". A faint purple disc plus a ghost bar shows for 2.5 s, then the bar sweeps one full turn in 8 s; "⬆ JUMP!" pops up just before it reaches you. Jumping clears it; standing gets −25.
- [ ] B7-11 Victory: she shudders, bursts into purple and gold shards, sinks and fades. "QUEEN DEFEATED" banner, crawlers vanish, no more attacks, the bar says "👑 DEFEATED!". **Dawn arrives about 12 s later** (the night timer jumps). Results: LEVEL COMPLETE (+$800 · 900 XP) and "CHAPTER 1 COMPLETE +$1,000 · +1,000 XP · Queen Slayer".
- [ ] B7-12 Replay L07 (set `MissionTest_Level` again on the same save): "LEVEL REPLAYED" with the reduced reward and **no** second Chapter 1 reward.
- [ ] B7-13 Respawn: after dying, nothing can hurt you for 3 s.
- [ ] B7-14 Performance (Dell i5-8th gen / 8 GB): Shift+F5 during phase 3 with the beam sweeping and crawlers out. Please send the FPS. Target: 40+ in Studio Play.

**Short checklist for the Dell laptop:** B7-2, B7-3, B7-4, **B7-5**, B7-6, B7-8, B7-11, then B7-14. Two-player test (Test → Clients and Servers → 2): B7-7.

## §C3: Campaign Levels 5–7 (test after §C2)

Shortcut: Workspace `MissionTest_Level` = `L05` / `L06` / `L07` before Play. Play days at normal speed (240 s). `MissionTest_CompleteStage` + `SkipPhase` jump to a night.

**Level 5: Restricted Access / The Stalker**
- [ ] C3-1 Day: 3 glass booths ("⚠ RESTRICTED · RED/GREEN/BLUE") with red lasers blinking in a rhythm. Walk through while a laser is lit: −15, knocked out of the booth, and ★ "Never trip a laser" fails. Time it and grab the card: toast "… card. It reads: N".
- [ ] C3-2 Vault (NW atrium): the keypad (E) opens a 0–9 pad showing the colour order and the digits found. Wrong code: "ACCESS DENIED", 3 s lockout. Right code: the door vanishes, the lamp turns green, and you can read the records inside (2 s hold).
- [ ] C3-3 Night: red lighting; a noise meter at the bottom; no crawler waves. After about 8 s, "You hear something tall…". The Stalker (tall, black, red mouth) wanders.
- [ ] C3-4 Press C (or 🤫): you walk slowly and the meter reads "quiet steps". Walking normally near it reads "LOUD", and it turns and rushes you (mouth glows). When it rears up you get the red "⚠ DODGE" flash. Getting caught does −45, "Times caught (1/2 max)".
- [ ] C3-5 Lockers: E "Hide" puts you inside (the meter says HIDDEN) and it can't catch you. After 25 s, "the locker door creaks open". Another player sees no prompt on your locker.
- [ ] C3-6 Radios: E makes it flash for 8 s and the Stalker heads there. It can be used again after 30 s.
- [ ] C3-7 Silence all 4 music boxes (3 s hold, ideally while it's away): "The music stops…", and it moves slower. Dawn: LEVEL COMPLETE (+$550 · 600 XP); 3 catches fails it.

**Level 6: Final Preparations / Rescue Mission**
- [ ] C3-8 Day: walk over glinting scrap piles (no prompt) for "+1 scrap (team pool)". The workbench (west of the entrance) shows the pool; with 3 or more, hold E to get a kit; place it at one of the 3 white rings by the entrance and a tower appears.
- [ ] C3-9 Hold your flashlight on a faint purple symbol on a wall (atrium west, atrium east, East Wing end) for about 2 s: it lights up with a message.
- [ ] C3-10 Night: green EVAC ring at the entrance; 4 white cocoons ("🆘 Help me!"), each with a crawler nearby. Hold E 3 s to cut free, and the shopper follows you. Die while escorting: "Don't leave me here!" and "Lead Me" (E) for anyone.
- [ ] C3-11 A shopper entering the ring ticks "Bring shoppers to the EVAC ring (n/3)" and waits there. "Crawlers caught the scent…" groups come for followers and waiting shoppers. Day-6 towers glow and burn crawlers near the ring.
- [ ] C3-12 "Evac van in 30 seconds": stand in the ring at dawn to get "Be at the exit" ✅. LEVEL COMPLETE (+$650 · 700 XP).

**Level 7: The Warning / The Shadow Queen**
- [ ] C3-13 Day: 3 gold cannons with cyan rings around the fountain. Stand in a ring: "🔆 n%" rises (about 20 s solo, faster with friends), then CHARGED.
- [ ] C3-14 North of the fountain: a 5×5 grid with a light source on the west and a crystal on the north. Rotating mirrors (E) redraws the beam. Correct route: the crystal blazes cyan and the toast says PRISM LENS earned.
- [ ] C3-15 to C3-18 (the night boss): replaced by §B7 above. One extra check: if she survives to dawn, LEVEL FAILED and "The Queen retreats…".
- [ ] C3-19 Regression: Levels 3–4 night shoppers still move normally (their pathfinding moved to the shared NpcMover).

## §C2: Campaign Levels 3–4 (test after §C)

Fastest route: set Workspace `MissionTest_Level` = `L03` (or `L04`) **before** Play. Play Day 3 and Day 4 without `FastPhases` (240 s days). For night-only checks, finish the day with `MissionTest_CompleteStage` = true, then `SkipPhase`.

**Level 3: The Missing Delivery / Impostors**
- [ ] C2-1 Day: a white "NIGHT SHIFT DELIVERIES" van with open rear doors stands in the plaza, east of the entrance path. The marker points to a glowing cyan clue by its rear; hold E. Each clue toasts a story line and the next one appears: atrium west, then the upper level (north side).
- [ ] C2-2 The last clue names a cage letter, and the marker then points to that cage. Cages: A NW ground corner, B NE ground corner, C upper level SW, D far East Wing. Searching a wrong cage gives a "junk" toast.
- [ ] C2-3 The right cage: 4 glowing crates appear. Grab one (a cardboard box on your chest) and load it at the green ring behind the van. You get a toast plus "+6 stock" if you own a shop, and crates stack in the van. Die or swap items while carrying one: it reappears at the stash.
- [ ] C2-4 Night: 9 shoppers wander. Within about 20–40 s some begin following others. The followed shopper says "😰 Someone's following me!". Followers flicker and sometimes show garbled text or 🙂, and idle ones turn to stare at you.
- [ ] C2-5 Hold the beam on a follower for about 1.5 s: "👻 UNMASKED!", and a pale, glassy crawler with cyan eyes appears. Burn it: Phantoms 1/4. Light a real shopper instead: "🙈 Hey! I'm real!" and the ★ "never light a real shopper" bonus is lost.
- [ ] C2-6 Let a follower stay on a shopper for about 5 s: the shopper fades with "😱" and the 🛡 row reads "Shoppers lost (1/2 max)". A 3rd loss shows "❌ FAILED" and the level fails at dawn.
- [ ] C2-7 At dawn, surviving shoppers say "😊 Thank you!" and fade. LEVEL COMPLETE (+$350 · 400 XP).

**Level 4: Security Upgrade / Mall Under Attack**
- [ ] C2-8 Day: 4 sparking wall cameras (entrance, west hall, upper level north, East Wing end). Stand underneath, hold E, and they get a red REC light. 3 terminal consoles (atrium south of the fountain, upper level north, mid East Wing): hold E, screen "ONLINE". 2 red alarm boxes (atrium east wall, East Wing end): hold E, lamp goes green.
- [ ] C2-9 Barricade: the hardware depot (where the Day 2 depot was) gives planks **only if you own a shop**. The build prompt appears **only at your own shop's door ring**. The built barricade is posts plus X-planks over the windows; the doorway stays open and customers still walk in.
- [ ] C2-10 Night: each terminal has a health bar visible from afar. About 15 s in comes "🚨 CAMERA ALERT: … heading for the X Terminal!". Crawlers march to it and the bar drops; "⚠️ under attack" toasts follow. Kill them all: "✅ Attack … repelled!".
- [ ] C2-11 "View Cameras" at a terminal: green-tinted feed with REC, camera name, shadow count. Q/E or the buttons switch cameras; X, moving or being hit exits. Your normal camera returns.
- [ ] C2-12 Sound an alarm: "… N crawlers lured!", the lamp flashes red, and nearby crawlers walk to it and mill about for 8 s; it's usable again after 25 s.
- [ ] C2-13 Let crawlers raid your barricaded shop: your stock stays put while the planks disappear; once broken, "Your barricade broke!" and stock drains.
- [ ] C2-14 Lose 2 terminals: "❌ FAILED: Terminals lost", and LEVEL FAILED at dawn. Lose at most 1: LEVEL COMPLETE (+$450 · 500 XP), then "Level 5 … coming in a future update".
- [ ] C2-15 Regression: Levels 1–2 still play as in §C; Day 2 fuses and lamps still carry correctly (shared carry code changed).

## §C: Campaign Levels 1–2

Setup: `git pull`, rebuild or reconnect `rojo serve`, press Play. Without API access, every Play is a brand-new player (memory store), which is ideal for testing Level 1. **Test Day 2 without `FastPhases`**; fast mode shrinks its 240 s day to about 72 s, too short for the carrying runs. `SkipPhase` is fine anywhere.

**Level 1**
- [ ] C-1 The goals panel reads **DAY 1 · FIRST SHIFT**: claim / stock / serve (0/3) / upgrade, plus ★ Serve 6. The phase pill says DAY 1. Each step ticks with a ✅ toast; finishing shows "🌟 All day objectives done!".
- [ ] C-2 At dusk: "✅ Day cleared!".
- [ ] C-3 **Night 1 · First Contact**: objectives equip / burn / survive (+★ team 6, ★ no knockdown). The fuse boxes stay off (no ⚡ marker, no "Breakers" in the top line). At most 4 crawlers at once.
- [ ] C-4 Dawn: green **LEVEL COMPLETE** banner (+$150 · 200 XP) and the toast "🔓 Level 2 unlocked". Press **M**: Level 1 ✅ CLEARED, Level 2 ▶ NEXT UP with your vote on it, chapters 2–6 🔒, levels 3–7 🚧.

**Level 2**: the next sunrise plays it automatically.
- [ ] C-5 **DAY 2 · POWER FAILURE**: day lights flicker. The marker points to the **maintenance depot** (south side, right of the entrance). Grab a fuse: a glowing item sits on your chest. The marker switches to the nearest sparking panel, whose "Install Spare Fuse" prompt only appears while you carry a fuse (hold E). Find all 4: west wall, north wall (under the balcony), upper-level west wall, far end of the East Wing. Flickering stops after the 4th.
- [ ] C-6 Lamps: grab a lamp, place it on a glowing ring. 3 are required, 5 for ★. Rings: by the atrium breaker, on the balcony by its breaker, at the East Wing end, mid-corridor, and the NW atrium.
- [ ] C-7 **NIGHT 2 · TOTAL BLACKOUT**: the lights stutter and die, the scene goes near-black, and your lamps glow. The top line shows "🌑 BLACKOUT ⚡ Breakers 0/3". Crawlers start near the breakers and patrol (they don't beeline to your shop). Crawlers walking into a lamp's light burn.
- [ ] C-8 Restore a breaker (hold E 5 s): **that zone's** neon and uplights return. After all 3: normal night look, crawlers stunned, "POWER RESTORED". At dawn: LEVEL COMPLETE (+$250 · 300 XP), then "Level 3 … coming in a future update".

**Failure and retry**
- [ ] C-9 On Night 2, skip to dawn without the breakers (SkipPhase): red **LEVEL FAILED** banner with a reason. The next sunrise plays Level 2 again, and its day shows the hint "Day already cleared…".
- [ ] C-10 Leave a day unfinished: at dusk "❌ Day objectives unfinished"; at dawn **DAY NOT CLEARED**.

**Shortcuts, multiplayer, persistence**
- [ ] C-11 Set `MissionTest_Level` = `L02` before Play: you start on Day 2 and still get credit. `MissionTest_CompleteStage` = true ticks the current stage's required objectives.
- [ ] C-12 Two players (Test → Clients and Servers): both see the same level; team objectives are shared, personal ones separate. Votes (M) show counts. A player who joins during the night sees "joined mid-night" and gets **JOINED MID-NIGHT** at dawn.
- [ ] C-13 Vote **Free Shift** (M): the next sunrise plays the classic loop (fuse boxes every night, no level objectives).
- [ ] C-14 Private test experience (API on, §P): clear Level 1, rejoin, and the map still shows it cleared. An older save that had finished the tutorial and a night starts at Level 2.
- [ ] C-15 Regression: shops, customers, upgrades, spiders' warnings, escalators, 🧪 test store.

## §F: Fixes: spider difficulty, escalators, closed shops

Use `FastPhases` = true. Use `SkipPhase` in the Server view to reach night quickly.

**Spiders (Shadow Crawlers)**
- [ ] F-1 Night 1: run away in a straight line from a crawler. You pull away (you 16 vs crawler 12.5).
- [ ] F-2 Before every bite the crawler **stops, rears up, its eyes flare red**, and you see an orange edge flash with **"⚠ DODGE!"**, about 0.6 s of warning.
- [ ] F-3 Step away during the wind-up: the bite misses (no damage).
- [ ] F-4 When bitten: red vignette, camera shake, a red "-10" and a knockback push away from the crawler.
- [ ] F-5 Stand among 3 crawlers on purpose: damage arrives at most about once per second (not all at once). You survive roughly 10 s or more on night 1.
- [ ] F-6 After respawning you get a few seconds of ForceField sparkle and can't be bitten.
- [ ] F-7 Later nights feel harder (faster, harder-hitting, more crawlers). Expected values per night are in the STATUS table. Optional: note your FPS with 10+ crawlers.

**Escalators**
- [ ] F-8 West escalator (sign **▲ UP**): stand still on it and you ride smoothly to the balcony with no jitter. Walking forward makes you faster; you can walk back down against it.
- [ ] F-9 East escalator (sign **▼ DOWN**): from the balcony, stand on it and ride down.
- [ ] F-10 Stepping on and off at both ends feels normal (no launch, no sticking). The moving treads match your riding speed and direction.
- [ ] F-11 Two-player test (Clients and Servers, 2 players): both ride at the same time; each sees the other ride smoothly.

**Closed shops**
- [ ] F-12 Walk to Velvet Arcade (or any shuttered atrium store): a **"What's this? [F]"** prompt appears. Pressing it shows a toast explaining it opens in a future expansion and pointing to the East Wing.
- [ ] F-13 Same at the Food Court gate at the end of the East Wing.
- [ ] F-14 Regression: the 6 East Wing shops still claim, stock, serve and upgrade normally.

## §M: Monetization Phase 1

No Robux is involved anywhere in this section. The store runs in **Studio test mode**.

1. `git pull`, then rebuild or reconnect `rojo serve`. Press Play.
2. Output should show `STUDIO TEST STORE active` and **no** `[MonetizationService] config:` warnings. A gold **🧪 TEST STORE** button sits bottom-left. Click it.
3. For persistence checks, use the published private test experience with API access on (§P). Otherwise the memory fallback forgets everything when you stop.

Scenario switches are Workspace attributes set in the **Server** view (Test tab → Current: Server → select Workspace → Attributes → +). See `docs/MONETIZATION.md` §4.

- [ ] M-1 **Gate:** in the Output, `StoreMode` is Test. (Optional: select ReplicatedStorage, Attributes → `StoreMode` = `Test`.)
- [ ] M-2 **Success:** click *Small Cash Pack* → toast "✅ [TEST] Small Cash Pack: +$500", cash +500 exactly once.
- [ ] M-3 **Cancel:** set `StoreTest_Decline` = true → click a pack → "Purchase cancelled", cash unchanged. Set it back to false.
- [ ] M-4 **Duplicate:** `StoreTest_Duplicate` = true → click a pack → cash +amount **once**, and a second toast says the duplicate was acknowledged without regranting.
- [ ] M-5 **DataStore failure:** `StoreTest_FailSave` = true → click a pack → "Receipt pending (attempt 1/4)…" warnings. Within 15 s set it back to false → the next retry acknowledges. Cash increased **once** overall.
- [ ] M-6 **Leave mid-purchase:** `StoreTest_DelaySeconds` = 10 → click a pack → stop Play within 10 s. No errors in Output. (The simulated receipt is dropped when you leave; real receipts are re-delivered by Roblox, which is unit-tested.)
- [ ] M-7 **Persistence (private test experience):** buy a pack, stop, play again → cash kept.
- [ ] M-8 **Pass:** click *VIP Membership* → "OWNED"; set `StoreTest_OwnPass_VIP` = false → it flips back to "not owned".
- [ ] M-9 **Rate limit:** spam-click a pack 10 times quickly → at most about 3 purchases per burst are processed; nothing errors.
- [ ] M-10 **Regression:** claim, stock, serve, upgrade, night and rewards all work as before.

When real Ids exist (later): §6 of MONETIZATION.md covers Roblox's own Studio test purchases (P-1) and private-experience pass ownership (P-2).

## §V: Visual slice review

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
