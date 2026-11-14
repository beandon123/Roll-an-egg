--!nocheck
-- A stand-in for Roblox Studio, so the real game scripts can be run by Lune.
--
-- It opens the place file that Rojo builds, then runs the game's own Script / LocalScript against it. Instances
-- are Lune's real implementations, which reject misspelled properties and enum items, so a typo such as
-- `part.CanColide = false` fails here instead of in Studio. The parts of Roblox that Lune does not provide
-- (events, remotes, the clock, a few methods) are faked below, just far enough for the game code to run.
--
-- What this cannot check: anything that needs the real engine, such as physics, character animation, input,
-- rendering, and networking. Those still need a play test in Studio.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Instance = roblox.Instance
local Enum = roblox.Enum

local Studio = {}

-- The session currently in use. The fakes below are registered once per process and read from it.
local current = nil

----------------------------------------------------------------------------------------------------------------
-- Signals (events)

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ entries = {} }, Signal)
end

function Signal:Connect(handler)
	local entry = { handler = handler }
	table.insert(self.entries, entry)
	local connection = { Connected = true }
	function connection.Disconnect()
		connection.Connected = false
		local index = table.find(self.entries, entry)
		if index then
			table.remove(self.entries, index)
		end
	end
	return connection
end

function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...)
	for _, entry in table.clone(self.entries) do
		entry.handler(...)
	end
end

Studio.Signal = Signal

local function signalOf(instance, name: string)
	local signals = current.signals[instance]
	if signals == nil then
		signals = {}
		current.signals[instance] = signals
	end
	local signal = signals[name]
	if signal == nil then
		signal = Signal.new()
		signals[name] = signal
	end
	return signal
end

local function fakeEvent(className: string, name: string)
	roblox.implementProperty(className, name, function(self)
		return signalOf(self, name)
	end)
end

-- A value stored per instance, for members Lune does not have.
local function fakeValue(className: string, name: string)
	roblox.implementProperty(className, name, function(self)
		local values = current.values[self]
		return values and values[name]
	end, function(self, value)
		local values = current.values[self]
		if values == nil then
			values = {}
			current.values[self] = values
		end
		values[name] = value
	end)
end

----------------------------------------------------------------------------------------------------------------
-- Fakes for what Lune's Roblox library leaves out. Registered once; they act on the current session.

fakeEvent("RunService", "Heartbeat")
fakeEvent("RunService", "RenderStepped")
fakeEvent("Players", "PlayerAdded")
fakeEvent("Players", "PlayerRemoving")
fakeEvent("Player", "CharacterAdded")
fakeEvent("Player", "CharacterRemoving")
fakeEvent("Humanoid", "Died")
fakeEvent("BaseRemoteEvent", "OnServerEvent")
fakeEvent("BaseRemoteEvent", "OnClientEvent")
fakeEvent("UserInputService", "JumpRequest")
fakeEvent("GuiButton", "Activated")
fakeEvent("ProximityPrompt", "Triggered")
fakeEvent("Instance", "Destroying")
fakeEvent("Instance", "AncestryChanged")
fakeEvent("Instance", "ChildAdded")
fakeEvent("Instance", "ChildRemoved")
fakeEvent("Instance", "DescendantAdded")
fakeEvent("Instance", "Changed")
fakeEvent("Instance", "AttributeChanged")

fakeValue("RemoteFunction", "OnServerInvoke")

roblox.implementMethod("Instance", "WaitForChild", function(self, name)
	local child = self:FindFirstChild(name)
	if child == nil then
		error(`WaitForChild("{name}") would wait forever: {self:GetFullName()} has no such child`, 2)
	end
	return child
end)

roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, property)
	return signalOf(self, "Changed:" .. property)
end)

roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, attribute)
	return signalOf(self, "AttributeChanged:" .. attribute)
end)

roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return current.clock
end)

roblox.implementMethod("RunService", "IsServer", function()
	return current.isServer
end)
roblox.implementMethod("RunService", "IsClient", function()
	return not current.isServer
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return current.isStudio
end)
roblox.implementMethod("RunService", "BindToRenderStep", function(_, name, priority, callback)
	table.insert(current.renderSteps, { name = name, priority = priority, callback = callback })
	table.sort(current.renderSteps, function(a, b)
		return a.priority < b.priority
	end)
end)
roblox.implementMethod("RunService", "UnbindFromRenderStep", function(_, name)
	for index, step in current.renderSteps do
		if step.name == name then
			table.remove(current.renderSteps, index)
			return
		end
	end
end)

-- Keys and gamepad buttons held down: tests set `session.keysDown[Enum.KeyCode.Space] = true`.
roblox.implementMethod("UserInputService", "IsKeyDown", function(_, keyCode)
	return current.keysDown[keyCode] == true
end)
roblox.implementMethod("UserInputService", "IsGamepadButtonDown", function(_, _gamepad, keyCode)
	return current.keysDown[keyCode] == true
end)

roblox.implementMethod("Players", "GetPlayers", function(self)
	local list = {}
	for _, child in self:GetChildren() do
		if child:IsA("Player") then
			table.insert(list, child)
		end
	end
	return list
end)
roblox.implementMethod("Players", "GetPlayerByUserId", function(self, userId)
	for _, child in self:GetChildren() do
		if child:IsA("Player") and child.UserId == userId then
			return child
		end
	end
	return nil
end)
roblox.implementMethod("Player", "Kick", function(self, message)
	table.insert(current.kicks, { player = self, message = message })
end)

-- Remotes do not cross a network here: every send is recorded, and tests deliver messages by hand.
local function record(remote, to, ...)
	table.insert(current.messages, { remote = remote.Name, to = to, args = table.pack(...) })
end
roblox.implementMethod("BaseRemoteEvent", "FireAllClients", function(self, ...)
	record(self, "all", ...)
end)
roblox.implementMethod("BaseRemoteEvent", "FireClient", function(self, player, ...)
	record(self, player, ...)
end)
roblox.implementMethod("BaseRemoteEvent", "FireServer", function(self, ...)
	record(self, "server", ...)
end)
roblox.implementMethod("RemoteFunction", "InvokeServer", function(self, ...)
	record(self, "server", ...)
	local handler = current.invokeHandlers[self.Name]
	if handler == nil then
		error(`no test handler for {self.Name}:InvokeServer()`, 2)
	end
	return handler(...)
end)

-- A model's pivot is its PrimaryPart's CFrame here (Roblox also has Model.WorldPivot for models without one).
roblox.implementMethod("Model", "GetPivot", function(self)
	local primary = self.PrimaryPart
	if primary == nil then
		error("GetPivot: the test stand-in needs the model to have a PrimaryPart", 2)
	end
	return primary.CFrame
end)

-- Moves every part in the model together, as Roblox does, so it keeps its shape.
roblox.implementMethod("Model", "PivotTo", function(self, cframe)
	local primary = self.PrimaryPart
	if primary == nil then
		error("PivotTo: the test stand-in needs the model to have a PrimaryPart", 2)
	end
	local move = cframe * primary.CFrame:Inverse()
	for _, part in self:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = move * part.CFrame
		end
	end
end)

roblox.implementMethod("Humanoid", "GetState", function(self)
	return current.humanoidStates[self] or Enum.HumanoidStateType.Running
end)
roblox.implementMethod("Humanoid", "ChangeState", function(self, state)
	current.humanoidStates[self] = state
end)

roblox.implementMethod("HttpService", "GenerateGUID", function()
	current.guid += 1
	return "test-guid-" .. current.guid
end)

roblox.implementMethod("TweenService", "Create", function(_, instance, _, goals)
	for property in goals do
		-- Reading the property makes a misspelled name fail.
		local _ = instance[property]
	end
	return {
		Play = function()
			for property, value in goals do
				instance[property] = value
			end
		end,
		Cancel = function() end,
	}
end)

----------------------------------------------------------------------------------------------------------------
-- A session: one place file, opened as either the server or one player's device.

local Session = {}
Session.__index = Session

local function describeInstance(instance): string
	local ok, name = pcall(function()
		return instance:GetFullName()
	end)
	return if ok then name else tostring(instance)
end

function Session:environment(scriptInstance)
	local session = self
	local seed = 0
	return {
		script = scriptInstance,
		game = self.game,
		workspace = self.game:GetService("Workspace"),
		require = function(target)
			return session:require(target)
		end,
		Instance = Instance,
		Enum = Enum,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Rect = roblox.Rect,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		ColorSequence = roblox.ColorSequence,
		TweenInfo = {
			new = function(...)
				return { arguments = { ... } }
			end,
		},
		Random = {
			new = function()
				seed += 1
				return {
					NextNumber = function(_, low, high)
						local value = math.random()
						if low ~= nil then
							return low + (high - low) * value
						end
						return value
					end,
					NextInteger = function(_, low, high)
						return math.random(low, high)
					end,
				}
			end,
		},
		task = task,
		-- Libraries such as Fusion check that events really are Roblox signals.
		typeof = function(value)
			if type(value) == "table" and getmetatable(value) == Signal then
				return "RBXScriptSignal"
			end
			return typeof(value)
		end,
		warn = function(...)
			local parts = {}
			for _, value in { ... } do
				table.insert(parts, tostring(value))
			end
			table.insert(session.warnings, table.concat(parts, " "))
		end,
		tick = os.clock,
		time = os.clock,
	}
end

-- Loads a ModuleScript the way Roblox would: once, by instance.
function Session:require(target)
	if typeof(target) ~= "Instance" or not target:IsA("ModuleScript") then
		error("require() expects a ModuleScript, got " .. tostring(target), 2)
	end
	local override = self.overrides[target]
	if override ~= nil then
		return override
	end
	local cached = self.modules[target]
	if cached then
		return cached.value
	end
	local chunk = luau.load(target.Source, {
		debugName = describeInstance(target),
		environment = self:environment(target),
	})
	local value = chunk()
	self.modules[target] = { value = value }
	return value
end

-- Runs a Script or LocalScript.
function Session:run(scriptInstance)
	current = self
	local chunk = luau.load(scriptInstance.Source, {
		debugName = describeInstance(scriptInstance),
		environment = self:environment(scriptInstance),
	})
	chunk()
end

function Session:service(name: string)
	return self.game:GetService(name)
end

-- Makes `require(module)` return `value` instead of running the module.
function Session:override(module, value)
	self.overrides[module] = value
end

-- Adds a player with a simple character. On the server this fires PlayerAdded.
function Session:addPlayer(userId: number, name: string)
	current = self
	local players = self:service("Players")
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = userId
	player.Parent = players

	local character = Instance.new("Model")
	character.Name = name
	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid.Jump = false
	humanoid.Parent = character
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = roblox.Vector3.new(0, 13, -100)
	root.Parent = character
	character.PrimaryPart = root
	character.Parent = self:service("Workspace")
	player.Character = character

	if self.isServer then
		signalOf(players, "PlayerAdded"):Fire(player)
	end
	return player, humanoid, root
end

-- Makes a player the one whose device this session stands for, with the folders Roblox would give them.
function Session:setLocalPlayer(player)
	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = player

	local playerScripts = Instance.new("PlayerScripts")
	playerScripts.Name = "PlayerScripts"
	playerScripts.Parent = player
	local playerModule = Instance.new("ModuleScript")
	playerModule.Name = "PlayerModule"
	playerModule.Parent = playerScripts

	-- Stands in for Roblox's control scripts; tests set `session.moveVector`.
	local session = self
	self:override(playerModule, {
		GetControls = function()
			return {
				GetMoveVector = function()
					return session.moveVector
				end,
			}
		end,
	})

	local workspace = self:service("Workspace")
	local camera = Instance.new("Camera")
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
	-- Looking down the runway (+Z), as a player would be.
	camera.CFrame = roblox.CFrame.lookAt(roblox.Vector3.new(0, 20, -10), roblox.Vector3.new(0, 20, 10))
	camera.Parent = workspace
	workspace.CurrentCamera = camera

	self:service("Players").LocalPlayer = player
	return playerGui
end

-- Advances the clock and fires Heartbeat.
function Session:heartbeat(deltaTime: number, count: number?)
	current = self
	local heartbeat = signalOf(self:service("RunService"), "Heartbeat")
	for _ = 1, count or 1 do
		self.clock += deltaTime
		heartbeat:Fire(deltaTime)
	end
end

-- Advances the clock and runs one rendered frame: render steps in priority order, then RenderStepped.
function Session:renderFrame(deltaTime: number, count: number?)
	current = self
	local renderStepped = signalOf(self:service("RunService"), "RenderStepped")
	for _ = 1, count or 1 do
		self.clock += deltaTime
		for _, step in table.clone(self.renderSteps) do
			step.callback(deltaTime)
		end
		renderStepped:Fire(deltaTime)
	end
end

function Session:remote(name: string)
	return self:service("ReplicatedStorage").Remotes[name]
end

-- Delivers a message to the server as if `player` had sent it.
function Session:fromClient(name: string, player, ...)
	current = self
	signalOf(self:remote(name), "OnServerEvent"):Fire(player, ...)
end

-- Delivers a message to this device as if the server had sent it.
function Session:fromServer(name: string, ...)
	current = self
	signalOf(self:remote(name), "OnClientEvent"):Fire(...)
end

-- Fires any other event on an instance, e.g. session:fire(humanoid, "Died").
function Session:fire(instance, eventName: string, ...)
	current = self
	signalOf(instance, eventName):Fire(...)
end

-- Every message sent through a remote so far, optionally only those sent to one target
-- ("all", "server", or a player).
function Session:sent(name: string, to: any?)
	local list = {}
	for _, entry in self.messages do
		if entry.remote == name and (to == nil or entry.to == to) then
			table.insert(list, entry)
		end
	end
	return list
end

function Session:lastSent(name: string, to: any?)
	local list = self:sent(name, to)
	return list[#list]
end

function Session:clearSent()
	table.clear(self.messages)
end

-- Replaces ProfileStore with an in-memory stand-in. Data "saved" when a session ends is kept in
-- `session.saved`, and live profiles are in `session.profiles`, both by profile key.
function Session:useFakeProfileStore()
	local session = self
	session.saved = session.saved or {}
	session.profiles = {}

	local function deepCopy(value)
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, item in value do
			copy[key] = deepCopy(item)
		end
		return copy
	end

	local function reconcile(data, template)
		for key, item in template do
			if type(key) == "string" then
				if data[key] == nil then
					data[key] = deepCopy(item)
				elseif type(data[key]) == "table" and type(item) == "table" then
					reconcile(data[key], item)
				end
			end
		end
	end

	local fake = {}
	function fake.New(storeName, template)
		local store = { Name = storeName }
		function store.StartSessionAsync(_, key)
			local active = true
			local profile = {
				Data = deepCopy(session.saved[key] or template),
				Key = key,
				OnSessionEnd = Signal.new(),
			}
			function profile.IsActive()
				return active
			end
			function profile.AddUserId() end
			function profile.Reconcile()
				reconcile(profile.Data, template)
			end
			function profile.EndSession()
				if active then
					active = false
					session.saved[key] = deepCopy(profile.Data)
					profile.OnSessionEnd:Fire()
				end
			end
			session.profiles[key] = profile
			return profile
		end
		return store
	end

	self:override(self:service("ServerScriptService").ServerPackages.ProfileStore, fake)
end

-- On a client session, creates the remotes the server would have created.
function Session:createRemotes()
	current = self
	local wasServer = self.isServer
	self.isServer = true
	self:require(self:service("ReplicatedStorage").Shared.Net)
	self.isServer = wasServer
	-- The game's own require of Net must run again, as a client this time.
	self.modules = {}
end

----------------------------------------------------------------------------------------------------------------

-- Builds the place file with Rojo. Returns its path, or nil (with a reason) if Rojo is not installed.
function Studio.buildPlace(): (string?, string?)
	local output = "tests/.tmp/RollAnEgg.rbxl"
	if not fs.isDir("tests/.tmp") then
		fs.writeDir("tests/.tmp")
	end
	local ok, result = pcall(process.exec, "rojo", { "build", "-o", output })
	if not ok then
		return nil, "Rojo is not installed"
	end
	if not result.ok then
		return nil, "rojo build failed: " .. result.stderr
	end
	return output, nil
end

-- Opens a built place file as the server (`isServer = true`) or as one player's device.
function Studio.open(placePath: string, options: { isServer: boolean, isStudio: boolean? })
	local session = setmetatable({
		game = roblox.deserializePlace(fs.readFile(placePath)),
		isServer = options.isServer,
		isStudio = if options.isStudio == nil then true else options.isStudio,
		-- The shared server clock, in seconds. Starts partway through a runway cycle, well before it closes.
		clock = 180 * 1000 + 5,
		signals = {},
		values = {},
		messages = {},
		renderSteps = {},
		modules = {},
		overrides = {},
		humanoidStates = {},
		invokeHandlers = {},
		kicks = {},
		warnings = {},
		guid = 0,
		moveVector = roblox.Vector3.new(0, 0, 0),
		keysDown = {},
	}, Session)
	current = session
	return session
end

return Studio
