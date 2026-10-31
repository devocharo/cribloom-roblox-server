--[[
	Network.lua
	RemoteEvent/RemoteFunction wrapper for type-safe client-server communication.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Network = {}
local remotesFolder: Folder

-- Initialize remotes folder
local function getRemotesFolder(): Folder
	if remotesFolder then return remotesFolder end
	remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end
	return remotesFolder
end

-- ========== REMOTE EVENT CREATION ==========
function Network.CreateRemoteEvent(name: string): RemoteEvent
	local folder = getRemotesFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

function Network.CreateRemoteFunction(name: string): RemoteFunction
	local folder = getRemotesFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then return existing end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = folder
	return remote
end

function Network.CreateUnreliableRemoteEvent(name: string): UnreliableRemoteEvent
	local folder = getRemotesFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("UnreliableRemoteEvent") then return existing end
	local remote = Instance.new("UnreliableRemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

-- ========== PREDEFINED REMOTES ==========
-- Server -> Client
Network.OnMatchStateChanged = Network.CreateRemoteEvent("OnMatchStateChanged")
Network.OnPlayerJoinedMatch = Network.CreateRemoteEvent("OnPlayerJoinedMatch")
Network.OnPlayerLeftMatch = Network.CreateRemoteEvent("OnPlayerLeftMatch")
Network.OnBloomCreated = Network.CreateUnreliableRemoteEvent("OnBloomCreated")
Network.OnSuperBloomCreated = Network.CreateUnreliableRemoteEvent("OnSuperBloomCreated")
Network.OnBloomRemoved = Network.CreateUnreliableRemoteEvent("OnBloomRemoved")
Network.OnDamageDealt = Network.CreateUnreliableRemoteEvent("OnDamageDealt")
Network.OnPlayerHit = Network.CreateUnreliableRemoteEvent("OnPlayerHit")
Network.OnPlayerDeath = Network.CreateRemoteEvent("OnPlayerDeath")
Network.OnEssenceChanged = Network.CreateUnreliableRemoteEvent("OnEssenceChanged")
Network.OnUltimateReady = Network.CreateRemoteEvent("OnUltimateReady")
Network.OnUltimateActivated = Network.CreateRemoteEvent("OnUltimateActivated")
Network.OnScoreUpdate = Network.CreateRemoteEvent("OnScoreUpdate")
Network.OnMatchEnd = Network.CreateRemoteEvent("OnMatchEnd")
Network.OnLeaderboardUpdate = Network.CreateRemoteEvent("OnLeaderboardUpdate")
Network.OnPetalSpawned = Network.CreateUnreliableRemoteEvent("OnPetalSpawned")
Network.OnPetalCollected = Network.CreateRemoteEvent("OnPetalCollected")

-- Client -> Server
Network.RequestJoinQueue = Network.CreateRemoteFunction("RequestJoinQueue")
Network.RequestLeaveQueue = Network.CreateRemoteFunction("RequestLeaveQueue")
Network.RequestClassSelect = Network.CreateRemoteFunction("RequestClassSelect")
Network.RequestDash = Network.CreateRemoteEvent("RequestDash")
Network.RequestAttack = Network.CreateRemoteEvent("RequestAttack")
Network.RequestAbility = Network.CreateRemoteEvent("RequestAbility")
Network.RequestUltimate = Network.CreateRemoteEvent("RequestUltimate")
Network.RequestPetalCollect = Network.CreateRemoteEvent("RequestPetalCollect")
Network.RequestMatchData = Network.CreateRemoteFunction("RequestMatchData")

-- ========== HELPERS ==========
-- Fire to all clients
function Network.Broadcast(remoteName: string, ...: any)
	local remote = getRemotesFolder():FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients(...)
	elseif remote and remote:IsA("UnreliableRemoteEvent") then
		remote:FireAllClients(...)
	end
end

-- Fire to specific client
function Network.FireClient(player: Player, remoteName: string, ...: any)
	local remote = getRemotesFolder():FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, ...)
	elseif remote and remote:IsA("UnreliableRemoteEvent") then
		remote:FireClient(player, ...)
	end
end

-- Fire to all clients except one
function Network.FireAllExcept(excludePlayer: Player, remoteName: string, ...: any)
	local remote = getRemotesFolder():FindFirstChild(remoteName)
	if not remote then return end
	for _, player in ipairs(game.Players:GetPlayers()) do
		if player ~= excludePlayer then
			if remote:IsA("RemoteEvent") then
				remote:FireClient(player, ...)
			elseif remote:IsA("UnreliableRemoteEvent") then
				remote:FireClient(player, ...)
			end
		end
	end
end

-- Fire to team
function Network.FireTeam(team: Team, remoteName: string, ...: any)
	local remote = getRemotesFolder():FindFirstChild(remoteName)
	if not remote then return end
	for _, player in ipairs(team:GetPlayers()) do
		if remote:IsA("RemoteEvent") then
			remote:FireClient(player, ...)
		elseif remote:IsA("UnreliableRemoteEvent") then
			remote:FireClient(player, ...)
		end
	end
end

-- Invoke server from client (with timeout)
function Network.InvokeServer(remoteName: string, timeout: number, ...: any): (boolean, any?)
	local remote = getRemotesFolder():FindFirstChild(remoteName)
	if not remote or not remote:IsA("RemoteFunction") then
		return false, "RemoteFunction not found: " .. remoteName
	end

	local success, result = pcall(function()
		return remote:InvokeServer(...)
	end)

	if not success then
		return false, result
	end
	return true, result
end

-- Invoke client from server (with timeout)
function Network.InvokeClient(player: Player, remoteName: string, timeout: number, ...: any): (boolean, any?)
	local remote = getRemotesFolder():FindFirstChild(remoteName)
	if not remote or not remote:IsA("RemoteFunction") then
		return false, "RemoteFunction not found: " .. remoteName
	end

	local success, result = pcall(function()
		return remote:InvokeClient(player, ...)
	end)

	if not success then
		return false, result
	end
	return true, result
end

-- ========== CLIENT-SIDE LISTENERS ==========
if RunService:IsClient() then
	Network.ClientListeners = {}

	function Network.OnClientEvent(remoteName: string, callback: (...any) -> ())
		local remote = getRemotesFolder():WaitForChild(remoteName, 5)
		if not remote then
			warn("[Network] RemoteEvent not found: " .. remoteName)
			return
		end
		local connection = remote.OnClientEvent:Connect(callback)
		Network.ClientListeners[remoteName] = Network.ClientListeners[remoteName] or {}
		table.insert(Network.ClientListeners[remoteName], connection)
		return connection
	end

	function Network.CleanupClientListeners()
		for _, connections in pairs(Network.ClientListeners) do
			for _, conn in ipairs(connections) do
				conn:Disconnect()
			end
		end
		Network.ClientListeners = {}
	end
end

-- ========== SERVER-SIDE LISTENERS ==========
if RunService:IsServer() then
	Network.ServerListeners = {}

	function Network.OnServerEvent(remoteName: string, callback: (Player, ...any) -> ())
		local remote = getRemotesFolder():FindFirstChild(remoteName)
		if not remote or not remote:IsA("RemoteEvent") then
			warn("[Network] RemoteEvent not found: " .. remoteName)
			return
		end
		local connection = remote.OnServerEvent:Connect(callback)
		Network.ServerListeners[remoteName] = Network.ServerListeners[remoteName] or {}
		table.insert(Network.ServerListeners[remoteName], connection)
		return connection
	end

	function Network.OnServerInvoke(remoteName: string, callback: (Player, ...any) -> (...any))
		local remote = getRemotesFolder():FindFirstChild(remoteName)
		if not remote or not remote:IsA("RemoteFunction") then
			warn("[Network] RemoteFunction not found: " .. remoteName)
			return
		end
		remote.OnServerInvoke = callback
	end

	function Network.CleanupServerListeners()
		for _, connections in pairs(Network.ServerListeners) do
			for _, conn in ipairs(connections) do
				conn:Disconnect()
			end
		end
		Network.ServerListeners = {}
	end
end

return Network