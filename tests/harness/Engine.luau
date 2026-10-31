-- A fake Roblox engine for Lune. It boots the UNMODIFIED server code (src/server, src/shared)
-- with deterministic simulated time, seeded randomness and mocked services, so tests exercise
-- production level logic rather than a copy of its rules.
--
-- What it models: instances with reflection-checked classes and properties (a typo'd property
-- or class fails like it does in Roblox), attributes and tags, signals, a coroutine scheduler
-- (task.*), joints, tweens (applied at their end), remotes with an inbox per player, players
-- and characters with respawning, a mock DataStore with failure injection, raycasts and
-- walkability computed from the real generated geometry (oriented boxes).
--
-- What it does NOT model: real physics, Humanoid behaviour, rendering, the real pathfinder,
-- network latency, client scripts. Passing here is "simulated gameplay", not "Studio-tested".

local fs = require("@lune/fs")
local process = require("@lune/process")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local db = roblox.getReflectionDatabase()
local realTypeof = typeof

local Engine = {}

-- ── reflection (shared between worlds) ──────────────────────────────────────

type ClassInfo =
	{ Exists: boolean, Props: { [string]: any }, Defaults: { [string]: any }, Super: { [string]: boolean } }
local classCache: { [string]: ClassInfo } = {}

local function classInfo(name: string): ClassInfo
	local cached = classCache[name]
	if cached then
		return cached
	end
	local info: ClassInfo = { Exists = false, Props = {}, Defaults = {}, Super = {} }
	local current = db:GetClass(name)
	info.Exists = current ~= nil
	local chain = {}
	while current do
		table.insert(chain, 1, current)
		info.Super[current.Name] = true
		current = if current.Superclass then db:GetClass(current.Superclass) else nil
	end
	for _, class in chain do
		for key, prop in class.Properties do
			info.Props[key] = prop
		end
		for key, value in class.DefaultProperties do
			info.Defaults[key] = value
		end
	end
	classCache[name] = info
	return info
end

local DATATYPE_DEFAULTS: { [string]: any } = {
	bool = false,
	Bool = false,
	string = "",
	String = "",
	float = 0,
	Float = 0,
	Float32 = 0,
	Float64 = 0,
	double = 0,
	int = 0,
	int64 = 0,
	Int32 = 0,
	Int64 = 0,
	Vector3 = Vector3.zero,
	CFrame = CFrame.new(),
	Color3 = roblox.Color3.new(0, 0, 0),
	UDim2 = roblox.UDim2.new(),
	Vector2 = roblox.Vector2.new(0, 0),
}

local CLASS_DEFAULTS: { [string]: { [string]: any } } = {
	BasePart = {
		Size = Vector3.new(4, 1.2, 2),
		CFrame = CFrame.new(),
		Anchored = false,
		CanCollide = true,
		CanQuery = true,
		CanTouch = true,
		Transparency = 0,
		CollisionGroup = "Default",
		AssemblyLinearVelocity = Vector3.zero,
		AssemblyMass = 1,
	},
	ProximityPrompt = { Enabled = true, MaxActivationDistance = 10, RequiresLineOfSight = true, HoldDuration = 0 },
	Humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16, HipHeight = 2, JumpPower = 50 },
	Light = { Enabled = true, Brightness = 1, Range = 8 },
	ParticleEmitter = { Enabled = true },
	BillboardGui = { Enabled = true },
	SurfaceGui = { Enabled = true },
	Highlight = { Enabled = true },
	Beam = { Enabled = true },
	Trail = { Enabled = true },
	GuiObject = { Visible = true },
}

-- Real properties the reflection data leaves out or doesn't let us read.
local EXTRA_PROPS = {
	Position = true,
	Orientation = true,
	Rotation = true,
	AssemblyMass = true,
	WorldPivot = true,
	WorldPosition = true,
	ProcessReceipt = true,
	JobId = true,
}

local EVENTS = {}
for _, name in
	{
		"Triggered",
		"TriggerEnded",
		"PromptButtonHoldBegan",
		"PromptButtonHoldEnded",
		"Touched",
		"TouchEnded",
		"Changed",
		"ChildAdded",
		"ChildRemoved",
		"DescendantAdded",
		"DescendantRemoving",
		"AncestryChanged",
		"Destroying",
		"Died",
		"MoveToFinished",
		"HealthChanged",
		"StateChanged",
		"Running",
		"CharacterAdded",
		"CharacterRemoving",
		"CharacterAppearanceLoaded",
		"PlayerAdded",
		"PlayerRemoving",
		"Heartbeat",
		"Stepped",
		"RenderStepped",
		"PreSimulation",
		"PostSimulation",
		"OnServerEvent",
		"OnClientEvent",
		"Completed",
		"PromptGamePassPurchaseFinished",
		"PromptProductPurchaseFinished",
		"Activated",
		"Deactivated",
		"Equipped",
		"Unequipped",
	}
do
	EVENTS[name] = true
end

-- ── compiled sources (shared between worlds) ────────────────────────────────

local bytecode: { [string]: string } = {}
local function compiled(path: string): string
	local code = bytecode[path]
	if not code then
		code = luau.compile(fs.readFile(path))
		bytecode[path] = code
	end
	return code
end

-- ── the world ───────────────────────────────────────────────────────────────

export type Options = {
	Seed: number?,
	Studio: boolean?, -- RunService:IsStudio() (default true: MissionTest_* helpers work)
	DataStore: { [string]: any }?, -- shared table = persistence across boots; nil = API access denied
	Attributes: { [string]: any }?, -- Workspace attributes set before boot
	ServerOnly: { string }?, -- unused services to skip (none by default)
}

local serverCount = 0 -- each world is its own server, for session locks

function Engine.new(options: Options?): any
	local opts = options or {}
	local world: any = {
		Now = 0,
		BaseTime = 1700000000,
		Errors = {},
		Warnings = {},
		Log = {},
		Seed = opts.Seed or 1,
		StepSize = 0.1,
		Stats = { Rays = 0, Paths = 0, Tweens = 0, InstancesCreated = 0, FireClient = 0, Steps = 0 },
	}

	-- ── seeded randomness ───────────────────────────────────────────────────
	local randomCounter = 0
	local function newRandom(seed: number?): any
		randomCounter += 1
		local state = (seed or (world.Seed * 7919 + randomCounter * 104729)) % 2147483647
		if state <= 0 then
			state += 2147483646
		end
		local function nextFloat(): number
			state = (state * 48271) % 2147483647
			return (state - 1) / 2147483646
		end
		for _ = 1, 3 do
			nextFloat()
		end
		return {
			NextNumber = function(_, a: number?, b: number?): number
				local low, high = a or 0, b or 1
				return low + (high - low) * nextFloat()
			end,
			NextInteger = function(_, a: number, b: number): number
				if b < a then
					error("invalid argument #2 to 'NextInteger' (interval is empty)", 2)
				end
				return a + math.floor(nextFloat() * (b - a + 1))
			end,
		}
	end
	world.Rng = newRandom(world.Seed * 31 + 7)

	-- ── scheduler ───────────────────────────────────────────────────────────
	local timers: { { At: number, Seq: number, Thread: thread, Args: { any }, Cancelled: boolean? } } = {}
	local seq = 0
	local cancelled: { [thread]: boolean } = {}

	local function heapPush(item)
		table.insert(timers, item)
		local i = #timers
		while i > 1 do
			local parent = i // 2
			local a, b = timers[i], timers[parent]
			if a.At < b.At or (a.At == b.At and a.Seq < b.Seq) then
				timers[i], timers[parent] = b, a
				i = parent
			else
				break
			end
		end
	end
	local function heapPop()
		local top = timers[1]
		local last = table.remove(timers)
		if #timers > 0 then
			timers[1] = last
			local i, n = 1, #timers
			while true do
				local l, r, s = i * 2, i * 2 + 1, i
				local function less(x, y)
					return timers[x].At < timers[y].At
						or (timers[x].At == timers[y].At and timers[x].Seq < timers[y].Seq)
				end
				if l <= n and less(l, s) then
					s = l
				end
				if r <= n and less(r, s) then
					s = r
				end
				if s == i then
					break
				end
				timers[i], timers[s] = timers[s], timers[i]
				i = s
			end
		end
		return top
	end

	local function resume(thread: thread, ...)
		if cancelled[thread] or coroutine.status(thread) == "dead" then
			return
		end
		local ok, err = coroutine.resume(thread, ...)
		if not ok then
			table.insert(world.Errors, {
				At = world.Now,
				Message = tostring(err),
				Trace = debug.traceback(thread),
			})
		end
	end

	local function schedule(seconds: number, thread: thread, ...)
		seq += 1
		heapPush({ At = world.Now + math.max(seconds, 0), Seq = seq, Thread = thread, Args = { ... } })
	end

	local taskLib = {}
	function taskLib.spawn(fn: any, ...): thread
		local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
		resume(thread, ...)
		return thread
	end
	function taskLib.defer(fn: any, ...): thread
		local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
		schedule(0, thread, ...)
		return thread
	end
	function taskLib.delay(seconds: number?, fn: any, ...): thread
		local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
		schedule(seconds or 0, thread, ...)
		return thread
	end
	function taskLib.wait(seconds: number?): number
		local running = coroutine.running()
		local start = world.Now
		schedule(math.max(seconds or 0, world.StepSize * 0.5), running)
		coroutine.yield()
		return world.Now - start
	end
	function taskLib.cancel(thread: thread)
		cancelled[thread] = true
	end
	world.task = taskLib

	-- ── signals ─────────────────────────────────────────────────────────────
	local function newSignal(): any
		local signal: any = { _handlers = {} }
		function signal:Connect(handler)
			local entry = { Fn = handler, Connected = true }
			table.insert(self._handlers, entry)
			local connection = { Connected = true }
			function connection.Disconnect(c)
				entry.Connected = false
				c.Connected = false
			end
			return connection
		end
		function signal:Once(handler)
			local connection
			connection = self:Connect(function(...)
				connection:Disconnect()
				handler(...)
			end)
			return connection
		end
		function signal:Wait()
			local running = coroutine.running()
			self:Once(function(...)
				resume(running, ...)
			end)
			return coroutine.yield()
		end
		function signal:_fire(...)
			local handlers = self._handlers
			local anyDead = false
			for _, entry in table.clone(handlers) do
				if entry.Connected then
					resume(coroutine.create(entry.Fn), ...)
				else
					anyDead = true
				end
			end
			if anyDead then
				local live = {}
				for _, entry in handlers do
					if entry.Connected then
						table.insert(live, entry)
					end
				end
				self._handlers = live
			end
		end
		return signal
	end

	-- ── instances ───────────────────────────────────────────────────────────
	local Instance_ = {}
	local Methods: { [string]: any } = {}
	local Mt: any = {}
	local tagged: { [string]: { [any]: boolean } } = {}
	local tagAdded: { [string]: any } = {}
	local tagRemoved: { [string]: any } = {}
	local game: any

	local function isInstance(v: any): boolean
		return type(v) == "table" and getmetatable(v) == Mt
	end
	world.isInstance = isInstance

	local function markGeometry(inst: any)
		world.GeometryDirty = true
		world.GeometryVersion = (world.GeometryVersion or 0) + 1
		inst = inst
	end

	local function collidable(inst: any): boolean
		return inst._info.Super.BasePart and inst._p.Anchored == true and inst:_get("CanCollide") == true
	end

	local function isUnder(inst: any, ancestor: any): boolean
		local current = inst._parent
		while current do
			if current == ancestor then
				return true
			end
			current = current._parent
		end
		return false
	end

	local function get(self: any, key: string): any
		local value = self._p[key]
		if value ~= nil then
			return value
		end
		local info = self._info
		local default = info.Defaults[key]
		if default ~= nil then
			return default
		end
		for class, defaults in CLASS_DEFAULTS do
			if info.Super[class] and defaults[key] ~= nil then
				return defaults[key]
			end
		end
		local prop = info.Props[key]
		if prop then
			return DATATYPE_DEFAULTS[prop.Datatype]
		end
		return nil
	end

	local function signalOf(self: any, key: string): any
		local signal = self._signals[key]
		if not signal then
			signal = newSignal()
			self._signals[key] = signal
		end
		return signal
	end

	Mt.__index = function(self: any, key: any): any
		if key == "Parent" then
			return self._parent
		end
		if key == "Name" then
			return self._name
		end
		if key == "ClassName" then
			return self._class
		end
		if type(key) == "string" and key:sub(1, 1) == "_" then
			return rawget(Methods, key)
		end
		local method = Methods[key]
		if method then
			return method
		end
		if key == "Position" and self._info.Super.BasePart then
			return get(self, "CFrame").Position
		end
		if key == "WorldPosition" then
			local parent = self._parent
			return if parent and parent._info.Super.BasePart
				then (parent:_get("CFrame") * CFrame.new(get(self, "Position") or Vector3.zero)).Position
				else Vector3.zero
		end
		if key == "Orientation" then
			return Vector3.zero
		end
		if self._p[key] ~= nil then
			return self._p[key]
		end
		if EVENTS[key] then
			return signalOf(self, key)
		end
		local info = self._info
		if info.Props[key] or EXTRA_PROPS[key] then
			return get(self, key)
		end
		local child = self:FindFirstChild(key)
		if child then
			return child
		end
		error(string.format("%s is not a valid member of %s %q", tostring(key), self._class, self._name), 2)
	end

	Mt.__newindex = function(self: any, key: string, value: any)
		if key:sub(1, 1) == "_" then
			rawset(self, key, value) -- harness bookkeeping
			return
		end
		if key == "Parent" then
			self:_setParent(value)
			return
		end
		if key == "Name" then
			self._name = value
			return
		end
		local info = self._info
		if not (info.Props[key] or EXTRA_PROPS[key] or self._loose) then
			error(string.format("%s is not a valid member of %s %q", tostring(key), self._class, self._name), 2)
		end
		local prop = info.Props[key]
		if prop and prop.Scriptability == "Read" then
			error(string.format("Unable to assign property %s. Property is read only", key), 2)
		end
		if key == "Position" and info.Super.BasePart then
			key = "CFrame"
			value = get(self, "CFrame").Rotation + value
		end
		if key == "CFrame" and info.Super.BasePart then
			self:_setCFrame(value)
			return
		end
		local old = self._p[key]
		local wasSolid = info.Super.BasePart and collidable(self)
		self._p[key] = value
		if info.Super.BasePart and self._inWorld and (wasSolid or collidable(self)) then
			markGeometry(self)
		end
		if old ~= value then
			local changed = self._propSignals and self._propSignals[key]
			if changed then
				changed:_fire()
			end
			if key == "Health" and info.Super.Humanoid then
				if type(value) == "number" and value <= 0 and not self._died then
					self._died = true
					signalOf(self, "Died"):_fire()
				end
				signalOf(self, "HealthChanged"):_fire(value)
			end
			if key == "Parent" then
				return
			end
		end
	end

	Mt.__tostring = function(self: any)
		return self._name
	end

	local function create(className: string, loose: boolean?): any
		local info = classInfo(className)
		if not info.Exists and not loose then
			error('Unable to create an Instance of type "' .. tostring(className) .. '"', 2)
		end
		world.Stats.InstancesCreated += 1
		return setmetatable({
			_class = className,
			_name = className,
			_info = info,
			_p = {},
			_children = {},
			_attrs = {},
			_tags = {},
			_signals = {},
			_parent = nil,
			_loose = loose,
		}, Mt)
	end

	function Instance_.new(className: string, parent: any?): any
		local inst = create(className)
		if parent then
			inst.Parent = parent
		end
		return inst
	end
	world.Instance = Instance_

	function Methods._get(self: any, key: string): any
		return get(self, key)
	end

	function Methods._setCFrame(self: any, value: any)
		local old = self._p.CFrame or CFrame.new()
		local joints = self._joints
		-- Assemblies only exist in the Workspace: a rig being built elsewhere moves one part.
		if joints and self._inWorld then
			local delta = value * old:Inverse()
			local visited = { [self] = true }
			local function walk(part: any)
				for other in part._joints or {} do
					if not visited[other] then
						visited[other] = true
						other._p.CFrame = delta * (other._p.CFrame or CFrame.new())
						walk(other)
					end
				end
			end
			walk(self)
		end
		self._p.CFrame = value
		-- monsters and NPCs move every step: players walk through them, so paths stay good
		local group = self._p.CollisionGroup
		local ghost = group and world.NonColliding and world.NonColliding.Players and world.NonColliding.Players[group]
		if self._inWorld and not ghost and collidable(self) then
			markGeometry(self)
		end
	end

	local function setInWorld(inst: any, inWorld: boolean)
		inst._inWorld = inWorld
		if inst._info.Super.BasePart and collidable(inst) then
			markGeometry(inst)
		end
		for _, child in inst._children do
			setInWorld(child, inWorld)
		end
	end

	local function registerJoint(joint: any)
		local a, b = joint._p.Part0, joint._p.Part1
		if a and b and not joint._joined then
			joint._joined = true
			a._joints = a._joints or {}
			b._joints = b._joints or {}
			a._joints[b] = true
			b._joints[a] = true
		end
	end

	local function unregisterJoint(joint: any)
		local a, b = joint._p.Part0, joint._p.Part1
		if joint._joined and a and b then
			joint._joined = false
			if a._joints then
				a._joints[b] = nil
			end
			if b._joints then
				b._joints[a] = nil
			end
		end
	end

	function Methods._setParent(self: any, parent: any)
		if self._destroyed then
			error(
				"The Parent property of "
					.. self._name
					.. " is locked, current parent: NULL, new parent "
					.. tostring(parent),
				3
			)
		end
		if parent ~= nil and not isInstance(parent) then
			error("invalid Parent", 3)
		end
		local previous = self._parent
		if previous == parent then
			return
		end
		if previous then
			local list = previous._children
			local index = table.find(list, self)
			if index then
				table.remove(list, index)
			end
			if previous._signals.ChildRemoved then
				previous._signals.ChildRemoved:_fire(self)
			end
		end
		self._parent = parent
		if parent then
			table.insert(parent._children, self)
		end
		local inWorld = parent ~= nil and (parent == world.Workspace or parent._inWorld == true)
		if inWorld ~= (self._inWorld == true) then
			setInWorld(self, inWorld)
		end
		if self._info.Super.WeldConstraint or self._info.Super.JointInstance then
			if parent then
				registerJoint(self)
			else
				unregisterJoint(self)
			end
		end
		if parent then
			if parent._signals.ChildAdded then
				parent._signals.ChildAdded:_fire(self)
			end
			local up = parent
			while up do
				if up._signals.DescendantAdded then
					up._signals.DescendantAdded:_fire(self)
				end
				up = up._parent
			end
		end
		if self._signals.AncestryChanged then
			self._signals.AncestryChanged:_fire(self, parent)
		end
		for tag in self._tags do
			if parent and tagAdded[tag] then
				tagAdded[tag]:_fire(self)
			end
		end
	end

	function Methods.IsA(self: any, className: string): boolean
		return self._info.Super[className] == true or self._class == className
	end
	function Methods.GetChildren(self: any): { any }
		return table.clone(self._children)
	end
	local function collect(inst: any, into: { any })
		for _, child in inst._children do
			table.insert(into, child)
			collect(child, into)
		end
	end
	function Methods.GetDescendants(self: any): { any }
		local list = {}
		collect(self, list)
		return list
	end
	function Methods.FindFirstChild(self: any, name: string, recursive: boolean?): any
		for _, child in self._children do
			if child._name == name then
				return child
			end
		end
		if recursive then
			for _, child in self._children do
				local found = child:FindFirstChild(name, true)
				if found then
					return found
				end
			end
		end
		return nil
	end
	function Methods.FindFirstChildOfClass(self: any, className: string): any
		for _, child in self._children do
			if child._class == className then
				return child
			end
		end
		return nil
	end
	function Methods.FindFirstChildWhichIsA(self: any, className: string, recursive: boolean?): any
		for _, child in self._children do
			if child:IsA(className) then
				return child
			end
		end
		if recursive then
			for _, child in self._children do
				local found = child:FindFirstChildWhichIsA(className, true)
				if found then
					return found
				end
			end
		end
		return nil
	end
	function Methods.FindFirstAncestorWhichIsA(self: any, className: string): any
		local current = self._parent
		while current do
			if current:IsA(className) then
				return current
			end
			current = current._parent
		end
		return nil
	end
	function Methods.FindFirstAncestor(self: any, name: string): any
		local current = self._parent
		while current do
			if current._name == name then
				return current
			end
			current = current._parent
		end
		return nil
	end
	function Methods.IsDescendantOf(self: any, ancestor: any): boolean
		return isUnder(self, ancestor)
	end
	function Methods.WaitForChild(self: any, name: string, timeout: number?): any
		local deadline = world.Now + (timeout or 30)
		while true do
			local child = self:FindFirstChild(name)
			if child then
				return child
			end
			if world.Now >= deadline then
				return nil
			end
			taskLib.wait(0.1)
		end
	end
	function Methods.Destroy(self: any)
		if self._destroyed then
			return
		end
		if self._signals.Destroying then
			self._signals.Destroying:_fire(self)
		end
		for _, child in table.clone(self._children) do
			child:Destroy()
		end
		self:_setParent(nil)
		self._destroyed = true
		for tag in self._tags do
			local set = tagged[tag]
			if set then
				set[self] = nil
			end
			if tagRemoved[tag] then
				tagRemoved[tag]:_fire(self)
			end
		end
	end
	function Methods.ClearAllChildren(self: any)
		for _, child in table.clone(self._children) do
			child:Destroy()
		end
	end
	local function validateAttribute(name: string, value: any)
		if type(name) ~= "string" or #name > 100 or not name:match("^[%w_]+$") then
			error("Attribute name is invalid: " .. tostring(name), 3)
		end
		local t = realTypeof(value)
		local allowed = {
			["nil"] = true,
			string = true,
			boolean = true,
			number = true,
			UDim = true,
			UDim2 = true,
			BrickColor = true,
			Color3 = true,
			Vector2 = true,
			Vector3 = true,
			CFrame = true,
			NumberSequence = true,
			ColorSequence = true,
			NumberRange = true,
			Rect = true,
			Font = true,
		}
		if not allowed[t] then
			error(string.format("Attribute %s: type %s is not supported", name, t), 3)
		end
	end
	function Methods.SetAttribute(self: any, name: string, value: any)
		validateAttribute(name, value)
		local old = self._attrs[name]
		self._attrs[name] = value
		if old ~= value and self._attrSignals and self._attrSignals[name] then
			self._attrSignals[name]:_fire()
		end
	end
	function Methods.GetAttribute(self: any, name: string): any
		return self._attrs[name]
	end
	function Methods.GetAttributes(self: any): { [string]: any }
		return table.clone(self._attrs)
	end
	function Methods.GetAttributeChangedSignal(self: any, name: string): any
		self._attrSignals = self._attrSignals or {}
		local signal = self._attrSignals[name]
		if not signal then
			signal = newSignal()
			self._attrSignals[name] = signal
		end
		return signal
	end
	function Methods.GetPropertyChangedSignal(self: any, name: string): any
		self._propSignals = self._propSignals or {}
		local signal = self._propSignals[name]
		if not signal then
			signal = newSignal()
			self._propSignals[name] = signal
		end
		return signal
	end
	function Methods.AddTag(self: any, tag: string)
		world.CollectionService:AddTag(self, tag)
	end
	function Methods.RemoveTag(self: any, tag: string)
		world.CollectionService:RemoveTag(self, tag)
	end
	function Methods.HasTag(self: any, tag: string): boolean
		return self._tags[tag] == true
	end
	function Methods.GetTags(self: any): { string }
		local list = {}
		for tag in self._tags do
			table.insert(list, tag)
		end
		return list
	end
	function Methods.Clone(self: any): any
		local copy = create(self._class, self._loose)
		copy._name = self._name
		for key, value in self._p do
			copy._p[key] = value
		end
		for key, value in self._attrs do
			copy._attrs[key] = value
		end
		local map = { [self] = copy }
		local joints = {}
		local function cloneChildren(from: any, to: any)
			for _, child in from._children do
				local c = create(child._class, child._loose)
				c._name = child._name
				for key, value in child._p do
					c._p[key] = value
				end
				for key, value in child._attrs do
					c._attrs[key] = value
				end
				for tag in child._tags do
					world.CollectionService:AddTag(c, tag)
				end
				map[child] = c
				c._parent = to
				table.insert(to._children, c)
				if c._info.Super.WeldConstraint or c._info.Super.JointInstance then
					table.insert(joints, c)
				end
				cloneChildren(child, c)
			end
		end
		cloneChildren(self, copy)
		for original, c in map do
			for key, value in original._p do
				if isInstance(value) and map[value] then
					c._p[key] = map[value]
				end
			end
		end
		for _, joint in joints do
			registerJoint(joint)
		end
		return copy
	end

	-- BasePart / Model
	function Methods.GetPlayerFromCharacter(self: any, model: any): any
		for _, player in self._children do
			if player._p.Character == model then
				return player
			end
		end
		return nil
	end
	-- (only the Studio harness asks; nothing here checks overlaps)
	function Methods.GetPartBoundsInBox(_self: any, _cf: any, _size: any, _params: any): { any }
		return {}
	end
	function Methods.GetPivot(self: any): any
		if self:IsA("BasePart") then
			return get(self, "CFrame")
		end
		local primary = self._p.PrimaryPart
		if primary then
			return get(primary, "CFrame")
		end
		local origin, _ = self:GetBoundingBox()
		return origin
	end
	function Methods.PivotTo(self: any, target: any)
		if self:IsA("BasePart") then
			self:_setCFrame(target)
			return
		end
		local pivot = self:GetPivot()
		local delta = target * pivot:Inverse()
		for _, part in self:GetDescendants() do
			if part:IsA("BasePart") then
				local cf = delta * get(part, "CFrame")
				part._p.CFrame = cf
				if part._inWorld and collidable(part) then
					markGeometry(part)
				end
			end
		end
	end
	function Methods.GetBoundingBox(self: any): (any, any)
		local minP, maxP
		for _, part in self:GetDescendants() do
			if part:IsA("BasePart") then
				local p, s = get(part, "CFrame").Position, get(part, "Size")
				local low = p - s / 2
				local high = p + s / 2
				minP = if minP
					then Vector3.new(math.min(minP.X, low.X), math.min(minP.Y, low.Y), math.min(minP.Z, low.Z))
					else low
				maxP = if maxP
					then Vector3.new(math.max(maxP.X, high.X), math.max(maxP.Y, high.Y), math.max(maxP.Z, high.Z))
					else high
			end
		end
		if not minP then
			return CFrame.new(), Vector3.zero
		end
		return CFrame.new((minP + maxP) / 2), maxP - minP
	end
	function Methods.GetExtentsSize(self: any): any
		local _, size = self:GetBoundingBox()
		return size
	end
	function Methods.GetScale(_self: any): number
		return 1
	end
	function Methods.ScaleTo(_self: any, _scale: number) end
	function Methods.SetNetworkOwner(self: any, _owner: any)
		if self._p.Anchored then
			error("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts", 2)
		end
	end
	function Methods.GetNetworkOwner(_self: any): any
		return nil
	end
	function Methods.ApplyImpulse(_self: any, _impulse: any) end
	function Methods.Emit(_self: any, _count: number?) end

	-- Humanoid
	function Methods.TakeDamage(self: any, amount: number)
		if self:FindFirstChildOfClass("ForceField") then
			return
		end
		local character = self._parent
		if character and character:FindFirstChildOfClass("ForceField") then
			return
		end
		self.Health = math.max(0, get(self, "Health") - amount)
	end
	function Methods.MoveTo(self: any, target: any)
		self._moveTarget = target
		self._moveStarted = world.Now
		world.Movers[self] = true
	end
	function Methods.ChangeState(_self: any, _state: any) end
	function Methods.GetState(_self: any): any
		return Enum.HumanoidStateType.Running
	end
	function Methods.SetStateEnabled(_self: any, _state: any, _on: boolean) end
	function Methods.GetStateEnabled(_self: any, _state: any): boolean
		return true
	end
	function Methods.EquipTool(self: any, tool: any)
		tool.Parent = self._parent
	end
	function Methods.UnequipTools(_self: any) end
	function Methods.LoadAnimation(_self: any, _animation: any): any
		return { Play = function() end, Stop = function() end, Looped = false, IsPlaying = false }
	end

	-- Remotes
	local function checkSerializable(value: any, path: string)
		if type(value) == "function" or type(value) == "thread" then
			table.insert(
				world.Errors,
				{ At = world.Now, Message = "remote payload holds a " .. type(value) .. " at " .. path, Trace = "" }
			)
		elseif type(value) == "table" and not isInstance(value) then
			local numeric, strings = false, false
			for key, item in value do
				if type(key) == "number" then
					numeric = true
				else
					strings = true
				end
				checkSerializable(item, path .. "." .. tostring(key))
			end
			if numeric and strings then
				table.insert(
					world.Errors,
					{ At = world.Now, Message = "mixed table in remote payload at " .. path, Trace = "" }
				)
			end
		end
	end
	local function deliver(remote: any, player: any, ...)
		world.Stats.FireClient += 1
		for i = 1, select("#", ...) do
			checkSerializable((select(i, ...)), remote._name)
		end
		local inbox = player._inbox
		if inbox then
			local list = inbox[remote._name]
			if not list then
				list = {}
				inbox[remote._name] = list
			end
			table.insert(list, { At = world.Now, Args = { ... } })
			if #list > 400 then
				table.remove(list, 1)
			end
		end
	end
	function Methods.FireClient(self: any, player: any, ...)
		deliver(self, player, ...)
	end
	function Methods.FireAllClients(self: any, ...)
		for _, player in world.Players:GetPlayers() do
			deliver(self, player, ...)
		end
	end
	function Methods.FireServer(_self: any, ...)
		error("FireServer called on the server", 2)
	end

	-- Bindables-free client path: tests use this to act as a client.
	function world:clientFire(player: any, remoteName: string, ...)
		local remotes = world.ReplicatedStorage:FindFirstChild("Remotes")
		local remote = remotes:FindFirstChild(remoteName)
		assert(remote, "no remote " .. remoteName)
		signalOf(remote, "OnServerEvent"):_fire(player, ...)
	end

	-- ── geometry: spatial index, raycasts, walkability ──────────────────────
	local CELL = 16
	local index: { [number]: { any } } = {}
	local indexVersion = -1
	world.GeometryVersion = 0
	local function cellKey(ix: number, iz: number): number
		return (ix + 4096) * 8192 + (iz + 4096)
	end
	local function rebuildIndex()
		if indexVersion == world.GeometryVersion then
			return
		end
		indexVersion = world.GeometryVersion
		index = {}
		world.ColumnCache = {}
		world.PathCache = {}
		local function visit(inst: any)
			for _, child in inst._children do
				if child._info.Super.BasePart and collidable(child) then
					local cf, size = get(child, "CFrame"), get(child, "Size")
					local p, rx, ux, bx = cf.Position, cf.XVector, cf.YVector, cf.ZVector
					local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
					local ex = math.abs(rx.X) * hx + math.abs(ux.X) * hy + math.abs(bx.X) * hz
					local ey = math.abs(rx.Y) * hx + math.abs(ux.Y) * hy + math.abs(bx.Y) * hz
					local ez = math.abs(rx.Z) * hx + math.abs(ux.Z) * hy + math.abs(bx.Z) * hz
					local entry = {
						Part = child,
						X = p.X,
						Y = p.Y,
						Z = p.Z,
						RX = rx.X,
						RY = rx.Y,
						RZ = rx.Z,
						UX = ux.X,
						UY = ux.Y,
						UZ = ux.Z,
						BX = bx.X,
						BY = bx.Y,
						BZ = bx.Z,
						HX = hx,
						HY = hy,
						HZ = hz,
						MinX = p.X - ex,
						MaxX = p.X + ex,
						MinY = p.Y - ey,
						MaxY = p.Y + ey,
						MinZ = p.Z - ez,
						MaxZ = p.Z + ez,
						Group = get(child, "CollisionGroup"),
					}
					for ix = math.floor(entry.MinX / CELL), math.floor(entry.MaxX / CELL) do
						for iz = math.floor(entry.MinZ / CELL), math.floor(entry.MaxZ / CELL) do
							local key = cellKey(ix, iz)
							local list = index[key]
							if not list then
								list = {}
								index[key] = list
							end
							table.insert(list, entry)
						end
					end
				end
				visit(child)
			end
		end
		visit(world.Workspace)
	end

	-- Slab test of a segment (origin + t * dir, t in 0..1) against an oriented box: (tIn, tOut).
	local function slab(
		e: any,
		ox: number,
		oy: number,
		oz: number,
		dx: number,
		dy: number,
		dz: number
	): (number?, number?)
		local rx, ry, rz = ox - e.X, oy - e.Y, oz - e.Z
		local tMin, tMax = -math.huge, math.huge
		for axis = 1, 3 do
			local ax, ay, az, h
			if axis == 1 then
				ax, ay, az, h = e.RX, e.RY, e.RZ, e.HX
			elseif axis == 2 then
				ax, ay, az, h = e.UX, e.UY, e.UZ, e.HY
			else
				ax, ay, az, h = e.BX, e.BY, e.BZ, e.HZ
			end
			local o = rx * ax + ry * ay + rz * az
			local d = dx * ax + dy * ay + dz * az
			if math.abs(d) < 1e-7 then
				if o < -h or o > h then
					return nil, nil
				end
			else
				local t1, t2 = (-h - o) / d, (h - o) / d
				if t1 > t2 then
					t1, t2 = t2, t1
				end
				if t1 > tMin then
					tMin = t1
				end
				if t2 < tMax then
					tMax = t2
				end
				if tMin > tMax then
					return nil, nil
				end
			end
		end
		return tMin, tMax
	end

	local nonCollidingGroups: { [string]: { [string]: boolean } } = {}
	world.NonColliding = nonCollidingGroups

	function world:raycast(origin: any, direction: any, params: any?): any
		world.Stats.Rays += 1
		rebuildIndex()
		local ox, oy, oz = origin.X, origin.Y, origin.Z
		local dx, dy, dz = direction.X, direction.Y, direction.Z
		local exclude: { [any]: boolean }? = nil
		local group = nil
		if params then
			group = params.CollisionGroup
			if params.FilterDescendantsInstances and #params.FilterDescendantsInstances > 0 then
				exclude = {}
				for _, inst in params.FilterDescendantsInstances do
					exclude[inst] = true
				end
			end
		end
		local best, bestT = nil, math.huge
		local seen = {}
		local length = math.sqrt(dx * dx + dz * dz)
		local steps = math.max(1, math.ceil(length / (CELL * 0.5)))
		for i = 0, steps do
			local t = i / steps
			local ix = math.floor((ox + dx * t) / CELL)
			local iz = math.floor((oz + dz * t) / CELL)
			for gx = ix - 1, ix + 1 do
				for gz = iz - 1, iz + 1 do
					local list = index[cellKey(gx, gz)]
					if list then
						for _, e in list do
							if not seen[e] then
								seen[e] = true
								local skip = group and nonCollidingGroups[group] and nonCollidingGroups[group][e.Group]
								if not skip then
									local tIn, tOut = slab(e, ox, oy, oz, dx, dy, dz)
									if tIn and tOut and tOut >= 0 and tIn <= 1 then
										local at = math.max(tIn, 0)
										if at < bestT then
											local excluded = false
											if exclude then
												local up = e.Part
												while up do
													if exclude[up] then
														excluded = true
														break
													end
													up = up._parent
												end
											end
											if not excluded then
												best, bestT = e, at
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
		if not best then
			return nil
		end
		return {
			Instance = best.Part,
			Position = origin + direction * bestT,
			Distance = direction.Magnitude * bestT,
			Normal = Vector3.yAxis,
			Material = Enum.Material.Plastic,
		}
	end

	-- Occupied vertical intervals { low, high } of the column at x, z (sorted high to low).
	world.ColumnCache = {}
	local function column(x: number, z: number): { { number } }
		rebuildIndex()
		local key = math.floor(x + 2048) * 4096 + math.floor(z + 2048)
		local cached = world.ColumnCache[key]
		if cached then
			return cached
		end
		local list = {}
		local entries = index[cellKey(math.floor(x / CELL), math.floor(z / CELL))]
		if entries then
			for _, e in entries do
				-- players walk through whatever their collision group ignores (enemies, NPCs)
				local ghost = nonCollidingGroups.Players and nonCollidingGroups.Players[e.Group]
				if not ghost and x >= e.MinX and x <= e.MaxX and z >= e.MinZ and z <= e.MaxZ then
					local tIn, tOut = slab(e, x, 400, z, 0, -800, 0)
					if tIn and tOut then
						table.insert(list, { 400 - 800 * tOut, 400 - 800 * tIn })
					end
				end
			end
		end
		table.sort(list, function(a, b)
			return a[2] > b[2]
		end)
		world.ColumnCache[key] = list
		return list
	end

	local STEP_UP = 2.2 -- a character walks over ledges this high
	local HEADROOM = 5 -- and fits under anything this high
	local RADIUS = 0.9 -- half-width of the walking footprint (a character just fits a 2-stud gap)

	-- The floor height someone at height `fromY` would stand on at x, z (nil = a pit).
	local function standY(x: number, z: number, fromY: number): number?
		for _, interval in column(x, z) do
			if interval[2] <= fromY + STEP_UP then
				return interval[2]
			end
		end
		return nil
	end
	world.standY = standY
	world.column = column

	local function blockedAt(x: number, z: number, floor: number, low: number): boolean
		for _, interval in column(x, z) do
			if interval[1] < floor + HEADROOM and interval[2] > floor + low then
				return true
			end
		end
		return false
	end

	local function standable(x: number, z: number, floor: number): boolean
		if blockedAt(x, z, floor, 0.05) then
			return false
		end
		for _, d in { { RADIUS, RADIUS }, { -RADIUS, RADIUS }, { RADIUS, -RADIUS }, { -RADIUS, -RADIUS } } do
			if blockedAt(x + d[1], z + d[2], floor, STEP_UP - 0.3) then
				return false
			end
		end
		return true
	end
	world.standable = standable

	-- A* over a 2-stud grid on the real geometry. `reach`: stop within this flat distance of the
	-- goal (and 12 studs of height). Returns waypoints (floor points) or nil.
	world.PathCache = {}
	world.PathFailures = {}
	local GRID = 2
	local NEIGHBOURS = {
		{ 1, 0, 1 },
		{ -1, 0, 1 },
		{ 0, 1, 1 },
		{ 0, -1, 1 },
		{ 1, 1, 1.414 },
		{ 1, -1, 1.414 },
		{ -1, 1, 1.414 },
		{ -1, -1, 1.414 },
	}
	function world:findPath(from: any, to: any, reach: number?): { any }?
		return world:findPathWithin(from, to, reach, nil)
	end

	function world:findPathWithin(from: any, to: any, reach: number?, within: number?): { any }?
		rebuildIndex()
		world.Stats.Paths += 1
		local r = reach or 2
		local fx, fz = math.round(from.X / GRID), math.round(from.Z / GRID)
		local startFloor = standY(from.X, from.Z, from.Y + 1)
		if not startFloor then
			return nil
		end
		local cacheKey = table.concat(
			{ fx, fz, math.round(startFloor), math.round(to.X), math.round(to.Y), math.round(to.Z), r, within or 0 },
			","
		)
		local cached = world.PathCache[cacheKey]
		if cached ~= nil then
			return if cached == false then nil else cached
		end
		-- a search that found nothing is the expensive kind: don't repeat it from next door
		local coarseKey = table.concat({
			fx // 4,
			fz // 4,
			math.round(startFloor),
			math.round(to.X / 8),
			math.round(to.Y / 8),
			math.round(to.Z / 8),
			r,
			within or 0,
		}, ",")
		if world.PathCache[coarseKey] == false then
			return nil
		end
		local gx, gy, gz = to.X, to.Y, to.Z
		local function nodeKey(ix, iz, y)
			return ((ix + 2048) * 4096 + (iz + 2048)) * 512 + (math.floor(y / 3) + 100)
		end
		local openHeap: { any } = {}
		local function push(item)
			table.insert(openHeap, item)
			local i = #openHeap
			while i > 1 do
				local p = i // 2
				if openHeap[i].F < openHeap[p].F then
					openHeap[i], openHeap[p] = openHeap[p], openHeap[i]
					i = p
				else
					break
				end
			end
		end
		local function pop()
			local top = openHeap[1]
			local last = table.remove(openHeap)
			if #openHeap > 0 then
				openHeap[1] = last
				local i, n = 1, #openHeap
				while true do
					local l, rr, s = i * 2, i * 2 + 1, i
					if l <= n and openHeap[l].F < openHeap[s].F then
						s = l
					end
					if rr <= n and openHeap[rr].F < openHeap[s].F then
						s = rr
					end
					if s == i then
						break
					end
					openHeap[i], openHeap[s] = openHeap[s], openHeap[i]
					i = s
				end
			end
			return top
		end
		local function h(x, z, y)
			return math.sqrt((x - gx) ^ 2 + (z - gz) ^ 2) + math.abs(y - gy) * 0.5
		end
		local best: { [number]: number } = {}
		local startX, startZ = fx * GRID, fz * GRID
		local first = {
			X = startX,
			Z = startZ,
			IX = fx,
			IZ = fz,
			Y = startFloor,
			G = 0,
			F = h(startX, startZ, startFloor),
			Prev = nil,
		}
		best[nodeKey(fx, fz, startFloor)] = 0
		push(first)
		local expansions = 0
		local goal = nil
		while #openHeap > 0 and expansions < (world.PathLimit or world.DefaultPathLimit or 60000) do
			local node = pop()
			expansions += 1
			local arrived
			if within then
				arrived = math.sqrt((node.X - gx) ^ 2 + (node.Z - gz) ^ 2 + (node.Y + 3 - gy) ^ 2) <= within
			else
				arrived = math.sqrt((node.X - gx) ^ 2 + (node.Z - gz) ^ 2) <= r and math.abs(node.Y - gy) <= 12
			end
			if arrived then
				goal = node
				break
			end
			for _, d in NEIGHBOURS do
				local ix, iz = node.IX + d[1], node.IZ + d[2]
				local x, z = ix * GRID, iz * GRID
				local y = standY(x, z, node.Y)
				if y and y > -80 and standable(x, z, y) then
					local diagonalOk = true
					if d[1] ~= 0 and d[2] ~= 0 then
						local ax, az = (node.IX + d[1]) * GRID, node.IZ * GRID
						local bx, bz = node.IX * GRID, (node.IZ + d[2]) * GRID
						local ay, by = standY(ax, az, node.Y), standY(bx, bz, node.Y)
						diagonalOk = ay ~= nil and by ~= nil and standable(ax, az, ay) and standable(bx, bz, by)
					end
					if diagonalOk then
						local g = node.G + d[3] * GRID
						local key = nodeKey(ix, iz, y)
						if not best[key] or g < best[key] then
							best[key] = g
							push({
								X = x,
								Z = z,
								IX = ix,
								IZ = iz,
								Y = y,
								G = g,
								F = g + h(x, z, y) * 1.15,
								Prev = node,
							})
						end
					end
				end
			end
		end
		if not goal then
			world.PathCache[cacheKey] = false
			world.PathCache[coarseKey] = false
			table.insert(world.PathFailures, { At = world.Now, From = from, To = to, Expansions = expansions })
			return nil
		end
		local path = {}
		local node = goal
		while node do
			table.insert(path, 1, Vector3.new(node.X, node.Y, node.Z))
			node = node.Prev
		end
		-- thin the straight runs (cheaper to walk and to store)
		local thin = { path[1] }
		for i = 2, #path - 1 do
			if i % 2 == 0 then
				table.insert(thin, path[i])
			end
		end
		if #path > 1 then
			table.insert(thin, path[#path])
		end
		world.PathCache[cacheKey] = thin
		return thin
	end

	-- ── services ────────────────────────────────────────────────────────────
	game = create("DataModel", true)
	game._name = "Game"
	serverCount += 1
	game._p.JobId = "sim-job-" .. serverCount
	game._p.PlaceId = 1
	world.Game = game
	local function service(className: string): any
		local s = create(className, true)
		s._name = className
		s._parent = game
		table.insert(game._children, s)
		return s
	end
	local Workspace = service("Workspace")
	Workspace._inWorld = true
	world.Workspace = Workspace
	world.Movers = {}
	function Methods.Raycast(_self: any, origin: any, direction: any, params: any?): any
		return world:raycast(origin, direction, params)
	end
	function Methods.GetServerTimeNow(_self: any): number
		return world.BaseTime + world.Now
	end
	local ReplicatedStorage = service("ReplicatedStorage")
	world.ReplicatedStorage = ReplicatedStorage
	local ServerStorage = service("ServerStorage")
	local ServerScriptService = service("ServerScriptService")
	local StarterPack = service("StarterPack")
	world.StarterPack = StarterPack
	service("StarterPlayer")
	local Lighting = service("Lighting")
	function Methods.GetSunDirection(_self: any): any
		return Vector3.new(0.3, 0.8, 0.2).Unit
	end
	local PlayersService = service("Players")
	world.Players = PlayersService
	function Methods.GetPlayers(self: any): { any }
		return self:GetChildren()
	end
	function Methods.GetPlayerByUserId(self: any, id: number): any
		for _, player in self._children do
			if player._p.UserId == id then
				return player
			end
		end
		return nil
	end
	local function rigModel(): any
		local model = create("Model")
		local root = create("Part")
		root._name = "HumanoidRootPart"
		root._p.Size = Vector3.new(2, 2, 1)
		root._p.CanCollide = true
		root._p.Transparency = 1
		root.Parent = model
		model._p.PrimaryPart = root
		for name, offset in { Head = 1.5, UpperTorso = 0.5, LowerTorso = -0.5 } do
			local part = create("Part")
			part._name = name
			part._p.Size = Vector3.new(2, 1, 1)
			part._p.CFrame = CFrame.new(0, offset, 0)
			part.Parent = model
			local joint = create("Motor6D")
			joint._name = name .. "Joint"
			joint._p.Part0 = root
			joint._p.Part1 = part
			joint.Parent = root
		end
		local humanoid = create("Humanoid")
		humanoid.Parent = model
		local animator = create("Animator")
		animator.Parent = humanoid
		return model
	end
	function Methods.CreateHumanoidModelFromDescription(_self: any, _description: any, _rig: any): any
		return rigModel()
	end
	local RunServiceInst = service("RunService")
	local studio = opts.Studio ~= false
	function Methods.IsStudio(_self: any): boolean
		return studio
	end
	function Methods.IsServer(_self: any): boolean
		return true
	end
	function Methods.IsClient(_self: any): boolean
		return false
	end
	function Methods.IsRunning(_self: any): boolean
		return true
	end
	local CollectionServiceInst = service("CollectionService")
	world.CollectionService = CollectionServiceInst
	local function tagSignal(map: any, tag: string): any
		if not map[tag] then
			map[tag] = newSignal()
		end
		return map[tag]
	end
	function Methods.AddTag(self: any, a: any, b: any)
		local inst, tag = if b ~= nil then a else self, if b ~= nil then b else a
		if inst._tags[tag] then
			return
		end
		inst._tags[tag] = true
		tagged[tag] = tagged[tag] or {}
		tagged[tag][inst] = true
		if tagAdded[tag] and (inst._parent or inst == game) then
			tagAdded[tag]:_fire(inst)
		end
	end
	function Methods.RemoveTag(self: any, a: any, b: any)
		local inst, tag = if b ~= nil then a else self, if b ~= nil then b else a
		if not inst._tags[tag] then
			return
		end
		inst._tags[tag] = nil
		if tagged[tag] then
			tagged[tag][inst] = nil
		end
		if tagRemoved[tag] then
			tagRemoved[tag]:_fire(inst)
		end
	end
	function Methods.HasTag(self: any, a: any, b: any): boolean
		local inst, tag = if b ~= nil then a else self, if b ~= nil then b else a
		return inst._tags[tag] == true
	end
	function Methods.GetTagged(_self: any, tag: string): { any }
		local list = {}
		for inst in tagged[tag] or {} do
			if inst._parent and isUnder(inst, game) then
				table.insert(list, inst)
			end
		end
		table.sort(list, function(a, b)
			return tostring(a._p.CFrame and a._p.CFrame.Position or a._name)
				< tostring(b._p.CFrame and b._p.CFrame.Position or b._name)
		end)
		return list
	end
	function Methods.GetInstanceAddedSignal(_self: any, tag: string): any
		return tagSignal(tagAdded, tag)
	end
	function Methods.GetInstanceRemovedSignal(_self: any, tag: string): any
		return tagSignal(tagRemoved, tag)
	end
	-- TweenService: the end state lands when the tween ends (no in-between values).
	local TweenServiceInst = service("TweenService")
	local activeTweens: { [any]: { [string]: any } } = {}
	function Methods.Create(_self: any, inst: any, info: any, goals: any): any
		if not isInstance(inst) then
			error("Unable to cast value to Object", 2)
		end
		for key in goals do
			if not (inst._info.Props[key] or EXTRA_PROPS[key]) then
				error(string.format("TweenService:Create property named '%s' cannot be tweened", key), 2)
			end
		end
		world.Stats.Tweens += 1
		local tween: any = { Completed = newSignal(), PlaybackState = "Begin" }
		function tween:Play()
			self._token = {}
			local token = self._token
			activeTweens[inst] = activeTweens[inst] or {}
			for key in goals do
				activeTweens[inst][key] = tween
			end
			if info.RepeatCount and info.RepeatCount ~= 0 then
				return -- looping tweens are cosmetic pulses: never settle
			end
			taskLib.delay(info.Time or 1, function()
				if self._token ~= token then
					return
				end
				if inst._destroyed then
					return
				end
				for key, value in goals do
					if activeTweens[inst] and activeTweens[inst][key] == tween then
						inst[key] = value
					end
				end
				tween.Completed:_fire(Enum.PlaybackState.Completed)
			end)
		end
		function tween:Cancel()
			self._token = nil
		end
		function tween:Pause()
			self._token = nil
		end
		function tween:Destroy()
			self._token = nil
		end
		return tween
	end
	service("HttpService")
	function Methods.JSONEncode(_self: any, value: any): string
		return serde.encode("json", value)
	end
	function Methods.JSONDecode(_self: any, value: string): any
		return serde.decode("json", value)
	end
	local guid = 0
	function Methods.GenerateGUID(_self: any, _braces: boolean?): string
		guid += 1
		return string.format("GUID-%d-%d", world.Seed, guid)
	end
	service("PhysicsService")
	local registered = {}
	function Methods.RegisterCollisionGroup(_self: any, name: string)
		registered[name] = true
	end
	function Methods.CollisionGroupSetCollidable(_self: any, a: string, b: string, on: boolean)
		nonCollidingGroups[a] = nonCollidingGroups[a] or {}
		nonCollidingGroups[b] = nonCollidingGroups[b] or {}
		nonCollidingGroups[a][b] = not on or nil
		nonCollidingGroups[b][a] = not on or nil
	end
	service("PathfindingService")
	function Methods.CreatePath(_self: any, _params: any): any
		local path: any = { Status = Enum.PathStatus.NoPath, _points = {} }
		function path:ComputeAsync(from: any, to: any)
			world.Stats.Computes = (world.Stats.Computes or 0) + 1
			-- a goal that nothing could reach (the fountain, when everyone's dead) stays that way
			-- until the world changes: monsters ask about it often, and A* can't say no quickly
			if world.UnreachableGoalsAt ~= world.GeometryVersion then
				world.UnreachableGoalsAt = world.GeometryVersion
				world.UnreachableGoals = {}
			end
			local goalKey = string.format("%d,%d,%d", to.X // 4, to.Y // 4, to.Z // 4)
			local points = nil
			if not world.UnreachableGoals[goalKey] then
				world.PathLimit = 20000
				points = world:findPath(from, to, 2.5)
				world.PathLimit = nil
				if not points then
					world.UnreachableGoals[goalKey] = true
				end
			end
			self.Status = if points then Enum.PathStatus.Success else Enum.PathStatus.NoPath
			self._points = points or {}
		end
		function path:GetWaypoints(): { any }
			local list = {}
			for _, p in self._points do
				table.insert(list, { Position = p, Action = Enum.PathWaypointAction.Walk })
			end
			return list
		end
		return path
	end

	-- DataStores: opts.DataStore = nil behaves like Studio without API access.
	service("DataStoreService")
	world.StoreFailures = { Read = 0, Write = 0 }
	world.StoreCalls = { Update = 0, Get = 0 }
	local function checkStorable(value: any, path: string)
		local t = type(value)
		if t == "table" then
			if isInstance(value) then
				error("Cannot store Instance in data store at " .. path)
			end
			local n, count, strings = #value, 0, false
			for key, item in value do
				count += 1
				if type(key) == "string" then
					strings = true
				elseif type(key) ~= "number" then
					error("Cannot store key of type " .. type(key) .. " in data store at " .. path)
				end
				checkStorable(item, path .. "." .. tostring(key))
			end
			if strings and n > 0 then
				error("Cannot store mixed tables in data store at " .. path)
			end
			if not strings and count ~= n then
				error("Cannot store sparse arrays in data store at " .. path)
			end
		elseif t == "number" then
			if value ~= value or value == math.huge or value == -math.huge then
				error("Cannot store NaN or infinity in data store at " .. path)
			end
		elseif t ~= "string" and t ~= "boolean" and t ~= "nil" then
			error("Cannot store " .. realTypeof(value) .. " in data store at " .. path)
		end
	end
	function Methods.GetDataStore(_self: any, name: string): any
		local backing = opts.DataStore
		if not backing then
			error("StudioAccessToApisNotAllowed")
		end
		backing[name] = backing[name] or {}
		local records = backing[name]
		local store = {}
		function store.GetAsync(_s, key: string)
			world.StoreCalls.Get += 1
			if world.StoreFailures.Read > 0 then
				world.StoreFailures.Read -= 1
				error("DataStore request failed (simulated read)")
			end
			local raw = records[key]
			return if raw then serde.decode("json", raw) else nil
		end
		function store.UpdateAsync(_s, key: string, transform: any)
			world.StoreCalls.Update += 1
			if world.StoreFailures.Write > 0 then
				world.StoreFailures.Write -= 1
				error("DataStore request failed (simulated write)")
			end
			local raw = records[key]
			local result = transform(if raw then serde.decode("json", raw) else nil)
			if result ~= nil then
				checkStorable(result, key)
				records[key] = serde.encode("json", result)
			end
			return result
		end
		return store
	end
	local MarketplaceServiceInst = service("MarketplaceService")
	world.MarketplaceService = MarketplaceServiceInst
	world.Prompted = {}
	function Methods.PromptProductPurchase(_self: any, player: any, id: number)
		table.insert(world.Prompted, { Kind = "Product", Player = player, Id = id })
	end
	function Methods.PromptGamePassPurchase(_self: any, player: any, id: number)
		table.insert(world.Prompted, { Kind = "Pass", Player = player, Id = id })
	end
	function Methods.UserOwnsGamePassAsync(_self: any, _userId: number, _id: number): boolean
		return false
	end
	function Methods.GetProductInfo(_self: any, _id: number, _kind: any): any
		return { Name = "Test", PriceInRobux = 1 }
	end
	world.CloseHandlers = {}
	function Methods.BindToClose(_self: any, handler: any)
		table.insert(world.CloseHandlers, handler)
	end
	function Methods.GetService(self: any, name: string): any
		local found = self:FindFirstChild(name)
		if not found then
			error("'" .. name .. "' is not a valid Service name", 2)
		end
		return found
	end
	function Methods.Kick(self: any, message: string?)
		self._kicked = message or ""
		world:removePlayer(self)
	end

	-- ── environment and module loading ──────────────────────────────────────
	local mathLib = table.clone(math)
	local mathRandom = newRandom(world.Seed * 13 + 3)
	function mathLib.random(a: number?, b: number?): number
		if a == nil then
			return mathRandom:NextNumber()
		elseif b == nil then
			return mathRandom:NextInteger(1, a)
		end
		return mathRandom:NextInteger(a, b :: number)
	end
	local osLib = table.clone(os)
	function osLib.clock(): number
		return world.Now
	end
	function osLib.time(_t: any?): number
		return world.BaseTime + math.floor(world.Now)
	end
	local env: { [string]: any } = {
		Vector3 = Vector3,
		Vector2 = roblox.Vector2,
		CFrame = CFrame,
		Color3 = roblox.Color3,
		BrickColor = roblox.BrickColor,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = Enum,
		Font = roblox.Font,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Rect = roblox.Rect,
		Ray = roblox.Ray,
		Region3 = roblox.Region3,
		PhysicalProperties = roblox.PhysicalProperties,
		Instance = Instance_,
		Random = {
			new = function(seed: number?)
				return newRandom(seed)
			end,
		},
		TweenInfo = {
			new = function(
				time: number?,
				style: any?,
				direction: any?,
				repeatCount: number?,
				reverses: boolean?,
				delayTime: number?
			)
				return {
					Time = time or 1,
					EasingStyle = style,
					EasingDirection = direction,
					RepeatCount = repeatCount or 0,
					Reverses = reverses,
					DelayTime = delayTime or 0,
				}
			end,
		},
		OverlapParams = {
			new = function(): any
				return { RespectCanCollide = false }
			end,
		},
		RaycastParams = {
			new = function()
				return {
					FilterType = Enum.RaycastFilterType.Exclude,
					FilterDescendantsInstances = {},
					RespectCanCollide = false,
					IgnoreWater = false,
					CollisionGroup = "Default",
				}
			end,
		},
		game = game,
		workspace = Workspace,
		task = taskLib,
		wait = taskLib.wait,
		math = mathLib,
		os = osLib,
		print = function(...)
			table.insert(world.Log, { ... })
		end,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring((select(i, ...))))
			end
			table.insert(world.Warnings, { At = world.Now, Message = table.concat(parts, " ") })
		end,
		typeof = function(value: any): string
			if isInstance(value) then
				return "Instance"
			end
			return realTypeof(value)
		end,
		type = type,
		tostring = tostring,
		tonumber = tonumber,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		select = select,
		pcall = pcall,
		xpcall = xpcall,
		error = error,
		assert = assert,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		unpack = table.unpack,
		string = string,
		table = table,
		coroutine = coroutine,
		bit32 = bit32,
		utf8 = utf8,
		debug = debug,
	}

	local moduleCache: { [any]: any } = {}
	local loading: { [any]: boolean } = {}
	local function loadScript(node: any): (...any) -> ...any
		local source = node._source
		local moduleEnv = table.clone(env)
		moduleEnv.script = node
		return luau.load(compiled(source), { debugName = source, environment = moduleEnv, injectGlobals = false })
	end
	env.require = function(node: any): any
		if not isInstance(node) or not node._source then
			error("Attempted to call require with invalid argument(s).", 2)
		end
		if moduleCache[node] ~= nil then
			return moduleCache[node]
		end
		if loading[node] then
			error("Requested module was required recursively: " .. node._name, 2)
		end
		loading[node] = true
		local result = loadScript(node)()
		loading[node] = nil
		moduleCache[node] = result
		return result
	end

	local function mount(path: string, parent: any, name: string): any
		local info = fs.isDir(path)
		if not info then
			local node = create("ModuleScript")
			node._name = name
			node._source = path
			compiled(path) -- now, on the main thread: file reads yield
			node._parent = parent
			table.insert(parent._children, node)
			return node
		end
		local folder = create("Folder")
		folder._name = name
		folder._parent = parent
		table.insert(parent._children, folder)
		local entries = fs.readDir(path)
		table.sort(entries)
		for _, entry in entries do
			local full = path .. "/" .. entry
			if fs.isDir(full) then
				mount(full, folder, entry)
			elseif entry:match("%.luau$") and not entry:match("^init%.") then
				mount(full, folder, (entry:gsub("%.luau$", "")))
			end
		end
		return folder
	end

	local root = process.cwd
	root = if root:sub(-1) == "/" then root else root .. "/"
	local shared = mount(root .. "src/shared", ReplicatedStorage, "Shared")
	shared = shared
	local server = mount(root .. "src/server", ServerScriptService, "Server")
	server._source = root .. "src/server/init.server.luau"
	compiled(server._source)
	local assets = create("Folder")
	assets._name = "Assets"
	assets.Parent = ServerStorage
	world.ServerRoot = server

	-- Runs a script file in this world's environment (the Studio harness's smoke test).
	function world:runFile(path: string)
		local node = create("ModuleScript")
		node._name = path:match("[^/]+$")
		node._source = path
		compiled(path)
		node._parent = server
		table.insert(server._children, node)
		resume(coroutine.create(loadScript(node)))
	end

	function world:require(path: string): any
		-- e.g. "Services.MissionService" or "Levels.ChefLogic" (server) or "Shared.Config.X"
		local node: any = if path:sub(1, 7) == "Shared." then ReplicatedStorage else server
		for part in path:gmatch("[^.]+") do
			node = node:FindFirstChild(part)
			assert(node, "no module " .. path)
		end
		return env.require(node)
	end

	-- Lets Lighting exist as a referenced upvalue without lint noise.
	world.Lighting = Lighting
	world.RunService = RunServiceInst
	world.TweenService = TweenServiceInst

	for name, value in opts.Attributes or {} do
		Workspace:SetAttribute(name, value)
	end

	-- ── players and characters ──────────────────────────────────────────────
	local nextUserId = 1000
	local function spawnCharacter(player: any)
		if player._parent ~= PlayersService then
			return
		end
		local old = player._p.Character
		if old then
			signalOf(player, "CharacterRemoving"):_fire(old)
			old:Destroy()
		end
		local character = rigModel()
		character._name = player._name
		local spawnPart = Workspace:FindFirstChild("PlayerSpawn", true)
		local at = if spawnPart then get(spawnPart, "CFrame").Position else Vector3.new(0, 1, 0)
		character:PivotTo(CFrame.new(at + Vector3.new(0, 3, 0)))
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			backpack:ClearAllChildren()
			for _, tool in StarterPack:GetChildren() do
				tool:Clone().Parent = backpack
			end
		end
		player._p.Character = character
		character.Parent = Workspace
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		signalOf(humanoid, "Died"):Connect(function()
			taskLib.delay(world.RespawnTime or 5, function()
				if player._parent == PlayersService and player._p.Character == character then
					spawnCharacter(player)
				end
			end)
		end)
		signalOf(player, "CharacterAdded"):_fire(character)
	end
	world.spawnCharacter = spawnCharacter

	function world:addPlayer(name: string?, userId: number?): any
		nextUserId += 1
		local player = create("Player", true)
		player._name = name or ("Player" .. nextUserId)
		player._p.UserId = userId or nextUserId
		player._p.DisplayName = player._name
		player._inbox = {}
		local backpack = create("Backpack")
		backpack.Parent = player
		local gui = create("PlayerGui")
		gui.Parent = player
		player.Parent = PlayersService
		signalOf(PlayersService, "PlayerAdded"):_fire(player)
		taskLib.spawn(function()
			taskLib.wait(0.2)
			spawnCharacter(player)
		end)
		return player
	end

	function world:removePlayer(player: any)
		if player._parent ~= PlayersService then
			return
		end
		signalOf(PlayersService, "PlayerRemoving"):_fire(player)
		local character = player._p.Character
		if character then
			signalOf(player, "CharacterRemoving"):_fire(character)
			character:Destroy()
			player._p.Character = nil
		end
		player:_setParent(nil)
	end

	-- ── stepping ────────────────────────────────────────────────────────────
	local function moveHumanoids(dt: number)
		for humanoid in world.Movers do
			local target = humanoid._moveTarget
			local model = humanoid._parent
			if not target or not model or humanoid._destroyed then
				world.Movers[humanoid] = nil
				continue
			end
			local root = model:FindFirstChild("HumanoidRootPart")
			if not root or root._p.Anchored then
				continue
			end
			local speed = get(humanoid, "WalkSpeed")
			local cf = get(root, "CFrame")
			local p = cf.Position
			local flat = Vector3.new(target.X - p.X, 0, target.Z - p.Z)
			local distance = flat.Magnitude
			if distance <= 0.4 then
				humanoid._moveTarget = nil
				world.Movers[humanoid] = nil
				signalOf(humanoid, "MoveToFinished"):_fire(true)
				continue
			end
			if speed > 0 then
				local step = math.min(distance, speed * dt)
				local direction = flat / distance
				local nx, nz = p.X + direction.X * step, p.Z + direction.Z * step
				local hip = get(humanoid, "HipHeight")
				local half = get(root, "Size").Y / 2
				local footY = p.Y - hip - half
				local floor = standY(nx, nz, footY)
				local clear = floor and not blockedAt(nx, nz, floor, STEP_UP - 0.3)
				if not clear then
					-- physics slides a character along whatever it walked into
					for _, slide in { { nx, p.Z }, { p.X, nz } } do
						floor = standY(slide[1], slide[2], footY)
						if floor and not blockedAt(slide[1], slide[2], floor, STEP_UP - 0.3) then
							nx, nz, clear = slide[1], slide[2], true
							break
						end
					end
				end
				if clear and floor then
					local ny = floor + hip + half
					root:_setCFrame(
						CFrame.lookAt(Vector3.new(nx, ny, nz), Vector3.new(nx + direction.X, ny, nz + direction.Z))
					)
				end
			end
			if world.Now - (humanoid._moveStarted or 0) > 8 then
				humanoid._moveTarget = nil
				world.Movers[humanoid] = nil
				signalOf(humanoid, "MoveToFinished"):_fire(false)
			end
		end
	end

	function world:step(dt: number?)
		local delta = dt or world.StepSize
		world.Now += delta
		world.Stats.Steps += 1
		moveHumanoids(delta)
		-- what physics would report for a character moved this step (bots walk by CFrame)
		for _, player in PlayersService._children do
			local character = player._p and player._p.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local at = get(root, "CFrame").Position
				local last = root._lastAt
				root._lastAt = at
				if last then
					local moved = (at - last) / delta
					root._p.AssemblyLinearVelocity = if moved.Magnitude < 60 then moved else Vector3.zero
				end
			end
		end
		while #timers > 0 and timers[1].At <= world.Now + 1e-9 do
			local item = heapPop()
			if not cancelled[item.Thread] then
				resume(item.Thread, table.unpack(item.Args))
			end
		end
		signalOf(RunServiceInst, "Heartbeat"):_fire(delta)
		signalOf(RunServiceInst, "Stepped"):_fire(world.Now, delta)
		signalOf(RunServiceInst, "PreSimulation"):_fire(delta)
	end

	function world:run(seconds: number)
		local stop = world.Now + seconds
		while world.Now < stop - 1e-9 do
			world:step()
		end
	end

	-- Steps until fn() is truthy or `seconds` pass. Returns whether fn was satisfied.
	function world:runUntil(fn: () -> any, seconds: number): boolean
		local stop = world.Now + seconds
		while world.Now < stop do
			if fn() then
				return true
			end
			world:step()
		end
		return fn() and true or false
	end

	function world:boot()
		local main = loadScript(server)
		local thread = coroutine.create(main)
		resume(thread)
		world:step()
		return world
	end

	-- Calls BindToClose handlers (a server shutdown).
	function world:shutdown()
		for _, handler in world.CloseHandlers do
			resume(coroutine.create(handler))
		end
		for _ = 1, 100 do
			world:step()
		end
	end

	function world:phase(): string
		return ReplicatedStorage:GetAttribute("Phase")
	end

	function world:skipPhase()
		Workspace:SetAttribute("SkipPhase", true)
		world:step()
		world:step()
	end

	-- Runs the server's GameStateService clock forward until the given phase starts.
	function world:waitForPhase(name: string, maxSeconds: number?): boolean
		return world:runUntil(function()
			return ReplicatedStorage:GetAttribute("Phase") == name
		end, maxSeconds or 900)
	end

	return world
end

return Engine
