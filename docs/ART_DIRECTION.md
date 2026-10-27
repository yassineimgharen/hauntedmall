# Art Direction: "Neon Noir Mall"

Built from your key art. Images 1, 2 and 4 are the target. Image 3 (flat arcade room, primitive props, unlit carpet) is what we avoid.

## Pillars
1. **Two moods, one place.** By day the mall is a warm, sunlit, aspirational atrium. By night the same space reads as violet and electric-blue, with fog and shadow. The transformation is the hook, so it must be dramatic.
2. **Light tells the story.** Warm 3200K interior light by day. Purple/cyan neon, moonlight through the dome, and the player's warm flashlight cone by night. The flashlight is both the weapon and the warmest color on screen at night.
3. **Stylized, not toy-like.** Roblox-native proportions for characters. Architecture gets real scale, bevels, trims and layered materials, never bare boxes.
4. **Readable darkness.** Night is dark but never pitch black. Ambient sits at about 45/30/80 RGB. Enemies always carry their own light (glowing eyes and grin), so players can read threats.

## Palette (source of truth: `src/shared/Config/Palette.luau`)
| Role | Color |
|------|-------|
| Marble floor / walls | `#EAE4DA`, `#F2ECE4` warm white |
| Trim | brass gold `#D8AE60`, dark metal `#24222E` |
| Night neon | pink `#FF40C8`, cyan `#40DCFF`, purple `#9848FF` |
| Day accents | gold `#FFC054`, mint `#54FFA4` |
| Creatures | body `#12081E`, eyes and grin `#EC54FF` / white |
| UI | deep violet glass `#18102C` panels, pink→purple gradients, cyan info |

## Lighting (presets in `LightingPresets.luau`, Technology = Future)
- **Day:** ClockTime 13.6, bright sun through the dome, warm Atmosphere haze, subtle bloom, sun rays.
- **Dusk (9 s):** day lights stutter and fail, the sky sweeps through sunset, neon saturates.
- **Night:** moon overhead, Atmosphere density 0.42 in violet, contrast +0.2, stronger bloom, neon flicker, lurker eyes in dark corners.
- **Dawn:** sunrise sweep back to day. Customers return.

## Architecture language
- Central atrium with a geodesic glass dome, a ring balcony with glass railings and a neon underglow strip (the signature shape from key art 1), palms in brass-rimmed planters, and a tiered fountain.
- Storefronts: dark-metal mullions, full-height glass, header sign boards with neon trim in the owner's accent color.
- Corridors: marble with inlay bands, a skylight strip, pendant lamps and wall sconces.

## Characters & creatures
- Players and customers: standard Roblox avatars. Customers use the default R15 body with colored outfits; authored outfits come in Phase 3.
- **Creature design language:** silhouettes made of void-black smoke and spikes, glowing magenta eyes, and a white neon zig-zag grin. Every creature must be recognizable from its silhouette and light pattern alone.
  - Shadow Crawler: low, six spider-legs, fast skitter.
  - Night Stalker: tall and thin, long arms, a single eye-slit.
  - Phantom Shopper: a customer whose face glitches and whose eyes glow at dusk.
  - Security Nightmare: a hulking guard with a riot-shield silhouette and a red visor.
  - Mall Warden (boss): a giant from key art 1, claw hands reaching over the balcony.

## UI
- Creepster for titles (horror flavour), Fredoka One for headings (friendly), Builder Sans for body text.
- Glass panels with a purple stroke, pill buttons with gradient and hover scale, emoji icons as placeholders until a custom icon set exists.

## Don'ts
- No flat unlit rooms, no single-material walls, no scattered primitives without purpose (image 3).
- No gore. The scare comes from atmosphere, light and surprise, which keeps the game all-ages friendly.
- No neon everywhere by day. Neon is pastel and restrained until night.
