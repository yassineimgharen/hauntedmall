-- A simulated player. It acts only through what a real client has: the MissionState
-- snapshot (objectives and markers), tags and prompts the game replicates, its own walking
-- along paths through the real geometry (no teleporting), and the same remotes as the client.
-- Its target picking copies GuideController and MissionClient.focusRow, so a bot that gets
-- lost means the in-game arrow would mislead a player too.

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Bot = {}
Bot.__index = Bot

export type Profile = {
	Name: string,
	Speed: number, -- fraction of walking speed (hesitation, detours)
	Reaction: number, -- seconds between deciding and acting
	Dodges: boolean, -- leaves red circles and lanes
	Fights: boolean, -- burns enemies that come close
}

Bot.Profiles = {
	Skilled = { Name = "Skilled", Speed = 1, Reaction = 0.3, Dodges = true, Fights = true },
	Average = { Name = "Average", Speed = 0.9, Reaction = 1, Dodges = true, Fights = true },
	Newcomer = { Name = "Newcomer", Speed = 0.7, Reaction = 2.5, Dodges = false, Fights = true },
	Slow = { Name = "Slow", Speed = 0.6, Reaction = 3, Dodges = true, Fights = true },
}

function Bot.new(world: any, player: any, profile: Profile?): any
	return setmetatable({
		World = world,
		Player = player,
		Profile = profile or Bot.Profiles.Skilled,
		Failures = {},
		Actions = {},
		Walked = 0,
		Deaths = 0,
		Strategies = {},
		Stopped = false,
		Tick = 0.1,
	}, Bot)
end

function Bot:fail(message: string)
	table.insert(self.Failures, { At = self.World.Now, Message = message })
end

function Bot:note(text: string)
	table.insert(self.Actions, string.format("%.1f %s", self.World.Now, text))
end

function Bot:wait(seconds: number)
	self.World.task.wait(seconds)
end

function Bot:root(): any
	local character = self.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

function Bot:health(): number
	local character = self.Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.Health else 0
end

function Bot:waitAlive()
	while not self:root() and self.Player.Parent do
		self:wait(0.25)
	end
end

function Bot:position(): any
	local root = self:root()
	return if root then root.Position else Vector3.zero
end

-- ── what the client knows ───────────────────────────────────────────────────

function Bot:snapshot(): any
	local list = self.Player._inbox.MissionState
	return list and list[#list] and list[#list].Args[1]
end

function Bot:toasts(): { string }
	local out = {}
	for _, entry in self.Player._inbox.Notify or {} do
		table.insert(out, entry.Args[1])
	end
	return out
end

function Bot:heard(pattern: string): boolean
	for _, text in self:toasts() do
		if text:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

function Bot:results(): { any }
	local out = {}
	for _, entry in self.Player._inbox.MissionResult or {} do
		table.insert(out, entry.Args[1])
	end
	return out
end

-- MissionClient.focusRow, but a Survive/Avoid row has nothing to walk to: skip those.
function Bot:focusRow(): any
	local snapshot = self:snapshot()
	if not snapshot or not snapshot.Rows or snapshot.Final then
		return nil
	end
	local carrying = self.Player:GetAttribute("Carrying")
	local first = nil
	for _, row in snapshot.Rows do
		if not row.Done and not row.Optional and row.Kind == "Count" then
			if carrying and row.Marker and row.Marker.Carry == carrying then
				return row
			end
			first = first or row
		end
	end
	return first
end

function Bot:row(id: string): any
	local snapshot = self:snapshot()
	for _, row in (snapshot and snapshot.Rows) or {} do
		if row.Id == id then
			return row
		end
	end
	return nil
end

local function nearest(self: any, parts: { any }): any
	local from = self:position()
	local best, bestDistance = nil, math.huge
	for _, part in parts do
		local distance = (part.Position - from).Magnitude
		if distance < bestDistance then
			best, bestDistance = part, distance
		end
	end
	return best
end

-- GuideController.openTagged
function Bot:openTagged(tag: string, own: string?, prefer: string?): { any }
	local parts, preferred = {}, {}
	for _, instance in self.World.CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") and not instance:GetAttribute("Done") then
			if own ~= "Shop" or instance:GetAttribute("ShopId") == self.Player:GetAttribute("ShopId") then
				table.insert(parts, instance)
				if prefer and instance:GetAttribute(prefer) then
					table.insert(preferred, instance)
				end
			end
		end
	end
	return if #preferred > 0 then preferred else parts
end

-- GuideController.missionTarget: where the in-game arrow points right now, and its label.
function Bot:markerTarget(row: any): (any, string?)
	local marker = row and row.Marker
	if not marker then
		-- the arrow's classic fallbacks: broken fuse boxes at night, the shop loop by day
		if self.World:phase() == "Night" then
			local broken = {}
			for _, fuse in self.World.CollectionService:GetTagged("FuseBox") do
				local box = fuse:FindFirstChild("Box")
				if box and fuse:GetAttribute("Broken") then
					table.insert(broken, box)
				end
			end
			local fuse = nearest(self, broken)
			return fuse, if fuse then "⚡ REPAIR FUSE" else nil
		end
		return self:shopTarget()
	end
	if marker.Own == "Shop" and self.Player:GetAttribute("ShopId") == nil then
		return self:shopTarget() -- "barricade your shop" without a shop: claim one first
	end
	if marker.Steps then
		local carrying = self.Player:GetAttribute("Carrying") or "None"
		for _, step in marker.Steps do
			if step.Carry == carrying then
				return nearest(self, self:openTagged(step.Tag)), step.Label
			end
		end
		return nil, nil
	end
	if marker.Carry and self.Player:GetAttribute("Carrying") ~= marker.Carry then
		return nearest(self, self:openTagged(marker.Pickup)), marker.PickupLabel
	end
	return nearest(self, self:openTagged(marker.Tag, marker.Own, marker.Prefer)), marker.Label
end

-- GuideController's shop loop: claim a stand, then serve or order stock.
function Bot:shopTarget(): (any, string?)
	local myShop = self.Player:GetAttribute("ShopId")
	local cs = self.World.CollectionService
	if myShop == nil then
		local stands = {}
		for _, shop in cs:GetTagged("Shop") do
			if shop:GetAttribute("OwnerUserId") == 0 then
				local board = shop:FindFirstChild("Board", true)
				if board then
					table.insert(stands, board)
				end
			end
		end
		return nearest(self, stands), "CLAIM"
	end
	for _, shop in cs:GetTagged("Shop") do
		if shop:GetAttribute("ShopId") == myShop then
			if (shop:GetAttribute("CustomersWaiting") or 0) > 0 then
				local counter = shop:FindFirstChild("Counter")
				return counter and counter:FindFirstChild("Top"), "SERVE"
			end
			if (self.Player:GetAttribute("ShopStock") or 0) == 0 then
				local crates = shop:FindFirstChild("Crates")
				return crates and crates:FindFirstChild("Crate"), "STOCK"
			end
		end
	end
	return nil, nil
end

-- PromptController: can this client see and use the prompt?
function Bot:usable(prompt: any): boolean
	if not prompt.Enabled or prompt:GetAttribute("Done") then
		return false
	end
	if prompt:HasTag("CarryPrompt") then
		local carrying = self.Player:GetAttribute("Carrying")
		local shop = prompt:GetAttribute("RequiresShop")
		if carrying == nil or prompt:GetAttribute("RequiresCarry") ~= carrying then
			return false
		end
		if shop ~= nil and shop ~= self.Player:GetAttribute("ShopId") then
			return false
		end
	end
	if prompt:HasTag("LockerPrompt") then
		local occupant = prompt:GetAttribute("Occupant") or 0
		if occupant ~= 0 and occupant ~= self.Player.UserId then
			return false
		end
	end
	return true
end

local function promptsIn(instance: any, into: { any })
	for _, d in instance:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			table.insert(into, d)
		end
	end
end

function Bot:promptsFor(target: any): { any }
	local list = {}
	promptsIn(target, list)
	if #list == 0 and target.Parent and target.Parent:IsA("Model") then
		promptsIn(target.Parent, list)
	end
	return list
end

function Bot:promptPosition(prompt: any): any
	local parent = prompt.Parent
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return parent.Position
end

-- ── moving ──────────────────────────────────────────────────────────────────

-- A red circle or lane on the floor that covers this point?
function Bot:dangerAt(p: any): any
	local folder = self.World.Workspace:FindFirstChild("Telegraphs")
	if not folder then
		return nil
	end
	for _, model in folder:GetChildren() do
		local outline = model:FindFirstChild("Outline")
		if outline then
			local cf, size = outline.CFrame, outline.Size
			local here = cf:PointToObjectSpace(p)
			if math.abs(p.Y - cf.Position.Y) < 8 then
				if model.Name == "DiscWarning" then
					local radius = size.Y / 2
					if Vector3.new(p.X - cf.Position.X, 0, p.Z - cf.Position.Z).Magnitude <= radius + 0.5 then
						return outline
					end
				elseif math.abs(here.X) <= size.X / 2 + 0.5 and math.abs(here.Z) <= size.Z / 2 + 0.5 then
					return outline
				end
			end
		end
	end
	return nil
end

function Bot:setPosition(floor: any, look: any?)
	local root = self:root()
	if not root then
		return
	end
	local at = floor + Vector3.new(0, 3, 0)
	local direction = look and Vector3.new(look.X, 0, look.Z)
	if direction and direction.Magnitude > 0.01 then
		root:_setCFrame(CFrame.lookAt(at, at + direction))
	else
		root:_setCFrame(CFrame.new(at) * root.CFrame.Rotation)
	end
end

function Bot:speed(): number
	local scale = self.Player:GetAttribute("MoveScale")
	local speed = 16 * self.Profile.Speed * (if type(scale) == "number" then scale else 1)
	return if self.SpeedCap then math.min(speed, self.SpeedCap) else speed
end

-- One step out of a telegraphed area, if we're in one and we dodge. Returns true if it moved.
function Bot:dodgeStep(): boolean
	if not self.Profile.Dodges then
		return false
	end
	local root = self:root()
	if not root then
		return false
	end
	local p = root.Position
	if not self:dangerAt(p) then
		return false
	end
	local world = self.World
	local floorY = p.Y - 3
	local step = 16 * self.Tick
	local best = nil
	for distance = 2, 14, 2 do
		for i = 0, 7 do
			local angle = i * math.pi / 4
			local q = p + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
			local y = world.standY(q.X, q.Z, floorY)
			if y and world.standable(q.X, q.Z, y) and not self:dangerAt(q) then
				best = Vector3.new(q.X, y, q.Z)
				break
			end
		end
		if best then
			break
		end
	end
	if not best then
		return false
	end
	local flat = Vector3.new(best.X - p.X, 0, best.Z - p.Z)
	if flat.Magnitude > 0.05 then
		local move = flat.Unit * math.min(step, flat.Magnitude)
		local nx, nz = p.X + move.X, p.Z + move.Z
		local y = world.standY(nx, nz, floorY)
		if y and not self:isWall(nx, nz, y) then
			self:setPosition(Vector3.new(nx, y, nz), flat)
		end
	end
	self:wait(self.Tick)
	return true
end

function Bot:isWall(x: number, z: number, y: number): boolean
	return not self.World.standable(x, z, y)
end

-- Walks a real path. `within` = 3D distance to the target's height; else flat `reach`.
-- Returns false if there's no way there (the failure is the caller's to judge).
-- Something solid appeared where the bot stands (a maze wall rising): Roblox physics pushes a
-- character out of it, so do the same, by the shortest move onto open floor. Counted in Ejected.
function Bot:eject(): boolean
	local world = self.World
	local p = self:position()
	local floor = p.Y - 3
	if world.standable(p.X, p.Z, floor) then
		return false
	end
	for radius = 1, 6 do
		for step = 0, 15 do
			local angle = step * math.pi / 8
			local x, z = p.X + math.cos(angle) * radius, p.Z + math.sin(angle) * radius
			local mx, mz = (x + p.X) / 2, (z + p.Z) / 2 -- never out through the far side of a wall
			if world.standable(x, z, floor) and (radius == 1 or world.standable(mx, mz, floor)) then
				self:setPosition(Vector3.new(x, floor, z), nil)
				self.Ejected = (self.Ejected or 0) + 1
				return true
			end
		end
	end
	return false
end

function Bot:walkTo(target: any, reach: number?, within: number?, shouldStop: (() -> boolean)?): boolean
	local world = self.World
	local version = -1
	local path, index = nil, 1
	local stuckAt = world.Now
	local started = world.Now
	local ejected = false
	while true do
		local root = self:root()
		if not root then
			return false
		end
		if shouldStop and shouldStop() then
			return true
		end
		if self:dodgeStep() then
			path = nil
			continue
		end
		if world.GeometryVersion ~= version or not path then
			version = world.GeometryVersion
			path = world:findPathWithin(root.Position - Vector3.new(0, 3, 0), target, reach or 2, within)
			index = 2
			if not path then
				if not ejected and self:eject() then
					ejected = true
					self:wait(self.Tick)
					continue
				end
				return false
			end
		end
		local waypoint = path[index]
		if not waypoint then
			return true
		end
		local p = root.Position
		local flat = Vector3.new(waypoint.X - p.X, 0, waypoint.Z - p.Z)
		local step = self:speed() * self.Tick
		if flat.Magnitude <= step then
			self:setPosition(waypoint, flat)
			self.Walked += flat.Magnitude
			index += 1
			stuckAt = world.Now
		else
			local move = flat.Unit * step
			local y = waypoint.Y + (p.Y - 3 - waypoint.Y) * 0.5
			self:setPosition(Vector3.new(p.X + move.X, y, p.Z + move.Z), flat)
			self.Walked += step
		end
		if world.Now - stuckAt > 20 or world.Now - started > 240 then
			return false
		end
		self:wait(self.Tick)
	end
end

function Bot:walkNear(part: any, maxDistance: number): boolean
	return self:walkTo(part.Position, nil, maxDistance)
end

-- ── prompts ─────────────────────────────────────────────────────────────────

-- Walk into range and hold E. Fails if the prompt turns off mid-hold (like the real one).
function Bot:hold(prompt: any): boolean
	local position = self:promptPosition(prompt)
	local range = prompt.MaxActivationDistance
	local world = self.World
	if not self:walkTo(position, nil, math.max(range - 1, 2)) then
		if not self:root() then
			return false -- died on the way: not a reachability problem
		end
		self:fail(
			string.format("can't reach prompt %q (%s) at %s", prompt.ActionText, prompt.ObjectText, tostring(position))
		)
		return false
	end
	-- Hesitates before a new job, but someone already waiting for a light to go green is ready.
	self:wait(if self.Primed then math.min(self.Profile.Reaction, 0.7) else self.Profile.Reaction)
	self.Primed = false
	local elapsed = 0
	while elapsed < prompt.HoldDuration do
		local root = self:root()
		if not root or not self:usable(prompt) or not prompt:IsDescendantOf(world.Workspace) then
			return false
		end
		if self:dangerAt(root.Position) and self.Profile.Dodges then
			return false
		end
		self:wait(self.Tick)
		elapsed += self.Tick
	end
	local root = self:root()
	if not root or not self:usable(prompt) or not prompt:IsDescendantOf(world.Workspace) then
		return false
	end
	if (root.Position - self:promptPosition(prompt)).Magnitude > range + 0.5 then
		self:fail("moved out of range of prompt " .. prompt.ActionText)
		return false
	end
	self:note("used " .. prompt.ActionText)
	prompt.Triggered:_fire(self.Player)
	self:wait(self.Tick)
	return true
end

-- ── flashlight ──────────────────────────────────────────────────────────────

function Bot:equip()
	local character = self.Player.Character
	if character and not character:FindFirstChild("Flashlight") then
		local backpack = self.Player:FindFirstChild("Backpack")
		local tool = backpack and backpack:FindFirstChild("Flashlight")
		if tool then
			tool.Parent = character
		end
	end
end

-- Walks to the closest place from which the part can be seen, as a player looking for an angle.
function Bot:walkToLine(part: any): boolean
	local world = self.World
	local params = world:require("Util.CollisionGroups").worldRaycastParams()
	local target = part.Position
	local floor = self:position().Y - 3
	for _, radius in { 6, 10, 14, 18, 24, 30 } do
		for step = 0, 15 do
			local angle = step * math.pi / 8
			local x, z = target.X + math.cos(angle) * radius, target.Z + math.sin(angle) * radius
			local y = world.standY(x, z, floor + 8)
			if y and world.standable(x, z, y) then
				local eye = Vector3.new(x, y + 4.5, z)
				local hit = world.Workspace:Raycast(eye, target - eye, params)
				if
					(hit == nil or hit.Instance == part or hit.Instance:IsDescendantOf(part.Parent))
					and self:walkTo(Vector3.new(x, y, z), 1.5)
				then
					return true
				end
			end
		end
	end
	return false
end

-- Is there a clear line from the head to this part (the same test the beam makes)?
function Bot:sees(part: any): boolean
	local character = self.Player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return false
	end
	local world = self.World
	local params = world:require("Util.CollisionGroups").worldRaycastParams()
	local hit = world.Workspace:Raycast(head.Position, part.Position - head.Position, params)
	return hit == nil or hit.Instance == part or hit.Instance:IsDescendantOf(part.Parent)
end

function Bot:beam(on: boolean, aim: any?)
	self.World:clientFire(self.Player, "SetBeam", on, aim)
end

function Bot:aimVector(point: any): any
	local character = self.Player.Character
	local head = character and character:FindFirstChild("Head")
	local root = self:root()
	if not head or not root then
		return Vector3.new(0, 0, -1)
	end
	local toward = point - head.Position
	local flat = Vector3.new(toward.X, 0, toward.Z)
	if flat.Magnitude > 0.05 then
		root:_setCFrame(CFrame.lookAt(root.Position, root.Position + flat))
	end
	return toward.Unit
end

-- Holds the beam on a moving or still point until done() or seconds pass.
function Bot:shine(getPoint: () -> any, done: () -> boolean, seconds: number): boolean
	self:equip()
	local world = self.World
	local stop = world.Now + seconds
	local on = false
	while world.Now < stop do
		if done() then
			break
		end
		if not self:root() then
			break
		end
		if self:dodgeStep() then
			continue
		end
		local battery = self.Player:GetAttribute("Battery")
		local point = getPoint()
		if not point then
			break
		end
		local aim = self:aimVector(point)
		if type(battery) == "number" and battery <= 0.02 then
			if on then
				self:beam(false, aim)
				on = false
			end
			self:wait(2)
		else
			if on then
				world:clientFire(self.Player, "AimUpdate", aim)
			else
				self:beam(true, aim)
				on = true
			end
			self:wait(self.Tick)
		end
	end
	if on then
		self:beam(false, nil)
	end
	return done()
end

function Bot:enemies(): { any }
	return self.World:require("Services.EnemyService").GetAll()
end

function Bot:nearestEnemy(range: number, visibleOnly: boolean?): any
	local best, bestDistance = nil, range
	local p = self:position()
	for _, enemy in self:enemies() do
		if not enemy.Dead and not enemy.Model:GetAttribute("Disguised") and (enemy.Config.LightScale or 1) > 0 then
			local distance = (enemy.Root.Position - p).Magnitude
			if distance < bestDistance and (not visibleOnly or self:sees(enemy.Root)) then
				best, bestDistance = enemy, distance
			end
		end
	end
	return best
end

-- Burns one nearby enemy until it's dead or it's been a while.
function Bot:fight(range: number?): boolean
	if not self.Profile.Fights then
		return false
	end
	local enemy = self:nearestEnemy(range or 18, true)
	if not enemy then
		return false
	end
	self:shine(function()
		if enemy.Dead then
			return nil
		end
		self:kite(enemy)
		return enemy.Root.Position
	end, function()
		return enemy.Dead
	end, 5)
	return true
end

-- Backs away from an enemy that's in biting range while the beam stays on it (what players
-- do: every chaser is slower than you). Called once per beam tick.
function Bot:kite(enemy: any)
	local root = self:root()
	if not root or not self.Profile.Dodges then
		return
	end
	local p = root.Position
	local away = Vector3.new(p.X - enemy.Root.Position.X, 0, p.Z - enemy.Root.Position.Z)
	if away.Magnitude > enemy.Config.AttackRange + 3 or away.Magnitude < 0.01 then
		return
	end
	local world = self.World
	local step = 16 * self.Tick
	for _, turn in { 0, 0.8, -0.8, 1.6, -1.6, 2.4, -2.4 } do
		local c, sn = math.cos(turn), math.sin(turn)
		local d = away.Unit
		local dir = Vector3.new(d.X * c - d.Z * sn, 0, d.X * sn + d.Z * c)
		local nx, nz = p.X + dir.X * step, p.Z + dir.Z * step
		local y = world.standY(nx, nz, p.Y - 3)
		if y and math.abs(y - (p.Y - 3)) < 2.2 and world.standable(nx, nz, y) then
			self:setPosition(Vector3.new(nx, y, nz))
			return
		end
	end
end

-- Walks at the nearest enemy anywhere and burns it (nights with nothing else to do).
function Bot:hunt(): boolean
	local enemy = self:nearestEnemy(400)
	if not enemy then
		return false
	end
	if (enemy.Root.Position - self:position()).Magnitude > 16 then
		self:walkTo(enemy.Root.Position, 12, nil, function()
			return enemy.Dead or (enemy.Root.Position - self:position()).Magnitude < 14
		end)
	end
	return self:fight(30)
end

-- ── working through a stage ─────────────────────────────────────────────────

local LIGHT_WORDS = { "SHINE", "EXORCISE", "BURN", "MELT" }
local function wantsLight(label: string?): boolean
	for _, word in LIGHT_WORDS do
		if label and label:find(word, 1, true) then
			return true
		end
	end
	return false
end

function Bot:useTarget(target: any, label: string?)
	local prompts = self:promptsFor(target)
	for _, prompt in prompts do
		if self:usable(prompt) then
			self:hold(prompt)
			return
		end
	end
	if #prompts > 0 then
		-- a prompt that's off for now (a live cable, a spitting growth): go and wait for it
		self:walkNear(target, math.max(prompts[1].MaxActivationDistance - 1.5, 3))
		self.Primed = true
		self:wait(0.25)
		return
	end
	if wantsLight(label) then
		-- Walks until there's a clear line, as a player would: being close isn't enough
		-- when a wall is in the way.
		local function lined(): boolean
			return (target.Position - self:position()).Magnitude <= 30 and self:sees(target)
		end
		if not self:walkTo(target.Position, 5, nil, lined) and not self:walkTo(target.Position, nil, 7, lined) then
			if self:root() then
				self:fail("can't get a clear flashlight line to " .. target.Name .. " at " .. tostring(target.Position))
			end
			self:wait(1)
			return
		end
		local tag = target:GetTags()[1]
		local shone = self:shine(function()
			return target.Position
		end, function()
			return target:GetAttribute("Done") == true
				or not target:IsDescendantOf(self.World.Workspace)
				or (tag ~= nil and not target:HasTag(tag))
		end, 9)
		if not shone and not self:sees(target) then
			self:walkToLine(target) -- the nearest spot was behind a wall: go round to one with a view
		end
		return
	end
	if not self:walkTo(target.Position, 2) then
		if self:root() then
			self:fail("can't walk to marker target " .. target.Name .. " at " .. tostring(target.Position))
		end
		self:wait(1)
		return
	end
	self:wait(0.3)
end

-- Plays the current stage until its phase ends or everything required is done.
function Bot:playStage(stage: string)
	local world = self.World
	local rs = world.ReplicatedStorage
	self:wait(self.Profile.Reaction)
	while rs:GetAttribute("Phase") == stage and self.Player.Parent and not self.Stopped do
		if not self:root() then
			self.Deaths += 1
			self:waitAlive()
			continue
		end
		if self:dodgeStep() then
			continue
		end
		if self.Strategies.Reflex and self.Strategies.Reflex(self) then
			continue
		end
		if not self.Pacifist and self:fight() then
			continue
		end
		local row = self:focusRow()
		local strategy = row and (self.Strategies[row.Id] or self.Strategies[row.Event])
		if strategy then
			strategy(self, row)
		elseif row then
			local target, label = self:markerTarget(row)
			if target then
				self:useTarget(target, label)
			else
				self:wait(0.5)
			end
		else
			local idle = self.Strategies.Idle
			if idle then
				idle(self)
			elseif not (stage == "Night" and self.Profile.Fights and self:hunt()) then
				self:wait(0.5)
			end
		end
		self:wait(self.Tick)
	end
end

return Bot
