# Development Roadmap

Each phase ends with the quality-control gate (static checks, feature list, incomplete items, Studio test list, known risks). The next major phase starts only after feedback on that gate.

## Phase 1: Foundation ✅ (code complete)
- Rojo project, pinned toolchain (Rokit on Windows, `scripts/install-tools.sh` on Ubuntu), selene, StyLua, luau-lsp
- Service/controller architecture, remote registry with rate limiting and validation
- Day/night state machine
- DataService with session locking, migrations, autosave and shutdown flush
- **Exit:** `scripts/check.sh` passes ✅. Data saves and reloads across sessions in Studio ⏳ *(needs your Studio test)*

## Phase 2: Premium vertical slice 🟡 (implemented, awaiting Studio verification)
- Atrium lobby: glass dome, balcony ring with neon underglow, fountain, palms, escalators, entrance plaza, 16 decorative storefronts
- East corridor with 6 claimable shops (3 categories, 30 visible merchandise slots each)
- Cinematic dusk power-down and dawn sunrise; night lighting with flicker and fog; lurker eyes
- Shadow Crawler: procedural six-legged rig, client animation, AI, raids on shops
- Shop income loop: claim → order stock → NPC customers → serve for tips → upgrades
- One survival round: waves, 3 fuse-box objectives, safe zones, stun, dawn rewards, rare finds
- HUD, main menu, shop/upgrade panel, settings, results, toasts; mobile flashlight button; gamepad shortcuts
- **Exit:** you approve how the slice looks and plays at 60 FPS on the Dell laptop with 2–3 test clients

## Phase 3: Core gameplay
- Authored hero assets replace placeholders (see `ASSETS.md`, priority A)
- Shop customization: themes, decoration slots, product display choices
- Product catalog per category, with a merchandise purchasing UI
- Inventory screen and collection book for rare finds
- Enemy roster: **Night Stalker** (hunts isolated players), **Phantom Shopper** (disguised among NPCs at dusk), **Security Nightmare** (armored; needs coordinated beams or fuse stuns)
- Player level unlocks: second-floor shop row, food court wing
- Daily missions (3/day) and weekly challenges, server-validated and stored in the profile
- Achievements
- **Exit:** a 20-minute session has clear goals and visible progression

## Phase 4: Multiplayer & polish
- Co-op objectives with variety: generator escort, lure-and-trap, restoring the PA system
- Night events: blackout, mannequin night, flooded fountain
- Night-type modifiers so no two nights play the same
- Authored animations (Animation Editor) for creatures and the flashlight hold; Studio-made VFX
- Sound design pass (licensed music and SFX, spatial ambience)
- Expanded mall: food court, arcade, second-floor shops
- Turn on StreamingEnabled with model streaming modes
- UI polish: icons, transitions, controller navigation everywhere
- Performance pass with MicroProfiler captures on the laptop and a phone
- **Exit:** 8-player playtest with no bugs above Minor and a stable frame rate

## Phase 5: Monetization (only after your approval of each item)
- MonetizationService (receipt deduplication, pass caching), premium shop UI
- Game passes: VIP, Shop Themes, Decoration Slots, Character Effects, Emote Pack, Flashlight Skins
- Developer products: cash packs (capped), cosmetic bundles, event items
- Purchase test plan using Studio test purchases
- **Exit:** every purchase path tested, including rejoin mid-purchase and server shutdown mid-purchase

## Phase 6: Release
- Full regression pass, bug bash, analytics events (AnalyticsService funnels: claim → first sale → first night → day 2)
- Mobile UX pass (touch targets, safe areas), low-end graphics fallbacks
- Thumbnails/icon from your key art, game description, age-appropriate content questionnaire
- Soft launch, then read the funnel data and retune economy config

## Phase 7: Live operations
- Monthly content: new wing, a new monster, a collectible set
- Seasonal events (Halloween Blood Moon, Winter Blackout)
- Bosses: **Mall Warden**, a multi-phase fight in the atrium under the dome
- Balance from data; community feedback loop
