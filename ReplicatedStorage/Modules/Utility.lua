--[[
	Utility.lua
	Shared helper functions for Critbloom.
]]

local Utility = {}

-- ========== TABLE UTILITIES ==========
function Utility.DeepCopy(original: any): any
	local copy
	if type(original) == "table" then
		copy = {}
		for key, value in pairs(original) do
			copy[Utility.DeepCopy(key)] = Utility.DeepCopy(value)
		end
		setmetatable(copy, Utility.DeepCopy(getmetatable(original)))
	else
		copy = original
	end
	return copy
end

function Utility.ShallowCopy(t: { [any]: any }): { [any]: any }
	local copy = {}
	for k, v in pairs(t) do copy[k] = v end
	return copy
end

function Utility.TableLength(t: { [any]: any }): number
	local count = 0
	for _ in pairs(t) do count += 1 end
	return count
end

function Utility.GetRandomKey(t: { [any]: any }): any
	local keys = {}
	for k in pairs(t) do table.insert(keys, k) end
	return keys[math.random(#keys)]
end

function Utility.Shuffle(t: { [number]: any })
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- ========== MATH UTILITIES ==========
function Utility.Clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

function Utility.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * Utility.Clamp(t, 0, 1)
end

function Utility.LerpVector3(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, Utility.Clamp(t, 0, 1))
end

function Utility.Round(num: number, decimals: number?): number
	local mult = 10 ^ (decimals or 0)
	return math.floor(num * mult + 0.5) / mult
end

function Utility.MapRange(value: number, inMin: number, inMax: number, outMin: number, outMax: number): number
	return outMin + (value - inMin) * (outMax - outMin) / (inMax - inMin)
end

-- ========== VECTOR UTILITIES ==========
function Utility.FlattenVector3(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Utility.GetHorizontalDistance(a: Vector3, b: Vector3): number
	return (Utility.FlattenVector3(a) - Utility.FlattenVector3(b)).Magnitude
end

function Utility.GetDirection(from: Vector3, to: Vector3): Vector3
	local diff = to - from
	if diff.Magnitude == 0 then return Vector3.zero end
	return diff.Unit
end

function Utility.RotateVector2(v: Vector2, angle: number): Vector2
	local c, s = math.cos(angle), math.sin(angle)
	return Vector2.new(v.X * c - v.Y * s, v.X * s + v.Y * c)
end

-- ========== TIME UTILITIES ==========
function Utility.FormatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	local ms = math.floor((seconds % 1) * 100)
	return string.format("%02d:%02d.%02d", mins, secs, ms)
end

function Utility.FormatTimeShort(seconds: number): string
	if seconds >= 3600 then
		return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
	elseif seconds >= 60 then
		return string.format("%dm %ds", math.floor(seconds / 60), seconds % 60)
	else
		return string.format("%ds", seconds)
	end
end

-- ========== STRING UTILITIES ==========
function Utility.Trim(s: string): string
	return s:match("^%s*(.-)%s*$") or ""
end

function Utility.Split(s: string, delimiter: string): { string }
	local result = {}
	for part in s:gmatch("[^" .. delimiter .. "]+") do
		table.insert(result, part)
	end
	return result
end

function Utility.Pluralize(count: number, singular: string, plural: string?): string
	return count == 1 and singular or (plural or singular .. "s")
end

-- ========== COLOR UTILITIES ==========
function Utility.HexToColor3(hex: string): Color3
	hex = hex:gsub("#", "")
	return Color3.fromRGB(
		tonumber(hex:sub(1, 2), 16),
		tonumber(hex:sub(3, 4), 16),
		tonumber(hex:sub(5, 6), 16)
	)
end

function Utility.Color3ToHex(color: Color3): string
	return string.format("#%02X%02X%02X",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255)
	)
end

function Utility.LerpColor(c1: Color3, c2: Color3, t: number): Color3
	t = Utility.Clamp(t, 0, 1)
	return Color3.new(
		Utility.Lerp(c1.R, c2.R, t),
		Utility.Lerp(c1.G, c2.G, t),
		Utility.Lerp(c1.B, c2.B, t)
	)
end

-- ========== INSTANCE UTILITIES ==========
function Utility.Create(className: string, properties: { [string]: any }?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	if properties then
		for prop, value in pairs(properties) do
			instance[prop] = value
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end
	return instance
end

function Utility.DestroyChildren(parent: Instance, classNameFilter: string?)
	for _, child in ipairs(parent:GetChildren()) do
		if not classNameFilter or child:IsA(classNameFilter) then
			child:Destroy()
		end
	end
end

function Utility.WaitForChildOfClass(parent: Instance, className: string, timeout: number?): Instance?
	local child = parent:FindFirstChildOfClass(className)
	if child then return child end

	local startTime = tick()
	timeout = timeout or 5
	while tick() - startTime < timeout do
		child = parent:FindFirstChildOfClass(className)
		if child then return child end
		task.wait()
	end
	return nil
end

-- ========== SIGNAL/ EVENT UTILITIES ==========
type SignalCallback = (...any) -> ()
type SignalConnection = { Disconnect: (self: SignalConnection) -> () }

local Signal = {}
Signal.__index = Signal

function Signal.new(): SignalConnection
	return setmetatable({ _connections = {} }, Signal)
end

function Signal:Connect(callback: SignalCallback): SignalConnection
	local connection = { _callback = callback, _connected = true }
	function connection:Disconnect()
		self._connected = false
		for i, conn in ipairs(self._connections) do
			if conn == self then
				table.remove(self._connections, i)
				break
			end
		end
	end
	table.insert(self._connections, connection)
	return connection
end

function Signal:Fire(...: any)
	for _, connection in ipairs(self._connections) do
		if connection._connected then
			task.spawn(connection._callback, ...)
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

Utility.Signal = Signal

-- ========== MAID (CLEANUP) ==========
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:GiveTask(task: any): any
	if typeof(task) == "Instance" then
		table.insert(self._tasks, function() task:Destroy() end)
	elseif type(task) == "function" then
		table.insert(self._tasks, task)
	elseif type(task) == "table" and task.Disconnect then
		table.insert(self._tasks, function() task:Disconnect() end)
	end
	return task
end

function Maid:DoCleaning()
	for _, task in ipairs(self._tasks) do
		task()
	end
	self._tasks = {}
end

function Maid:Destroy()
	self:DoCleaning()
	setmetatable(self, nil)
end

Utility.Maid = Maid

-- ========== DEBUG ==========
Utility.Debug = false

function Utility.Log(...: any)
	if Utility.Debug then
		print("[Critbloom]", os.date("%H:%M:%S"), ...)
	end
end

function Utility.Warn(...: any)
	warn("[Critbloom]", os.date("%H:%M:%S"), ...)
end

function Utility.Error(...: any)
	error("[Critbloom] " .. table.concat({...}, " "), 2)
end

function Utility.Assert(condition: boolean, message: string)
	if not condition then
		Utility.Error("Assertion failed: " .. message)
	end
end

return Utility