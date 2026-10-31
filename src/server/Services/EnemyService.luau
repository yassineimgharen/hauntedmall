-- Server-authoritative enemy lifecycle and AI.
--
-- AI states (re-evaluated every AIThinkInterval, staggered across enemies):
--   Stunned  → frozen while StunnedUntil > now
--   Hunt     → nearest living player in AggroRange (line of sight, or very close)
--   Attack   → player within AttackRange: damage on cooldown
--   Raid     → no player nearby: walk to an owned shop with stock and drain it
--   Prowl    → nothing else to do: head toward the nearest player anywhere
-- Movement: direct MoveTo when the goal is visible on the same level, otherwise a cached
-- PathfindingService path recomputed when the goal moves or the path goes stale.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnemyConfig = require(ReplicatedStorage.Shared.Config.EnemyConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local FrostWraith = require(script.Parent.Parent.Enemies.FrostWraith)
local Meatball = require(script.Parent.Parent.Enemies.Meatball)
local ParcelMimic = require(script.Parent.Parent.Enemies.ParcelMimic)
local PossessedCart = require(script.Parent.Parent.Enemies.PossessedCart)
local ShadowCrawler = require(script.Parent.Parent.Enemies.ShadowCrawler)
local SporeBloater = require(script.Parent.Parent.Enemies.SporeBloater)
local CollisionGroups = require(script.Parent.Parent.Util.CollisionGroups)
local Notify = require(script.Parent.Parent.Util.Notify)
local ShopService = require(script.Parent.ShopService)

export type Enemy = {
	Type: string,
	Config: EnemyConfig.EnemyType,
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	HP: number,
	Dead: boolean,
	Contributors: { [Player]: number },
	NextThink: number,
	LastAttack: number,
	WindupUntil: number,
	LastDrain: number,
	StunnedUntil: number,
	TargetShop: ShopService.Shop?,
	PathObject: Path,
	Path: { PathWaypoint }?,
	PathIndex: number,
	PathGoal: Vector3?,
	PathAt: number,
	Computing: boolean,
	LastPosition: Vector3,
	LastProgressAt: number,
	Patrols: boolean, -- walks a patrol route instead of hunting shops when no one is in sight
	PatrolTarget: Vector3?,
	Goal: Goal?, -- level objective this enemy attacks when no player is in sight
	LureUntil: number, -- os.clock(): drawn to LurePosition (alarms) until then
	LurePosition: Vector3?,
	Custom: { [string]: any }, -- per-type state for Kind.Think (and hooks a level sets)
}

-- Something an enemy marches on and hits (e.g. a security terminal).
export type Goal = {
	Position: Vector3,
	Alive: () -> boolean,
	Hit: (enemy: any) -> (),
}

-- Night-specific behaviour, set by NightService from the level's rules.
export type Behavior = {
	PatrolPoints: { Vector3 }?, -- if set, some enemies patrol these points
	PatrolShare: number, -- fraction of new spawns that patrol
	SightScale: number, -- multiplies AggroRange (e.g. 0.75 in a blackout)
}

local EnemyService = {}
EnemyService.Killed = Signal.new() -- (enemy, contributors: {[Player]: number})

-- What an enemy type adds to the shared AI (Enemies/*.luau). Only Build is required.
--   Think    runs every AI tick before the default behaviour; return true to skip it
--   OnLit    the flashlight is on it this tick (after any light damage)
--   OnKilled it just died (e.g. split into smaller enemies)
-- They get the `ai` helpers below instead of requiring this service (no require cycle).
export type Kind = {
	Build: () -> Model,
	Think: ((enemy: Enemy, now: number, ai: any) -> boolean)?,
	OnLit: ((enemy: Enemy, player: Player, dt: number, ai: any) -> ())?,
	OnKilled: ((enemy: Enemy, ai: any) -> ())?,
}

local KINDS: { [string]: Kind } = {
	ShadowCrawler = {
		Build = function()
			return ShadowCrawler.build()
		end,
	},
	PhantomShopper = {
		Build = function()
			return ShadowCrawler.build("Phantom")
		end,
	},
	PossessedCart = PossessedCart :: any,
	ParcelMimic = ParcelMimic.Mimic :: any,
	ParcelMite = ParcelMimic.Mite :: any,
	FrostWraith = FrostWraith :: any,
	SporeBloater = SporeBloater :: any,
	Meatball = Meatball :: any,
}

local enemies: { Enemy } = {}
local DEFAULT_BEHAVIOR: Behavior = { PatrolPoints = nil, PatrolShare = 0, SightScale = 1 }
local behavior: Behavior = DEFAULT_BEHAVIOR
local folder: Folder
local rayParams = CollisionGroups.worldRaycastParams()
local rng = Random.new()

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function hasLineOfSight(from: Vector3, to: Vector3): boolean
	return workspace:Raycast(from, to - from, rayParams) == nil
end

local function livingRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root then
		return root :: BasePart
	end
	return nil
end

local function nearestPlayer(position: Vector3, range: number, requireSight: boolean): (Player?, BasePart?, number)
	local best, bestRoot, bestDistance = nil, nil, range
	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root then
			local distance = (root.Position - position).Magnitude
			if
				distance < bestDistance
				and (not requireSight or distance < 25 or hasLineOfSight(position, root.Position))
			then
				best, bestRoot, bestDistance = player, root, distance
			end
		end
	end
	return best, bestRoot, bestDistance
end

local function computePath(enemy: Enemy, goal: Vector3)
	enemy.Computing = true
	enemy.PathGoal = goal
	enemy.PathAt = os.clock()
	task.spawn(function()
		local ok = pcall(function()
			enemy.PathObject:ComputeAsync(enemy.Root.Position, goal)
		end)
		enemy.Computing = false
		if enemy.Dead then
			return
		end
		if ok and enemy.PathObject.Status == Enum.PathStatus.Success then
			enemy.Path = enemy.PathObject:GetWaypoints()
			enemy.PathIndex = 2
		else
			enemy.Path = nil
			enemy.Humanoid:MoveTo(goal)
		end
	end)
end

local function navigate(enemy: Enemy, goal: Vector3)
	local position = enemy.Root.Position
	if math.abs(goal.Y - position.Y) < 6 and hasLineOfSight(position, goal + Vector3.new(0, 1, 0)) then
		enemy.Path = nil
		enemy.Humanoid:MoveTo(goal)
		return
	end

	-- no path yet (or the last one failed, or was used up): try again, but at most once a
	-- second, not on every AI tick; an unreachable goal must not spam the pathfinder
	local age = os.clock() - enemy.PathAt
	local stale = age > 3
	local moved = enemy.PathGoal == nil or (enemy.PathGoal - goal).Magnitude > 10
	if (stale or moved or (not enemy.Path and age > 1)) and not enemy.Computing then
		computePath(enemy, goal)
	end

	local path = enemy.Path
	if path then
		local waypoint = path[enemy.PathIndex]
		while waypoint and flatDistance(waypoint.Position, position) < 3.5 do
			enemy.PathIndex += 1
			waypoint = path[enemy.PathIndex]
		end
		if waypoint then
			enemy.Humanoid:MoveTo(waypoint.Position)
		else
			enemy.Path = nil
		end
	end
end

local function face(enemy: Enemy, point: Vector3)
	local position = enemy.Root.Position
	local flat = Vector3.new(point.X, position.Y, point.Z)
	if (flat - position).Magnitude > 0.1 then
		enemy.Root.CFrame = CFrame.lookAt(position, flat)
	end
end

local lastHitAt: { [Player]: number } = {}
local spawnedAt: { [Player]: number } = {}

-- The one way monsters (and bosses) hurt players. Nothing lands within PlayerHitGrace of
-- the last hit (swarm protection) or RespawnGrace of spawning. `from` aims the knockback.
-- Returns whether the hit landed.
function EnemyService.HitPlayer(player: Player, damage: number, from: Vector3): boolean
	local root = livingRoot(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return false
	end
	local now = os.clock()
	local combat = EnemyConfig.Combat
	if
		now - (lastHitAt[player] or 0) < combat.PlayerHitGrace
		or now - (spawnedAt[player] or 0) < combat.RespawnGrace
	then
		return false
	end
	lastHitAt[player] = now
	humanoid:TakeDamage(damage)
	local flat = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	Notify.effect(player, "Hit", {
		Damage = damage,
		Direction = if flat.Magnitude > 0.01 then flat.Unit else nil,
	})
	return true
end

-- The bite lands only if the target is still in reach after the wind-up (dodgeable), and
-- only if that player hasn't just been hit by anything (swarm protection).
local function resolveBite(enemy: Enemy, player: Player)
	if enemy.Dead or os.clock() < enemy.StunnedUntil then
		return
	end
	enemy.Model:SetAttribute("AttackAt", serverNow())
	local root = livingRoot(player)
	if not root then
		return
	end
	if (root.Position - enemy.Root.Position).Magnitude > enemy.Config.AttackRange + EnemyConfig.Combat.DodgeMargin then
		return -- dodged
	end
	EnemyService.HitPlayer(player, enemy.Config.Damage, enemy.Root.Position)
end

-- Telegraphed attack: stop, rear up (clients see WindupAt), warn the target, then bite.
local function attackPlayer(enemy: Enemy, player: Player, now: number)
	if now < enemy.WindupUntil or now - enemy.LastAttack < enemy.Config.AttackCooldown then
		return
	end
	enemy.LastAttack = now
	enemy.WindupUntil = now + enemy.Config.AttackWindup
	enemy.Model:SetAttribute("WindupAt", serverNow())
	Notify.effect(player, "Danger", { Windup = enemy.Config.AttackWindup })
	task.delay(enemy.Config.AttackWindup, resolveBite, enemy, player)
end

local function pickShop(position: Vector3): ShopService.Shop?
	local best, bestDistance = nil, math.huge
	for _, shop in ShopService.GetOwnedShops() do
		if ShopService.GetStock(shop) > 0 then
			local distance = (shop.Model:GetAttribute("P_Stock") - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = shop, distance
			end
		end
	end
	return best
end

local AI -- helpers handed to Kind hooks (filled in below, once everything is defined)

local function think(enemy: Enemy, now: number)
	local humanoid = enemy.Humanoid
	local config = enemy.Config
	if now < enemy.StunnedUntil then
		humanoid.WalkSpeed = 0
		return
	end
	humanoid.WalkSpeed = config.WalkSpeed
	local kind = KINDS[enemy.Type]
	if kind.Think and kind.Think(enemy, now, AI) then
		return
	end

	local position = enemy.Root.Position
	if now < enemy.WindupUntil then
		humanoid:MoveTo(position) -- planted while rearing up: the player's window to escape
		return
	end

	-- stuck detection
	if (position - enemy.LastPosition).Magnitude > 1 then
		enemy.LastPosition = position
		enemy.LastProgressAt = now
	elseif now - enemy.LastProgressAt > 1.5 then
		enemy.LastProgressAt = now
		enemy.PathAt = 0
		humanoid.Jump = true
	end

	-- an alarm pulls it in; it only bites someone standing right next to it
	if now < enemy.LureUntil and enemy.LurePosition then
		local nearby, nearbyRoot, nearbyDistance = nearestPlayer(position, config.AttackRange, false)
		if nearby and nearbyRoot and nearbyDistance <= config.AttackRange then
			humanoid:MoveTo(position)
			face(enemy, nearbyRoot.Position)
			attackPlayer(enemy, nearby, now)
		elseif flatDistance(position, enemy.LurePosition) > 5 then
			navigate(enemy, enemy.LurePosition)
		else
			enemy.LastProgressAt = now
			humanoid:MoveTo(position)
		end
		return
	end

	local player, root, distance = nearestPlayer(position, config.AggroRange * behavior.SightScale, true)
	if player and root then
		enemy.LastProgressAt = if distance <= config.AttackRange then now else enemy.LastProgressAt
		if distance <= config.AttackRange then
			humanoid:MoveTo(position)
			face(enemy, root.Position)
			attackPlayer(enemy, player, now)
		else
			navigate(enemy, root.Position)
		end
		return
	end

	local goal = enemy.Goal
	if goal and not goal.Alive() then
		enemy.Goal = nil
		goal = nil
	end
	if goal then
		if flatDistance(position, goal.Position) < 6 then
			enemy.LastProgressAt = now
			humanoid:MoveTo(position)
			face(enemy, goal.Position)
			if now - enemy.LastDrain >= config.ShopDrainInterval then
				enemy.LastDrain = now
				enemy.Model:SetAttribute("AttackAt", serverNow())
				goal.Hit(enemy)
			end
		else
			navigate(enemy, goal.Position)
		end
		return
	end

	local patrol = behavior.PatrolPoints
	if enemy.Patrols and patrol and #patrol > 0 then
		local goal = enemy.PatrolTarget
		if not goal or flatDistance(position, goal) < 6 then
			goal = patrol[rng:NextInteger(1, #patrol)]
			enemy.PatrolTarget = goal
		end
		navigate(enemy, goal :: Vector3)
		return
	end

	local shop = enemy.TargetShop
	if not shop or not shop.Owner or ShopService.GetStock(shop) <= 0 then
		shop = pickShop(position)
		enemy.TargetShop = shop
	end
	if shop then
		local point = shop.Model:GetAttribute("P_Stock") :: Vector3
		if flatDistance(position, point) < 5 then
			enemy.LastProgressAt = now
			humanoid:MoveTo(position)
			if now - enemy.LastDrain >= config.ShopDrainInterval then
				enemy.LastDrain = now
				enemy.Model:SetAttribute("AttackAt", serverNow())
				ShopService.Drain(shop, config.ShopDrain)
			end
		else
			navigate(enemy, point)
		end
		return
	end

	local _, anyRoot = nearestPlayer(position, math.huge, false)
	navigate(enemy, if anyRoot then anyRoot.Position else Vector3.zero)
end

local function remove(enemy: Enemy)
	enemy.Dead = true
	local index = table.find(enemies, enemy)
	if index then
		table.remove(enemies, index)
	end
	workspace:SetAttribute("EnemiesAlive", #enemies)
	if enemy.Model.Parent then
		enemy.Root.Anchored = true
		enemy.Model:SetAttribute("Dead", true)
		task.delay(1.4, function()
			enemy.Model:Destroy()
		end)
	end
end

-- Is a living player too close for a monster to appear here? (Levels pick another spot.)
function EnemyService.PlayerNear(position: Vector3, range: number?): boolean
	local player = nearestPlayer(position, range or EnemyConfig.SpawnClearance, false)
	return player ~= nil
end

-- night (1 = first) scales speed, damage, health and detection (EnemyConfig.Scaled).
function EnemyService.Spawn(typeId: string, position: Vector3, night: number?): Enemy?
	local kind = KINDS[typeId]
	if not kind or not EnemyConfig.Types[typeId] then
		warn("[EnemyService] unknown enemy type " .. tostring(typeId))
		return nil
	end
	local config = EnemyConfig.Scaled(typeId, night or 1)

	local model = kind.Build()
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	CollisionGroups.assign(model, CollisionGroups.Enemies)
	model:PivotTo(
		CFrame.new(position + Vector3.new(0, config.HipHeight, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	)
	model:SetAttribute("EnemyType", typeId)
	model:SetAttribute("HP", config.MaxHealth)
	model:SetAttribute("MaxHP", config.MaxHealth)
	model:SetAttribute("Windup", config.AttackWindup)
	model:SetAttribute("SpawnedAt", serverNow())
	CollectionService:AddTag(model, "Enemy")
	model.Parent = folder
	root:SetNetworkOwner(nil)

	local now = os.clock()
	local enemy: Enemy = {
		Type = typeId,
		Config = config,
		Model = model,
		Root = root,
		Humanoid = humanoid,
		HP = config.MaxHealth,
		Dead = false,
		Contributors = {},
		NextThink = now + 0.8 + rng:NextNumber(0, EnemyConfig.AIThinkInterval), -- emerge first
		LastAttack = 0,
		WindupUntil = 0,
		LastDrain = 0,
		StunnedUntil = 0,
		TargetShop = nil,
		PathObject = PathfindingService:CreatePath({
			AgentRadius = 2.5,
			AgentHeight = 5,
			AgentCanJump = false,
			WaypointSpacing = 6,
		}),
		Path = nil,
		PathIndex = 1,
		PathGoal = nil,
		PathAt = 0,
		Computing = false,
		LastPosition = root.Position,
		LastProgressAt = now,
		Patrols = behavior.PatrolPoints ~= nil and rng:NextNumber() < behavior.PatrolShare,
		PatrolTarget = nil,
		Goal = nil,
		LureUntil = 0,
		LurePosition = nil,
		Custom = {},
	}
	table.insert(enemies, enemy)
	workspace:SetAttribute("EnemiesAlive", #enemies)
	return enemy
end

function EnemyService.Damage(enemy: Enemy, amount: number, source: Player?)
	if enemy.Dead or amount <= 0 then
		return
	end
	enemy.HP -= amount
	if source then
		enemy.Contributors[source] = (enemy.Contributors[source] or 0) + amount
	end
	enemy.Model:SetAttribute("HP", math.max(0, math.ceil(enemy.HP)))
	enemy.Model:SetAttribute("LitUntil", serverNow() + 0.3)
	if enemy.HP <= 0 then
		remove(enemy)
		local onKilled = KINDS[enemy.Type].OnKilled
		if onKilled then
			local ok, err = pcall(onKilled, enemy, AI)
			if not ok then
				warn("[EnemyService] OnKilled error: " .. tostring(err))
			end
		end
		EnemyService.Killed:Fire(enemy, enemy.Contributors)
	end
end

-- Flashlight damage (CombatService): scaled by the type's LightScale, then its OnLit hook.
-- Light-proof enemies still flash "lit" so players see the beam land.
function EnemyService.Burn(enemy: Enemy, amount: number, player: Player, dt: number)
	if enemy.Dead then
		return
	end
	local scale = enemy.Config.LightScale or 1
	if scale > 0 then
		EnemyService.Damage(enemy, amount * scale, player)
	else
		enemy.Model:SetAttribute("LitUntil", serverNow() + 0.3)
	end
	local onLit = KINDS[enemy.Type].OnLit
	if onLit and not enemy.Dead then
		onLit(enemy, player, dt, AI)
	end
end

function EnemyService.StunAll(seconds: number)
	local untilClock = os.clock() + seconds
	for _, enemy in enemies do
		enemy.StunnedUntil = untilClock
		enemy.Humanoid:MoveTo(enemy.Root.Position)
		enemy.Model:SetAttribute("StunnedUntil", serverNow() + seconds)
	end
end

function EnemyService.Stun(enemy: Enemy, seconds: number)
	if enemy.Dead then
		return
	end
	local untilClock = os.clock() + seconds
	if untilClock > enemy.StunnedUntil then
		enemy.StunnedUntil = untilClock
		enemy.Humanoid:MoveTo(enemy.Root.Position)
		enemy.Model:SetAttribute("StunnedUntil", serverNow() + seconds)
	end
end

function EnemyService.ClearAll()
	for _, enemy in table.clone(enemies) do
		remove(enemy)
	end
end

-- Draws every enemy within `radius` of `center` there for `seconds`. Returns how many.
function EnemyService.Lure(center: Vector3, radius: number, seconds: number): number
	local count = 0
	for _, enemy in enemies do
		if not enemy.Dead and (enemy.Root.Position - center).Magnitude <= radius then
			enemy.LureUntil = os.clock() + seconds
			enemy.LurePosition = center
			enemy.PathAt = 0
			count += 1
		end
	end
	return count
end

-- nil restores the default (hunt players, raid shops, full sight).
function EnemyService.SetBehavior(newBehavior: Behavior?)
	behavior = newBehavior or DEFAULT_BEHAVIOR
end

function EnemyService.GetAll(): { Enemy }
	return enemies
end

function EnemyService.AliveCount(): number
	return #enemies
end

AI = {
	NearestPlayer = nearestPlayer, -- (position, range, requireSight) -> (Player?, BasePart?, distance)
	LivingRoot = livingRoot,
	Navigate = navigate,
	Face = face,
	Attack = attackPlayer, -- the standard telegraphed bite (enemy, player, now)
	HitPlayer = EnemyService.HitPlayer,
	Spawn = EnemyService.Spawn,
	Stun = EnemyService.Stun,
	LineOfSight = hasLineOfSight,
	FlatDistance = flatDistance,
	ServerNow = serverNow,
	Warn = function(player: Player, seconds: number)
		Notify.effect(player, "Danger", { Windup = seconds })
	end,
}

function EnemyService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace
	workspace:SetAttribute("EnemiesAlive", 0)
end

function EnemyService.Start()
	local function watchSpawns(player: Player)
		player.CharacterAdded:Connect(function()
			spawnedAt[player] = os.clock()
		end)
	end
	Players.PlayerAdded:Connect(watchSpawns)
	for _, player in Players:GetPlayers() do
		watchSpawns(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastHitAt[player] = nil
		spawnedAt[player] = nil
	end)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, enemy in table.clone(enemies) do
			if not enemy.Dead and now >= enemy.NextThink then
				enemy.NextThink = now + EnemyConfig.AIThinkInterval
				local ok, err = pcall(think, enemy, now)
				if not ok then
					warn("[EnemyService] AI error: " .. tostring(err))
				end
			end
		end
	end)
end

return EnemyService
