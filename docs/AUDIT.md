# Project Audit

_Audit date: 2026-10-27. Method: line-by-line review of the source plus your Studio report. Nothing in this audit was run inside Roblox by me; "verified" below means you confirmed it in Studio._

## 1. Shop shutters: intended behavior, not a bug

There are three kinds of storefront in the mall:

| Kind | Where | Count | Interactive? |
|---|---|---|---|
| **Player shops** | East Wing corridor, 3 on each side | 6 | Yes: claim, stock, register, upgrades |
| **Decorative storefronts** (roll-down shutters) | Around the atrium, ground floor and balcony | 16 | No. Set dressing and future expansion slots |
| **Food Court gate** | End of the East Wing corridor | 1 | No. Locked future area (Phase 4) |

Answers to your questions:
1. **Are the shutters closed by default on purpose?** Yes, intentionally. They are static decoration (`Props.facade`) with no script attached.
2. **When do they open?** Never, in this version. They are reserved for the Phase 4 mall expansion.
3. **Does claiming a shop unlock its entrance?** Real shops have no door at all. Their entrance is an open glass doorway, 10 studs wide, before and after claiming. Claiming changes the sign, lights the neon trim and hides the FOR LEASE stand.
4. **Are shutters tied to day/night?** No. Night only changes lighting, neon and the lurker eyes peeking from under some shutters.
5. **Does the tutorial affect access?** No. Every shop is reachable at any time.
6. **Decorative vs interactive?** As in the table. Only the 6 East Wing shops are interactive.
7. **Can players reach their stock crates?** Yes. They sit in the back-left corner inside the shop, with an "Order Stock" prompt visible only to the owner.
8. **Can players reach and use the register?** Yes. The counter is front-right inside the shop. Its "Serve Customer" prompt appears only to the owner, and only while a customer is waiting.
9. **Do NPC customers enter the right shop?** By design, yes. Each customer is assigned to one owned shop with stock and walks a route built from that shop's own navigation points. This is code-verified, not Studio-verified (see §3).
10. **Can players buy upgrades and manage merchandise?** Upgrades: you confirmed they work. Merchandise is currently a single stock pool per shop; choosing products is Phase 2/3 work.

**Real problem found:** the "OPENING SOON" sign appeared on a random 50% of the shutters, so half of them looked like real, closed shops. **Fixed:** every shutter now reads "COMING SOON / 🔒 future update", and a marker points new players to the East Wing.

## 2. Tutorial objectives: can each be completed?

| Goal | How it completes | Status before | Status now |
|---|---|---|---|
| Claim a shop | Claim prompt at a FOR LEASE stand | Worked (you confirmed) | Unchanged, plus a guide marker |
| Order stock | Restock prompt at the crates, or ORDER in the shop panel | **Could be blocked** (bug 1). Also unticked itself when stock sold out (bug 2) | Fixed |
| Serve a customer | Press E at the register while a customer waits | Possible, but remembered only on the client and lost on rejoin (bug 2) | Fixed: persisted on the server |
| Buy an upgrade | Shop panel | Worked | Unchanged |

## 3. Confirmed defects (all fixed in this update)

| # | Defect | Cause | Fix |
|---|---|---|---|
| 1 | **Economy soft-lock:** a new player who buys an upgrade first can't afford stock, so no customers come and they can't earn until night | Start cash is $150 and upgrades cost $120–180, but restock required the full $30 order | Restock now buys as many units as you can afford. If you can't afford one unit and your shelves are empty, the supplier sends 10 free units, at most once every 10 minutes (the cooldown is saved, so rejoining doesn't reset it) |
| 2 | Shift goals un-tick or reset | "Order stock" meant "stock > 0 right now"; "Served" was a client-only flag | Goals are now persistent server flags (`data.Tutorial`, replicated as `Tut_*`), set once and never cleared. Older saves are backfilled from their stats |
| 3 | Decorative shutters look like closed player shops | Random label visibility | Always labelled "COMING SOON" |
| 4 | DataStore warning in Studio | **Not a defect**: expected for an unpublished place, or with API access off (see §5) | Added a separate `_Studio` DataStore so Studio tests can never touch real player saves |

Clarity improvements (no gameplay change):
- **Objective marker:** a floating arrow, visible through walls, points at the next action (claim stand, your crates, your register when a customer waits, the nearest broken fuse at night).
- **Goals panel:** highlights the next step (▶) with a one-line hint. After the four day goals it switches to a "Daily Routine" list with a countdown to nightfall.
- **One-time $100 training bonus** for finishing the four day goals.
- **Customer-waiting toast** for owners, at most every 20 s.
- **Faster customers:** walk speed 11 → 13, so the first sale arrives sooner.

## 4. Full system checklist

Legend: ✅ verified in Studio by you · 🧪 implemented, needs a Studio test · 🐞 bug fixed in this update (re-test) · 🟨 partial · ⬜ not started · 🎨 needs external assets

### Shop tycoon
| System | Status |
|---|---|
| Shop claiming / ownership | ✅ |
| Stock ordering | 🐞 |
| NPC customers (spawn, walk, browse, queue, pay, leave) | 🧪 |
| Register serving and tips | 🧪 |
| Earning cash from sales | 🧪 |
| Shop upgrades (Shelves, Quality, Appeal) | ✅ (UI response); effects 🧪 |
| Persistent shop stock and upgrades | 🧪 (needs real DataStore) |
| Shop customization (themes, decor slots) | ⬜ |
| Shop reputation | ⬜ |
| Unlockable merchandise / product choice | ⬜ |
| Store expansion | ⬜ |

### Survival
| System | Status |
|---|---|
| Day/night cycle and transitions | ✅ |
| Enemy spawning | ✅ |
| Pathfinding / AI (hunt, raid, prowl) | 🧪 |
| Crawler animation | 🧪 (top risk, see STATUS) |
| Flashlight combat and battery | 🧪 |
| Player health, damage, respawn | 🧪 |
| Fuse-box co-op objective, safe zones, stun | 🧪 |
| Waves and difficulty scaling | 🧪 |
| Dawn rewards and Shift Report | 🧪 |
| Defensive equipment (traps, barricades) | ⬜ |
| Additional monsters (Stalker, Phantom, Security) | ⬜ |
| Mall Warden boss | ⬜ |

### Progression
| System | Status |
|---|---|
| Cash, XP, levels | ✅ (HUD); level-ups 🧪 |
| Persistent upgrades | 🧪 |
| Collectibles (drop + save) | 🧪; collection UI ⬜ |
| Tutorial / onboarding | 🐞 |
| Inventory screen | ⬜ |
| Achievements | ⬜ |
| Daily / weekly missions | ⬜ |
| Unlockable mall areas | ⬜ |
| Cosmetic rewards | ⬜ |

### Platform
| System | Status |
|---|---|
| DataStore persistence (locks, retries, shutdown) | 🧪 (memory fallback ✅ by you) |
| Studio data isolation | 🐞 new |
| Multiplayer (ownership, shared kill credit, leave/join) | 🧪 |
| Remote validation and rate limits | 🧪 (code-reviewed) |
| Monetization | ⬜ (config only, disabled) |
| Premium shop UI | ⬜ |
| Settings (volume, reduced effects) | 🧪 |
| Mobile controls | 🧪 |
| Audio system | 🟨 system ready; 🎨 no licensed tracks |
| Authored meshes / animations / icons | 🎨 |
| Analytics | ⬜ |

## 5. The DataStore warning in Studio

`DataStores unavailable in Studio — using an in-memory store` is **expected**. It appears when either:
- the place has never been published to Roblox (local file or Baseplate), or
- Game Settings → Security → **Enable Studio Access to API Services** is off.

In that mode the game runs normally but nothing is saved. The HUD shows a yellow "Studio test mode" line, so you can't mistake it for a bug. It is the safety fallback working as intended.

To test real saving safely, use a separate private test experience; see `TESTING.md` §P. Studio sessions now also use their own DataStore (`NightShift_PlayerData_v1_Studio`), so even in the live experience a Studio test can never read or overwrite real players' saves.
