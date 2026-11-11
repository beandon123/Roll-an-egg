--!nocheck
-- Loads game modules outside Roblox Studio so their logic can be tested with Lune (https://lune-org.github.io/docs).
--
-- Game modules find each other the Roblox way: `require(script.Parent.Something)` and
-- `game:GetService("ReplicatedStorage").Shared`. This harness fakes just enough of `script` and `game` for that
-- to work against the files on disk, following the same layout as default.project.json:
--     ReplicatedStorage.Shared        -> src/shared
--     ServerScriptService.Server      -> src/server
-- Only modules that stick to plain Luau (no parts, players, or remotes) can be loaded this way.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local harness = {}

local loaded: { [string]: any } = {}
local fakeGame

-- The source tree is read once, up front: Lune's file functions cannot be called from inside the
-- metamethods that fake Roblox's `script.Parent.Child` lookups.
local files: { [string]: string } = {}
local dirs: { [string]: boolean } = {}

local function scan(dir: string)
	dirs[dir] = true
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			scan(path)
		elseif entry:match("%.luau$") then
			files[path] = fs.readFile(path)
		end
	end
end
scan("src")

local function parentOf(path: string): string
	return (path:gsub("/[^/]+$", ""))
end

local function nameOf(path: string): string
	local base = path:match("([^/]+)$") or path
	return (base:gsub("%.luau$", ""))
end

local makeInstance

-- A stand-in for a Roblox Instance backed by a file or directory.
function makeInstance(path: string, isDir: boolean)
	return setmetatable({ __path = path, __isDir = isDir }, {
		__index = function(_, key)
			if key == "Parent" then
				return makeInstance(parentOf(path), true)
			elseif key == "Name" then
				return nameOf(path)
			end
			if isDir then
				local file = path .. "/" .. key .. ".luau"
				if files[file] ~= nil then
					return makeInstance(file, false)
				end
				local dir = path .. "/" .. key
				if dirs[dir] then
					return makeInstance(dir, true)
				end
			end
			error(`{key} is not a valid member of {path}`, 2)
		end,
	})
end

local function fakeRequire(target: any)
	assert(type(target) == "table" and target.__path, "test harness: require() expects a fake instance")
	local path = target.__path
	if target.__isDir then
		path = path .. "/init.luau"
	end
	if loaded[path] ~= nil then
		return loaded[path]
	end

	local source = files[path]
	if source == nil then
		error(`test harness: no module at {path}`, 2)
	end
	local chunk = luau.load(source, {
		debugName = path,
		environment = {
			script = makeInstance(target.__path, target.__isDir),
			require = fakeRequire,
			game = fakeGame,
		},
	})
	local result = chunk()
	loaded[path] = result
	return result
end

local services = {
	ReplicatedStorage = setmetatable({}, {
		__index = function(_, key)
			if key == "Shared" then
				return makeInstance("src/shared", true)
			end
			error(`ReplicatedStorage.{key} is not available in tests`, 2)
		end,
	}),
}

fakeGame = {
	GetService = function(_, name: string)
		local service = services[name]
		if service == nil then
			error(`game:GetService("{name}") is not available in tests`, 2)
		end
		return service
	end,
}

-- Loads a module by its path from the repository root, without the extension:
-- harness.load("src/shared/EggMotion")
function harness.load(path: string)
	return fakeRequire(makeInstance(path .. ".luau", false))
end

----------------------------------------------------------------------------------------------------------------
-- A very small test framework.

local results = { passed = 0, failed = 0, failures = {} :: { string } }
-- Set VERBOSE=1 to print each test's name as it starts (useful for finding a test that hangs).
local verbose = require("@lune/process").env.VERBOSE ~= nil
local currentSuite = ""

function harness.describe(name: string, body: () -> ())
	currentSuite = name
	body()
	currentSuite = ""
end

function harness.it(name: string, body: () -> ())
	if verbose then
		print(`  {currentSuite} > {name}`)
	end
	local ok, err = xpcall(body, function(message)
		return debug.traceback(tostring(message), 2)
	end)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, `{currentSuite} > {name}\n{err}`)
	end
end

local expect = {}

function expect.equal(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

function expect.near(actual: number, expected: number, tolerance: number?, label: string?)
	if math.abs(actual - expected) > (tolerance or 1e-6) then
		error(`{label or "value"}: expected about {expected}, got {actual}`, 2)
	end
end

function expect.truthy(value: any, label: string?)
	if not value then
		error(`{label or "value"}: expected something truthy, got {tostring(value)}`, 2)
	end
end

function expect.falsy(value: any, label: string?)
	if value then
		error(`{label or "value"}: expected nil or false, got {tostring(value)}`, 2)
	end
end

harness.expect = expect

function harness.finish(): number
	for _, failure in results.failures do
		print("FAIL " .. failure .. "\n")
	end
	print(`{results.passed} passed, {results.failed} failed`)
	return if results.failed > 0 then 1 else 0
end

return harness
