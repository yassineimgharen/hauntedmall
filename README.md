# NIGHT SHIFT: Haunted Mall

Multiplayer Roblox shop-tycoon by day, co-op survival horror by night.

Run a store in a gorgeous mall: stock shelves, serve customers, upgrade. When the lights die, grab your flashlight, burn back the shadows, repair the fuse boxes, and protect your shop until dawn.

## Quick start

**Ubuntu (development):**
```bash
scripts/install-tools.sh     # one time: pinned Rojo/selene/StyLua/luau-lsp into .tools/ (no sudo)
scripts/check.sh             # format check, lint, type analysis, build → build/NightShift.rbxl
```

**Windows (Studio testing):** see [docs/TESTING.md](docs/TESTING.md). In short: `rokit install`, then `rojo build -o NightShift.rbxl`, then `rojo serve`, then open the place in Studio and connect.

## Docs
| Doc | Contents |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Services, networking, data model, security, performance, monetization design |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phases 1–7 with exit criteria |
| [docs/ART_DIRECTION.md](docs/ART_DIRECTION.md) | Visual pillars, palette, lighting, creature language |
| [docs/ASSETS.md](docs/ASSETS.md) | Asset list, Blender → Studio pipeline, audio/animation plan |
| [docs/TESTING.md](docs/TESTING.md) | Windows setup and Studio test checklist |
| [docs/STATUS.md](docs/STATUS.md) | Current phase QC report: done, missing, risks |

## Tuning
Every gameplay number is in `src/shared/Config/`: phase lengths, economy, upgrades, enemies, waves, flashlight, collectibles, lighting looks, and the palette.
