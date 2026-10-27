# Phase 1 + 2 Quality-Control Report

_Last updated: 2026-10-27_

## 1. Static checks (run on Ubuntu, `scripts/check.sh`)
| Check | Result |
|---|---|
| StyLua format check | ✅ pass |
| selene lint (roblox std) | ✅ 0 errors, 0 warnings |
| luau-lsp type analysis (Roblox API definitions, sourcemap) | ✅ no type errors |
| Rojo 7.7.1 build → `build/NightShift.rbxl` | ✅ builds |
| **Roblox Studio runtime** | ⏳ **not yet run.** Nothing here has executed inside Roblox. See `TESTING.md` |

## 2. Implemented
- **Architecture:** Rojo layout, 8 server services, 7 client controllers, shared config, rate-limited remotes, collision groups
- **Data:** session-locked DataStore profiles, migrations, sanitizing, autosave, shutdown flush, Studio memory fallback
- **World:** atrium (dome, balcony, fountain, palms, escalators, facades, plaza), east corridor, 6 shop units, fuse boxes, spawn points, lurker eyes, AssetRegistry swap-in
- **Day:** shop claiming, stock ordering, NPC customers (R15, colored outfits, bubbles, shopping bags), register serving with tips, auto-checkout, 5 persistent upgrades
- **Night:** state machine, cinematic transition, Shadow Crawler (procedural rig and animation), waves scaled by night and player count, AI (hunt/attack/raid/prowl, pathfinding, stuck recovery), flashlight combat with battery, fuse-box co-op objective with safe zones and stun, shared kill credit, respawn, dawn rewards, rare-find collectibles
- **Progression:** cash, XP, levels with cash rewards, upgrades, stats, collectibles
- **UI:** title screen, HUD (phase timer, cash, level/XP, goals, health/battery, night info), shop panel, settings (saved), shift report, toasts, damage vignette, world and screen popups, responsive scaling, touch flashlight button, gamepad Y/B shortcuts
- **Audio:** system complete (SoundGroups, crossfades, volume settings); tracks are empty placeholders

## 3. Incomplete / placeholder (by design for this slice)
- 3D assets are procedural part-built placeholders, not authored meshes (`ASSETS.md`)
- Music and most SFX are empty IDs (`AudioConfig.luau`)
- Only one enemy type. No boss yet.
- No daily/weekly missions, achievements, inventory screen or shop customization yet (Phase 3)
- Monetization is planned and configured but disabled (Phase 5)
- Icons are emoji placeholders
- Customers wear plain colored R15 bodies (no hair or accessories)

## 4. Known risks: verify these first in Studio
| Risk | Why | Fallback if it fails |
|---|---|---|
| Crawler legs don't animate | Relies on client `Motor6D.Transform` on a server-owned NPC | Move to Animator with Studio-authored animations |
| Crawler hovers or sinks | Custom R15 Humanoid with `HipHeight` | Tune `EnemyConfig.Types.ShadowCrawler.HipHeight` |
| Customers fail to spawn | `CreateHumanoidModelFromDescription` failing on the server | Output warns `[CustomerService] could not create customer rig`; ship a rig in `assets/` |
| Creepster font missing | Font family availability | Falls back to the default font. Change `Theme.Fonts.Title` |
| Flashlight cone offset from the hand | Beam originates from a root-relative attachment, not the tool | Tune `BEAM_OFFSET` in CombatService |
| Pathfinding on escalators | Invisible ramp collision | Enemies fall back to direct MoveTo; check the balcony fuse fight |
| Frame rate on the laptop at night | Future lighting plus ~60 dynamic lights | Report FPS; we can cut corridor lights or disable shadows |

## 5. Required Studio tests
The full checklist is in `TESTING.md` (sections A–F).

## 6. Decisions waiting on you
1. Visual sign-off on the slice, or a list of what feels off
2. Whether you'll model the priority-A assets in Blender yourself, or want them specified for a 3D artist
3. Approval to start Phase 3
