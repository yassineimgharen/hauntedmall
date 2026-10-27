--!nonstrict
-- The campaign: 6 chapters × 7 levels. Each level is one Day + one Night with its own
-- objectives, rules and rewards. Pure data (no Roblox types) so tests can load it.
--
-- Implemented = true  → playable; Day/Night carry full objective lists and rules.
-- Implemented = false → planned; shown on the campaign map as "coming soon".
-- Levels must be implemented in order: progress stops at the first planned level.
--
-- Objective events (fired by game systems through MissionEvents; see docs/CAMPAIGN.md):
--   ShopClaimed Restocked Served Upgraded            (shops / upgrades)
--   FlashlightEquipped Kill EnemyDefeated Downed     (night combat; Kill = per contributor)
--   PanelRepaired LampPlaced                         (PowerGrid day mechanic)
--   BreakerRestored PowerRestored PowerRestoredEarly (breakers at night)
--   ClueFound CageSearched StashFound CrateRecovered (MissingDelivery day mechanic)
--   PhantomUnmasked PhantomDefeated ShopperTaken FalseAccusation (Impostors night mechanic)
--   CameraRepaired TerminalActivated AlarmArmed BarricadeBuilt (SecuritySystem day)
--   TerminalLost AlarmUsed CamerasViewed AttackRepelled (SecuritySystem night)

local CampaignConfig = {}

CampaignConfig.Events = {
	ShopClaimed = true,
	Restocked = true,
	Served = true,
	Upgraded = true,
	FlashlightEquipped = true,
	Kill = true,
	EnemyDefeated = true,
	Downed = true,
	PanelRepaired = true,
	LampPlaced = true,
	BreakerRestored = true,
	PowerRestored = true,
	PowerRestoredEarly = true,
	ClueFound = true,
	CageSearched = true,
	StashFound = true,
	CrateRecovered = true,
	PhantomUnmasked = true,
	PhantomDefeated = true,
	ShopperTaken = true,
	FalseAccusation = true,
	CameraRepaired = true,
	TerminalActivated = true,
	AlarmArmed = true,
	BarricadeBuilt = true,
	TerminalLost = true,
	AlarmUsed = true,
	CamerasViewed = true,
	AttackRepelled = true,
}

-- Rewards for replaying an already-cleared level, and per optional objective (first time).
CampaignConfig.ReplayFraction = 0.25
CampaignConfig.OptionalXP = 50

CampaignConfig.Chapters = {
	{ Index = 1, Name = "The East Wing", Boss = "The Shadow Queen", Theme = "Blackouts, impostors, stealth, rescue" },
	{
		Index = 2,
		Name = "Food Court",
		Boss = "The Gorging Chef",
		Theme = "Kitchen hazards, deliveries, infected diners",
	},
	{
		Index = 3,
		Name = "Underground Parking",
		Boss = "The Concrete Guardian",
		Theme = "Dark garages, headlights, pursuits",
	},
	{
		Index = 4,
		Name = "Abandoned Cinema",
		Boss = "The Phantom Projectionist",
		Theme = "Illusions, haunted screens, stealth",
	},
	{ Index = 5, Name = "Rooftop", Boss = "The Storm Wraith", Theme = "Storms, traversal, flying enemies" },
	{
		Index = 6,
		Name = "Secret Laboratory",
		Boss = "The Night Manager",
		Theme = "Revelations, experiments, final boss",
	},
}

local function planned(index: number, dayName: string, dayTeaser: string, nightName: string, nightTeaser: string)
	return {
		Id = string.format("L%02d", index),
		Index = index,
		Chapter = math.ceil(index / 7),
		Implemented = false,
		Day = { Name = dayName, Teaser = dayTeaser },
		Night = { Name = nightName, Teaser = nightTeaser },
	}
end

-- Typed loosely on purpose: implemented and planned levels have different shapes;
-- tests/Campaign.spec.luau validates the content instead.
local levels: { any } = {
	-- ── Chapter 1: The East Wing ────────────────────────────────────────────
	{
		Id = "L01",
		Index = 1,
		Chapter = 1,
		Implemented = true,
		Rewards = { Cash = 150, XP = 200 },
		Modules = {},
		Day = {
			Name = "First Shift",
			Teaser = "Claim a shop, stock it, serve customers, learn upgrades.",
			Story = "Welcome to Night Shift Mall! Lease a store and learn the ropes before closing time.",
			Duration = 150,
			Objectives = {
				{
					Id = "claim",
					Text = "Claim a shop in the East Wing",
					Event = "ShopClaimed",
					Hint = "Follow the marker to a FOR LEASE stand and press E.",
				},
				{
					Id = "stock",
					Text = "Order stock at your 📦 crates",
					Event = "Restocked",
					Hint = "The crates are in your shop's back corner. Press E.",
				},
				{
					Id = "serve",
					Text = "Serve customers at the register",
					Event = "Served",
					Target = 3,
					Hint = "When a 💬 customer waits at your till, press E.",
				},
				{
					Id = "upgrade",
					Text = "Buy your first upgrade",
					Event = "Upgraded",
					Hint = "Press B (or 🏪) and pick an upgrade you can afford.",
				},
				{ Id = "serve6", Text = "Serve 6 customers", Event = "Served", Target = 6, Optional = true },
			},
		},
		Night = {
			Name = "First Contact",
			Teaser = "Meet the Shadow Crawlers. Learn the flashlight. Survive.",
			Story = "Something crawls out of the dark. Your flashlight burns it. Use it.",
			Duration = 120,
			Objectives = {
				{
					Id = "equip",
					Text = "Equip your flashlight",
					Event = "FlashlightEquipped",
					Hint = "Press 1 (or tap the flashlight in your hotbar).",
				},
				{
					Id = "burn",
					Text = "Burn away a Shadow Crawler",
					Event = "Kill",
					Hint = "Hold click on a crawler. Step back when its eyes flare red!",
				},
				{ Id = "survive", Text = "Survive until dawn", Kind = "Survive" },
				{
					Id = "team6",
					Text = "Team: defeat 6 shadows",
					Event = "EnemyDefeated",
					Target = 6,
					Scope = "Team",
					Optional = true,
				},
				{ Id = "nodown", Text = "Don't get knocked down", Kind = "Avoid", Event = "Downed", Optional = true },
			},
			-- A gentle encounter: small waves, the fuse boxes stay powered.
			Rules = {
				Tier = 1,
				Fuses = false,
				Blackout = false,
				Waves = { Base = 2, PerPlayer = 1, Growth = 0, Interval = 24, MaxAlive = 4, FirstDelay = 10 },
				Intro = "🔦 Shadow Crawlers are waking up! Press 1 for your flashlight and burn them.",
			},
		},
	},
	{
		Id = "L02",
		Index = 2,
		Chapter = 1,
		Implemented = true,
		Rewards = { Cash = 250, XP = 300 },
		Modules = { "PowerGrid" },
		Day = {
			Name = "Power Failure",
			Teaser = "Find the failing electrical panels, repair them, set up emergency lamps.",
			Story = "The lights keep flickering. Grab spare fuses from the maintenance depot and fix the panels before dark.",
			Duration = 240,
			Objectives = {
				{
					Id = "panels",
					Text = "Repair the electrical panels",
					Event = "PanelRepaired",
					Target = 4,
					Scope = "Team",
					Hint = "Grab a ⚡ spare fuse at the maintenance depot, carry it to a sparking panel, hold E.",
					Marker = {
						Tag = "PowerPanel",
						Label = "🔧 REPAIR PANEL",
						Carry = "Fuse",
						Pickup = "SupplyFuse",
						PickupLabel = "⚡ GRAB A SPARE FUSE",
					},
				},
				{
					Id = "lamps",
					Text = "Set up emergency lamps",
					Event = "LampPlaced",
					Target = 3,
					Scope = "Team",
					Hint = "Take a 💡 lamp from the depot and place it on a glowing floor ring. Lamps protect you tonight!",
					Marker = {
						Tag = "LampSpot",
						Label = "💡 PLACE LAMP",
						Carry = "Lamp",
						Pickup = "SupplyLamp",
						PickupLabel = "💡 GRAB A LAMP",
					},
				},
				{
					Id = "lamps5",
					Text = "Place all 5 lamps (safer night)",
					Event = "LampPlaced",
					Target = 5,
					Scope = "Team",
					Optional = true,
				},
				{
					Id = "serve",
					Text = "Serve 3 customers between repairs",
					Event = "Served",
					Target = 3,
					Optional = true,
				},
			},
		},
		Night = {
			Name = "Total Blackout",
			Teaser = "The mall goes dark. Restore the breakers while crawlers patrol the halls.",
			Story = "The main breakers blew. Only your emergency lamps are on. Restore power before dawn!",
			Duration = 180,
			Objectives = {
				{
					Id = "breakers",
					Text = "Restore the breakers",
					Event = "BreakerRestored",
					Target = 3,
					Scope = "Team",
					Hint = "Follow the ⚡ marker. Hold E for 5 s; crawlers guard the breakers, so clear them first.",
				},
				{ Id = "survive", Text = "Hold out until dawn", Kind = "Survive" },
				{
					Id = "early",
					Text = "Restore power before midnight",
					Event = "PowerRestoredEarly",
					Scope = "Team",
					Optional = true,
				},
				{ Id = "burn3", Text = "Burn 3 shadows in the dark", Event = "Kill", Target = 3, Optional = true },
				{ Id = "nodown", Text = "Don't get knocked down", Kind = "Avoid", Event = "Downed", Optional = true },
			},
			-- Lights out everywhere; each breaker re-powers its zone. Crawlers patrol and see less.
			Rules = {
				Tier = 2,
				Fuses = true,
				RepairTime = 5,
				Blackout = true,
				Patrol = true,
				SightScale = 0.75,
				Guards = 3,
				EarlyFraction = 0.5,
				Waves = { Base = 1, PerPlayer = 1, Growth = 1, Interval = 30, MaxAlive = 7, FirstDelay = 25 },
				Intro = "🌑 TOTAL BLACKOUT! Restore the 3 breakers. Stay near your emergency lamps.",
			},
		},
	},
	{
		Id = "L03",
		Index = 3,
		Chapter = 1,
		Implemented = true,
		Rewards = { Cash = 350, XP = 400 },
		Modules = { "MissingDelivery", "Impostors" },
		Day = {
			Name = "The Missing Delivery",
			Teaser = "Follow a trail of clues, search the storage cages, bring the stolen stock back.",
			Story = "Last night's delivery vanished from the van. Something dragged it inside. Find it.",
			Duration = 240,
			Objectives = {
				{
					Id = "clues",
					Text = "Follow the trail of clues",
					Event = "ClueFound",
					Target = 3,
					Scope = "Team",
					Hint = "Inspect the glowing clue (hold E). Each one points to the next.",
					Marker = { Tag = "Clue", Label = "🔍 INSPECT CLUE" },
				},
				{
					Id = "stash",
					Text = "Find the stolen crates",
					Event = "StashFound",
					Scope = "Team",
					Hint = "Search the storage cages (hold E). The last clue tells you which one.",
					Marker = { Tag = "StorageCage", Label = "📦 SEARCH STORAGE", Prefer = "Hinted" },
				},
				{
					Id = "recover",
					Text = "Load the crates back into the van",
					Event = "CrateRecovered",
					Target = 4,
					Scope = "Team",
					Hint = "Grab a crate from the stash and carry it to the van outside the entrance. You keep some stock!",
					Marker = {
						Tag = "ReturnDock",
						Label = "🚚 LOAD THE VAN",
						Carry = "Crate",
						Pickup = "StashCrate",
						PickupLabel = "📦 GRAB A CRATE",
					},
				},
				{
					Id = "cages",
					Text = "Search all 4 storage cages",
					Event = "CageSearched",
					Target = 4,
					Scope = "Team",
					Optional = true,
				},
				{
					Id = "carry2",
					Text = "Carry 2 crates yourself",
					Event = "CrateRecovered",
					Target = 2,
					Optional = true,
				},
			},
		},
		Night = {
			Name = "Impostors",
			Teaser = "Phantom Shoppers hide among late shoppers. Spot them, unmask them, protect the real ones.",
			Story = "Shoppers are trapped inside after closing… but not all of them are people.",
			Duration = 180,
			Objectives = {
				{
					Id = "phantoms",
					Text = "Unmask & destroy the Phantom Shoppers",
					Event = "PhantomDefeated",
					Target = 4,
					Scope = "Team",
					Hint = "Phantoms stalk real shoppers, glitch and stare at you. Hold your beam on one to unmask it, then burn it.",
				},
				{
					Id = "protect",
					Text = "Shoppers lost",
					Kind = "Avoid",
					Event = "ShopperTaken",
					Allow = 2,
					Scope = "Team",
					Hint = "A shopper saying they're being followed is in danger. Unmask whoever is following them!",
				},
				{ Id = "survive", Text = "Survive until dawn", Kind = "Survive" },
				{
					Id = "saveall",
					Text = "Lose no shoppers at all",
					Kind = "Avoid",
					Event = "ShopperTaken",
					Scope = "Team",
					Optional = true,
				},
				{
					Id = "noaccuse",
					Text = "Never light up a real shopper",
					Kind = "Avoid",
					Event = "FalseAccusation",
					Optional = true,
				},
			},
			-- No breakers, no blackout: the threat hides in plain sight. A trickle of crawlers.
			Rules = {
				Tier = 3,
				Fuses = false,
				Blackout = false,
				Waves = { Base = 1, PerPlayer = 0.5, Growth = 0, Interval = 35, MaxAlive = 3, FirstDelay = 40 },
				Intro = "👥 Shoppers are trapped inside, and some of them aren't human. Watch closely.",
			},
		},
	},
	{
		Id = "L04",
		Index = 4,
		Chapter = 1,
		Implemented = true,
		Rewards = { Cash = 450, XP = 500 },
		Modules = { "SecuritySystem" },
		Day = {
			Name = "Security Upgrade",
			Teaser = "Repair cameras, power the terminals, arm the alarms, barricade your shop.",
			Story = "Management finally approved a security system. Get it running before they come back.",
			Duration = 240,
			Objectives = {
				{
					Id = "cameras",
					Text = "Repair the security cameras",
					Event = "CameraRepaired",
					Target = 4,
					Scope = "Team",
					Hint = "Stand under a sparking camera and hold E. One is on the upper level.",
					Marker = { Tag = "SecurityCamera", Label = "📷 REPAIR CAMERA" },
				},
				{
					Id = "terminals",
					Text = "Activate the security terminals",
					Event = "TerminalActivated",
					Target = 3,
					Scope = "Team",
					Hint = "Hold E on each terminal console. Tonight they're what the monsters go for.",
					Marker = { Tag = "SecurityTerminal", Label = "🖥️ ACTIVATE TERMINAL" },
				},
				{
					Id = "alarms",
					Text = "Arm the alarm panels",
					Event = "AlarmArmed",
					Target = 2,
					Scope = "Team",
					Hint = "Red alarm boxes on the atrium's east wall and at the East Wing's end.",
					Marker = { Tag = "AlarmPanel", Label = "🚨 ARM ALARM" },
				},
				{
					Id = "barricade",
					Text = "Barricade your shop entrance",
					Event = "BarricadeBuilt",
					Hint = "Grab planks at the hardware depot and build at your own shop door (claim a shop first).",
					Marker = {
						Tag = "BarricadeSpot",
						Label = "🪵 BUILD BARRICADE",
						Carry = "Planks",
						Pickup = "SupplyPlanks",
						PickupLabel = "🪵 GRAB PLANKS",
						Own = "Shop",
					},
				},
				{
					Id = "barricade3",
					Text = "Barricade 3 shops",
					Event = "BarricadeBuilt",
					Target = 3,
					Scope = "Team",
					Optional = true,
				},
			},
		},
		Night = {
			Name = "Mall Under Attack",
			Teaser = "Strike groups hit the terminals. Watch the cameras, sound alarms, defend every point.",
			Story = "They know about the cameras. They're coming for the terminals.",
			Duration = 200,
			Objectives = {
				{
					Id = "terminals",
					Text = "Terminals lost",
					Kind = "Avoid",
					Event = "TerminalLost",
					Allow = 1,
					Scope = "Team",
					Hint = "🚨 alerts name the terminal under attack. Check the cameras at any terminal; an alarm lures crawlers away.",
				},
				{ Id = "survive", Text = "Survive until dawn", Kind = "Survive" },
				{
					Id = "perfect",
					Text = "Lose no terminals",
					Kind = "Avoid",
					Event = "TerminalLost",
					Scope = "Team",
					Optional = true,
				},
				{
					Id = "repel",
					Text = "Repel 4 attacks",
					Event = "AttackRepelled",
					Target = 4,
					Scope = "Team",
					Optional = true,
				},
				{ Id = "alarm", Text = "Lure crawlers with an alarm", Event = "AlarmUsed", Optional = true },
				{ Id = "cams", Text = "Check the camera feeds", Event = "CamerasViewed", Optional = true },
			},
			Rules = {
				Tier = 4,
				Fuses = false,
				Blackout = false,
				Waves = { Base = 1, PerPlayer = 0.5, Growth = 0, Interval = 45, MaxAlive = 10, FirstDelay = 30 },
				Intro = "🚨 Security system online. Defend the terminals: alerts will tell you where they strike.",
			},
		},
	},
	planned(
		5,
		"Restricted Access",
		"Find access cards and solve a puzzle to open the locked corridor.",
		"The Stalker",
		"A monster that hunts by sound. Sneak, hide, and finish the job quietly."
	),
	planned(
		6,
		"Final Preparations",
		"Gather defensive materials, repair equipment, find clues about the boss.",
		"Rescue Mission",
		"Trapped shoppers! Reach them, escort them, defend the extraction point."
	),
	planned(
		7,
		"The Warning",
		"Uncover the boss's identity, prepare the arena, gear up.",
		"The Shadow Queen",
		"First boss: attack phases, arena hazards, co-op objectives."
	),
	-- ── Chapter 2: Food Court ───────────────────────────────────────────────
	planned(
		8,
		"Grand Reopening",
		"Run food deliveries between stalls.",
		"Grease Fire",
		"Spreading kitchen fires: extinguish while fighting."
	),
	planned(
		9,
		"Health Inspection",
		"Fix kitchen equipment against the clock.",
		"Cold Storage",
		"Freezer zones slow you; frozen crawlers thaw."
	),
	planned(
		10,
		"Lost Recipes",
		"Investigate the stalls for scattered recipe pages.",
		"Infected Diners",
		"Cure infected customers with light before they turn."
	),
	planned(
		11,
		"Supply Run",
		"Escort a supply cart through the court.",
		"Rat King's Court",
		"Swarms of small, fast enemies and traps."
	),
	planned(
		12,
		"Pipe Dreams",
		"Route water by turning valves (puzzle).",
		"Flooded Kitchens",
		"Rising water and live wires."
	),
	planned(13, "Feast Prep", "Co-op cooking stations.", "Siege of the Food Court", "Defend the stalls from waves."),
	planned(14, "The Chef's Warning", "Prepare the kitchen arena.", "The Gorging Chef", "Chapter 2 boss."),
	-- ── Chapter 3: Underground Parking ──────────────────────────────────────
	planned(
		15,
		"Down the Ramp",
		"Explore and map the garage levels.",
		"Headlights",
		"Car headlights become light weapons."
	),
	planned(
		16,
		"Jump Start",
		"Carry batteries to dead cars.",
		"Ticket Booth Terrors",
		"Patrols and stealth between cars."
	),
	planned(17, "Parking Puzzle", "Move carts to unblock routes.", "The Chase", "Outrun a Hunter along a set route."),
	planned(
		18,
		"Power Station B2",
		"Repair the garage substation.",
		"Sublevel Blackout",
		"Multi-level power restoration."
	),
	planned(
		19,
		"Lost & Found",
		"Track down missing shoppers' cars.",
		"Valet of the Damned",
		"Rescue drivers trapped below."
	),
	planned(20, "Barricades", "Build movable barriers.", "Gridlock", "Defend with barricades."),
	planned(21, "The Guardian Stirs", "Prepare the lowest level.", "The Concrete Guardian", "Chapter 3 boss."),
	-- ── Chapter 4: Abandoned Cinema ─────────────────────────────────────────
	planned(
		22,
		"Opening the Doors",
		"Restore the old projector.",
		"Now Showing",
		"Haunted screens flash warnings of attacks."
	),
	planned(23, "Reel Hunt", "Collect lost film reels.", "Mirror Lobby", "Illusions and fake exits."),
	planned(
		24,
		"Ticket Booth Mystery",
		"Crack the booth's code puzzle.",
		"Silent Film",
		"Stealth: every sound is heard."
	),
	planned(25, "Usher Training", "Seat guests correctly.", "Sold Out", "Phantom audience: find the real guests."),
	planned(
		26,
		"Behind the Screen",
		"Find the secret passages.",
		"Intermission of Fear",
		"Timed puzzle under pressure."
	),
	planned(27, "Final Cut", "Assemble the cursed reel.", "Projection Room Siege", "Hold the projection booth."),
	planned(28, "The Premiere", "Prepare the grand theatre.", "The Phantom Projectionist", "Chapter 4 boss."),
	-- ── Chapter 5: Rooftop ──────────────────────────────────────────────────
	planned(29, "Up on the Roof", "Traversal across the rooftops.", "First Storm", "Wind gusts push you around."),
	planned(30, "Lightning Rods", "Install lightning rods.", "Thunderstrike", "Dodge strikes; lure enemies into them."),
	planned(31, "Skylight Repairs", "Fix the dome from above.", "Winged Shadows", "Flying enemies."),
	planned(32, "Helipad", "Light signal fires.", "Stranded", "Rescue across the roofs."),
	planned(33, "Crane Operator", "Move cargo with the crane.", "Hailstorm", "Take cover from hail."),
	planned(34, "The Beacon", "Power the rooftop beacon.", "Eye of the Storm", "Hold the beacon at the storm's peak."),
	planned(35, "Calm Before", "Prepare the rooftop arena.", "The Storm Wraith", "Chapter 5 boss."),
	-- ── Chapter 6: Secret Laboratory ────────────────────────────────────────
	planned(36, "Hidden Elevator", "Find the way down.", "Specimen Escape", "Experimental creatures break loose."),
	planned(37, "Lab Notes", "Piece together what happened.", "Containment Breach", "Seal the breach doors."),
	planned(38, "Keycard Protocol", "Advanced keycard puzzles.", "Mutation", "Enemies adapt to your tactics."),
	planned(39, "The Founder's Office", "Story revelations.", "Mirror Experiments", "Copies of you, but wrong."),
	planned(40, "Reactor Check", "Stabilise the reactor.", "Meltdown", "Timed escape."),
	planned(41, "Last Allies", "Rally every survivor.", "The Hive", "Assault the nest."),
	planned(42, "Lights Out Forever?", "The final preparations.", "The Night Manager", "Multi-stage final boss."),
}

CampaignConfig.Levels = levels

CampaignConfig.IndexOf = {} :: { [string]: number }
CampaignConfig.ById = {} :: { [string]: any }
for _, level in CampaignConfig.Levels do
	CampaignConfig.IndexOf[level.Id] = level.Index
	CampaignConfig.ById[level.Id] = level
end

return CampaignConfig
