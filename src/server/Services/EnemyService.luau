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
local ShadowCrawler = require(script.Parent.Parent.Enemies.ShadowCrawler)
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
}

local EnemyService = {}
EnemyService.Killed = Signal.new() -- (enemy, contributors: {[Player]: number})

local BUILDERS = {
	ShadowCrawler = ShadowCrawler.build,
}

local enemies: { Enemy } = {}
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

	local stale = os.clock() - enemy.PathAt > 3
	local moved = enemy.PathGoal == nil or (enemy.PathGoal - goal).Magnitude > 10
	if (stale or moved or not enemy.Path) and not enemy.Computing then
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

-- The bite lands only if the target is still in reach after the wind-up (dodgeable), and
-- only if that player hasn't just been hit by anything (swarm protection).
local function resolveBite(enemy: Enemy, player: Player)
	if enemy.Dead or os.clock() < enemy.StunnedUntil then
		return
	end
	enemy.Model:SetAttribute("AttackAt", serverNow())
	local root = livingRoot(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local offset = root.Position - enemy.Root.Position
	if offset.Magnitude > enemy.Config.AttackRange + EnemyConfig.Combat.DodgeMargin then
		return -- dodged
	end
	local now = os.clock()
	if now - (lastHitAt[player] or 0) < EnemyConfig.Combat.PlayerHitGrace then
		return
	end
	lastHitAt[player] = now
	humanoid:TakeDamage(enemy.Config.Damage)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	Notify.effect(player, "Hit", {
		Damage = enemy.Config.Damage,
		Direction = if flat.Magnitude > 0.01 then flat.Unit else nil,
	})
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

local function think(enemy: Enemy, now: number)
	local humanoid = enemy.Humanoid
	local config = enemy.Config
	if now < enemy.StunnedUntil then
		humanoid.WalkSpeed = 0
		return
	end
	humanoid.WalkSpeed = config.WalkSpeed

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

	local player, root, distance = nearestPlayer(position, config.AggroRange, true)
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

-- night (1 = first) scales speed, damage, health and detection (EnemyConfig.Scaled).
function EnemyService.Spawn(typeId: string, position: Vector3, night: number?): Enemy?
	local build = BUILDERS[typeId]
	if not build or not EnemyConfig.Types[typeId] then
		warn("[EnemyService] unknown enemy type " .. tostring(typeId))
		return nil
	end
	local config = EnemyConfig.Scaled(typeId, night or 1)

	local model = build()
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
		EnemyService.Killed:Fire(enemy, enemy.Contributors)
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

function EnemyService.ClearAll()
	for _, enemy in table.clone(enemies) do
		remove(enemy)
	end
end

function EnemyService.GetAll(): { Enemy }
	return enemies
end

function EnemyService.AliveCount(): number
	return #enemies
end

function EnemyService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Enemies"
	folder.Parent = workspace
	workspace:SetAttribute("EnemiesAlive", 0)
end

function EnemyService.Start()
	Players.PlayerRemoving:Connect(function(player)
		lastHitAt[player] = nil
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
