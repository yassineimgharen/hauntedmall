# Technical Architecture

## Principles

- **Server-authoritative.** Clients send *intent* (claim, restock, beam on/off + aim). The server validates, simulates, and owns every number that matters: cash, stock, HP, damage, rewards.
- **Replicate state, not events.** Phase, timers, cash, battery and shop stock are Instance attributes. The HUD derives from them, so there's no per-second network chatter and no drift.
- **Data-driven tuning.** All balance numbers live in `src/shared/Config/*`. Designers change config, not code.
- **One gateway per concern.** Only `ProgressionService` changes cash/XP/upgrades. Only `DataService` touches DataStores.
- **Procedural world with an asset slot system.** The mall is built in code (correct scale, materials and lighting). Any hero prop can be replaced by an authored model through `AssetRegistry` without code changes.

## Project layout (Rojo)

```
default.project.json         Rojo tree (also sets Lighting.Technology = Future, StreamingEnabled = false)
src/shared   → ReplicatedStorage.Shared
  Config/                    GameConfig, EconomyConfig, UpgradeConfig, EnemyConfig,
                             CollectibleConfig, MonetizationConfig (disabled), AudioConfig,
                             Palette, LightingPresets
  Net.luau                   Remote registry + rate-limited server handlers
  Util/                      Signal, Format, Validate, RateLimiter
src/server   → ServerScriptService.Server   (init.server.luau = bootstrap)
  World/                     Builder, Layout, Props, Lobby, Corridor, ShopUnit, MallBuilder, AssetRegistry
  Enemies/                   ShadowCrawler (procedural rig)
  Services/                  DataService, ProgressionService, GameStateService, ShopService,
                             CustomerService, EnemyService, CombatService, NightService
  Util/                      Notify, CollisionGroups
src/client   → StarterPlayerScripts.Client   (init.client.luau = bootstrap)
  Controllers/               Audio, Lighting, WorldFx, EnemyVisual, Prompt, Flashlight, UI
  UI/                        Theme, Create, Components, Screens/{Hud, MainMenu, Notifications,
                             ShopPanel, SettingsPanel, ResultsPanel}
assets/      → ServerStorage.Assets         Authored models (.rbxm) picked up by AssetRegistry
```

## Boot sequence

Server: `CollisionGroups.setup()` → `MallBuilder.build()` → every service `Init()` → every service `Start()`, in this dependency order:

| # | Service | Owns | Depends on |
|---|---------|------|-----------|
| 1 | DataService | Profiles, session locks, autosave, shutdown flush | — |
| 2 | ProgressionService | Cash, XP, levels, upgrades, settings, collectibles | Data |
| 3 | GameStateService | Intermission → Day → Dusk → Night → Dawn loop | — |
| 4 | ShopService | Shop claim/release, stock, sales, raids | Data, Progression |
| 5 | CustomerService | NPC shoppers, register queue, serving | Shop, GameState, Progression |
| 6 | EnemyService | Enemy spawn, AI, HP, death | Shop |
| 7 | CombatService | Flashlight tool, beam validation, battery, cone damage, player setup | Enemy, Progression |
| 8 | NightService | Waves, fuse objectives, safe zones, rewards, results | Enemy, GameState, Progression |

Client: waits for `game.Loaded` and `workspace.Mall`, then starts its controllers. Each one is isolated in `pcall`, so a failing controller can't take down the others.

## Replicated state (attributes)

| Where | Attributes |
|-------|-----------|
| `ReplicatedStorage` | `Phase`, `PhaseStartedAt` (server time), `PhaseDuration`, `NightNumber`, `Wave`, `FusesRepaired`, `FusesTotal` |
| `workspace` | `EnemiesAlive`; Studio-only `FastPhases`, `SkipPhase` |
| `Player` | `DataLoaded`, `DataMock`, `Cash`, `Level`, `XP`, `XPNeeded`, `Upg_<Id>`, `Set_*`, `ShopId`, `ShopStock`, `ShopMaxStock`, `Battery`, `CollectiblesFound` |
| Shop model | `ShopId`, `Category`, `Accent`, `OwnerUserId`, `OwnerName`, `Stock`, `MaxStock`, `CustomersWaiting`, nav points `P_*` |
| Enemy model | `HP`, `MaxHP`, `SpawnedAt`, `AttackAt`, `LitUntil`, `StunnedUntil`, `Dead` |

## Remotes

| Remote | Dir | Rate (per s / burst) | Server validation |
|--------|-----|----------------------|-------------------|
| `PurchaseUpgrade(id)` | C→S | 4 / 6 | id is a known string; level < max; cash checked server-side |
| `Restock()` | C→S | 2 / 3 | caller owns a shop; shelves not full; cash |
| `SetBeam(on, aim)` | C→S | 12 / 12 | boolean; unit Vector3; within 80° of facing; pitch limit; tool equipped; battery > 0 |
| `AimUpdate(aim)` | C→S (unreliable) | 20 / 20 | same aim validation; ignored while beam is off |
| `SaveSettings(t)` | C→S | 1 / 3 | known keys only, fractions in [0,1], boolean |
| `RequestPurchase(kind, key)` | C→S | 2 / 3 | kind ∈ Product/GamePass; key must exist in `MonetizationConfig`; only *opens a prompt*, never grants |
| `VoteLevel(levelId)` | C→S | 2 / 4 | level must exist, be implemented and unlocked for the voter (or "FREE"); only a vote, the server picks at sunrise |
| `Notify(text, kind)` | S→C | — | — |
| `NightResults(data)` | S→C | — | — |
| `Effect(kind, payload)` | S→C | — | cosmetic only |

ProximityPrompts (claim, restock, serve, repair) are handled with server-side `Triggered` events. Each handler re-checks ownership and phase. The client hides prompts that don't apply to you, but that is cosmetic only.

## Data model (DataStore `NightShift_PlayerData_v1`, key `p_<UserId>`)

```lua
{
  Version = 1, Cash, XP, Level, Stock,
  Upgrades = { [UpgradeId] = level },
  Collectibles = { [ItemId] = count },
  Stats = { NightsSurvived, Kills, Sales, TotalEarned, FusesRepaired },
  Settings = { Music, Sfx, ReducedEffects },
  ProcessedReceipts = {},     -- Phase 5 purchase de-duplication
  CreatedAt,
  Lock = { JobId, Time }      -- session lock (stripped in memory)
}
```

Safeguards against data loss:
- **Session locking.** Writes are refused if another server holds a fresh lock. The load is retried. A lock goes stale after 3× the autosave interval (it can only go that long without a refresh if its server crashed).
- **Never save what wasn't loaded.** A failed load kicks the player with a friendly message instead of creating a blank profile that could overwrite real data.
- **Lock-checked writes.** Every write goes through `UpdateAsync` and verifies the lock is still ours. If it isn't, local changes are discarded and the player is kicked, never overwriting newer data.
- **Migrations and sanitizing.** Schema migrations are indexed by version. `reconcile` fills newly added fields, and `sanitize` repairs NaN or negative values.
- **Autosave and shutdown.** Autosave runs every 60 s, staggered per player. `BindToClose` waits (up to 25 s) for every in-flight save, including ones started by `PlayerRemoving`.
- **Studio fallback.** Without API access, Studio uses an in-memory store and the HUD shows a warning.

## Combat model

The flashlight is the weapon, so the game reads as horror rather than a shooter, and it stays all-ages friendly.
- The client sends beam on/off and an aim vector at ≤10 Hz. While beaming, the character turns to face the aim, so the server can sanity-check the aim against the facing.
- The server ticks at 10 Hz. For each beaming player it drains the battery, then tests each enemy against range, cone and world-only line of sight (a raycast with the `Enemies` collision group plus `RespectCanCollide`), and applies DPS scaled by the Lens upgrade.
- Kill credit goes in full to every contributor, so there's no kill-stealing in co-op.
- Enemy attacks use `Humanoid:TakeDamage`, which respects ForceFields. Respawning uses Roblox's default with `Players.RespawnTime = 5`.

## Enemy AI

Every 0.2 s, staggered across enemies: **Stunned** → **Hunt / Attack** (nearest living player within 70 studs, with line of sight or within 25 studs) → **Raid** (nearest owned shop with stock; drains 1 unit every 2 s) → **Prowl** (toward the nearest player anywhere). Movement uses direct `MoveTo` when the goal is visible on the same floor, and otherwise a cached PathfindingService path, recomputed when the goal moves more than 10 studs or the path is older than 3 s. Stuck detection forces a jump and a repath. Enemies run on Humanoids with server network ownership, so Roblox interpolates movement smoothly. Legs and body are animated client-side through `Motor6D.Transform`, so animation costs no bandwidth.

Adding an enemy type: add a config entry in `EnemyConfig.Types`, a builder in `src/server/Enemies/`, and register it in `EnemyService` `BUILDERS`. Behaviours unique to that type (e.g. Night Stalker preferring isolated players) branch inside `think` on `enemy.Type`. The plan is to split `think` into per-type modules once there are three or more types.

## Performance strategy

- Decoration parts are created with `CanCollide=false`, `CanQuery=false`, `CanTouch=false`, `CastShadow=false` (`Builder.decor`).
- Only the central pendant light in each shop casts shadows. Escalator treads, lurker eyes and enemy animation are client-local and distance-culled.
- AI thinks at 5 Hz with staggering, combat runs at 10 Hz, and remotes are rate-limited.
- Hard caps: 14 enemies and 10 customers alive at once.
- `StreamingEnabled` is off for the vertical slice (small map, simpler code). Turn it on in Phase 4 once the mall grows; client code already uses `WaitForChild` for world lookups.
- The startup log prints `[MallBuilder] built N parts`. Keep it under ~6k for the slice.

## Monetization architecture

Implemented (Phase 1 of monetization): a single ProcessReceipt handler, idempotent persisted receipts, game-pass ownership checks, server-validated prompts, and a Studio-only test store. The store is closed (`Enabled = false`, Ids 0). Full design, guarantees and test plan: [MONETIZATION.md](MONETIZATION.md).

## Campaign

`MissionService` runs per-level objectives on top of the shared clock; see [CAMPAIGN.md](CAMPAIGN.md).
