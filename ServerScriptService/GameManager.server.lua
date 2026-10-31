--[[
	GameManager.server.lua
	Main server script managing match lifecycle, game modes, and state.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConstants = require(ReplicatedStorage.Modules.GameConstants)
local Network = require(ReplicatedStorage.Modules.Network)
local Utility = require(ReplicatedStorage.Modules.Utility)
local BloomMath = require(ReplicatedStorage.Modules.BloomMath)

-- ========== MODULES ==========
local PlayerData = require(script.Parent.PlayerData)
local CombatSystem = require(script.Parent.CombatSystem)
local Matchmaking = require(script.Parent.Matchmaking)
local EssenceSystem = require(script.Parent.EssenceSystem)

-- ========== STATE ==========
type MatchState = "Waiting" | "Starting" | "InProgress" | "SuddenDeath" | "Ended" | "Intermission"

local GameManager = {
	CurrentMatch = nil,
	MatchState = "Waiting" :: MatchState,
	ActiveBlooms = {}, -- [id] = { Center, Radius, EndTime, IsSuper, Creator }
	BloomIdCounter = 0,
	MatchStartTime = 0,
	MapName = "",
	CurrentMap = nil,
	TeamA = nil,
	TeamB = nil,
	Score = { TeamA = 0, TeamB = 0 },
	BloomCore = nil,
	PetalSpawns = {},
}

-- ========== TEAM SETUP ==========
local function SetupTeams()
	if not Teams:FindFirstChild("TeamA") then
		local teamA = Instance.new("Team")
		teamA.Name = "TeamA"
		teamA.TeamColor = BrickColor.new("Bright violet")
		teamA.AutoAssignable = false
		teamA.Parent = Teams
		GameManager.TeamA = teamA
	end

	if not Teams:FindFirstChild("TeamB") then
		local teamB = Instance.new("Team")
		teamB.Name = "TeamB"
		teamB.TeamColor = BrickColor.new("Bright orange")
		teamB.AutoAssignable = false
		teamB.Parent = Teams
		GameManager.TeamB = teamB
	end
end

-- ========== MAP LOADING ==========
local function LoadMap(mapName: string)
	local mapData = GameConstants.Maps[mapName]
	if not mapData then
		warn("[GameManager] Map not found: " .. mapName)
		mapName = "SakuraGardens"
		mapData = GameConstants.Maps[mapName]
	end

	GameManager.MapName = mapName
	GameManager.CurrentMap = mapData

	-- Clear existing map
	local mapsFolder = Workspace:FindFirstChild("Maps")
	if mapsFolder then mapsFolder:Destroy() end
	mapsFolder = Instance.new("Folder")
	mapsFolder.Name = "Maps"
	mapsFolder.Parent = Workspace

	-- Create baseplate
	local baseplate = Instance.new("Part")
	baseplate.Name = "Baseplate"
	baseplate.Size = mapData.Size
	baseplate.Position = Vector3.new(0, mapData.Size.Y / 2, 0)
	baseplate.Anchored = true
	baseplate.Material = Enum.Material.Grass
	baseplate.Color = Color3.fromRGB(40, 35, 50)
	baseplate.Parent = mapsFolder

	-- Create spawn points
	local spawnsFolder = Workspace:FindFirstChild("Spawns")
	if spawnsFolder then spawnsFolder:Destroy() end
	spawnsFolder = Instance.new("Folder")
	spawnsFolder.Name = "Spawns"
	spawnsFolder.Parent = Workspace

	for teamName, spawnPoints in pairs(mapData.SpawnPoints) do
		local teamFolder = Instance.new("Folder")
		teamFolder.Name = teamName
		teamFolder.Parent = spawnsFolder
		for i, pos in ipairs(spawnPoints) do
			local spawn = Instance.new("SpawnLocation")
			spawn.Name = "Spawn" .. i
			spawn.Position = pos
			spawn.Size = Vector3.new(6, 1, 6)
			spawn.Anchored = true
			spawn.TeamColor = teamName == "TeamA" and BrickColor.new("Bright violet") or BrickColor.new("Bright orange")
			spawn.AllowTeamChangeOnTouch = false
			spawn.Neutral = false
			spawn.Parent = teamFolder
		end
	end

	-- Create bloom core for Bloom Ball mode
	local core = Instance.new("Part")
	core.Name = "BloomCore"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(4, 4, 4)
	core.Position = mapData.BloomCoreSpawn
	core.Anchored = true
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(255, 20, 147)
	core.CanCollide = false
	core.Parent = mapsFolder
	GameManager.BloomCore = core

	-- Add bloom core visual effects
	local pointLight = Instance.new("PointLight")
	pointLight.Color = Color3.fromRGB(255, 20, 147)
	pointLight.Range = 30
	pointLight.Brightness = 2
	pointLight.Parent = core

	-- Create petal spawn zones
	GameManager.PetalSpawns = {}
	local petalsFolder = Workspace:FindFirstChild("PetalSpawns")
	if petalsFolder then petalsFolder:Destroy() end
	petalsFolder = Instance.new("Folder")
	petalsFolder.Name = "PetalSpawns"
	petalsFolder.Parent = Workspace

	for i = 1, mapData.PetalSpawnZones do
		local zone = Instance.new("Part")
		zone.Name = "PetalZone" .. i
		zone.Size = Vector3.new(10, 1, 10)
		zone.Position = Vector3.new(
			math.random(-mapData.Size.X/2 + 20, mapData.Size.X/2 - 20),
			5,
			math.random(-mapData.Size.Z/2 + 20, mapData.Size.Z/2 - 20)
		)
		zone.Anchored = true
		zone.Transparency = 1
		zone.CanCollide = false
		zone.Parent = petalsFolder
		table.insert(GameManager.PetalSpawns, zone)
	end

	Utility.Log("Loaded map:", mapName)
end

-- ========== MATCH STATE MACHINE ==========
local function SetMatchState(newState: MatchState)
	GameManager.MatchState = newState
	Network.Broadcast("OnMatchStateChanged", newState, GameManager.GetMatchInfo())
	Utility.Log("Match state changed:", newState)
end

function GameManager.GetMatchInfo()
	return {
		State = GameManager.MatchState,
		MapName = GameManager.MapName,
		TimeRemaining = GameManager.GetTimeRemaining(),
		Score = GameManager.Score,
		TeamAPlayers = GameManager.TeamA and #GameManager.TeamA:GetPlayers() or 0,
		TeamBPlayers = GameManager.TeamB and #GameManager.TeamB:GetPlayers() or 0,
	}
end

function GameManager.GetTimeRemaining(): number
	if GameManager.MatchState ~= "InProgress" and GameManager.MatchState ~= "SuddenDeath" then
		return 0
	end
	local elapsed = tick() - GameManager.MatchStartTime
	local duration = GameManager.MatchState == "SuddenDeath"
		and GameConstants.Match.SuddenDeathDuration
		or GameConstants.Match.MatchDuration
	return math.max(0, duration - elapsed)
end

-- ========== BLOOM MANAGEMENT ==========
function GameManager.CreateBloom(center: Vector3, creator: Player, isSuper: boolean): number
	GameManager.BloomIdCounter += 1
	local id = GameManager.BloomIdCounter

	local constants = GameConstants.Bloom
	local bloom = {
		Id = id,
		Center = center,
		Radius = isSuper and constants.SuperBloomRadius or constants.Radius,
		EndTime = tick() + (isSuper and constants.SuperBloomDuration or constants.Duration),
		IsSuper = isSuper,
		Creator = creator,
	}

	GameManager.ActiveBlooms[id] = bloom

	-- Notify clients
	if isSuper then
		Network.Broadcast("OnSuperBloomCreated", id, center, bloom.Radius, bloom.EndTime)
	else
		Network.Broadcast("OnBloomCreated", id, center, bloom.Radius, bloom.EndTime)
	end

	-- Check for super bloom creation (if not already super)
	if not isSuper and BloomMath.CheckSuperBloom(center, GameManager.ActiveBlooms, GameConstants) then
		local superCenter = BloomMath.GetSuperBloomCenter(center, GameManager.ActiveBlooms, GameConstants)
		task.delay(0.1, function()
			GameManager.CreateBloom(superCenter, creator, true)
			-- Remove overlapping normal blooms
			for bid, b in pairs(GameManager.ActiveBlooms) do
				if not b.IsSuper and (b.Center - superCenter).Magnitude < (constants.Radius * 2) then
					GameManager.RemoveBloom(bid)
				end
			end
		end)
	end

	return id
end

function GameManager.RemoveBloom(id: number)
	local bloom = GameManager.ActiveBlooms[id]
	if bloom then
		GameManager.ActiveBlooms[id] = nil
		Network.Broadcast("OnBloomRemoved", id)
	end
end

function GameManager.GetActiveBlooms()
	return GameManager.ActiveBlooms
end

function GameManager.CleanupExpiredBlooms()
	local now = tick()
	for id, bloom in pairs(GameManager.ActiveBlooms) do
		if bloom.EndTime <= now then
			GameManager.RemoveBloom(id)
		end
	end
end

-- ========== MATCH FLOW ==========
function GameManager.StartMatch(players: { Player }, mapName: string)
	if GameManager.MatchState ~= "Waiting" and GameManager.MatchState ~= "Intermission" then
		warn("[GameManager] Cannot start match in state:", GameManager.MatchState)
		return
	end

	SetupTeams()
	LoadMap(mapName)

	-- Assign players to teams
	Utility.Shuffle(players)
	for i, player in ipairs(players) do
		local team = i <= GameConstants.Match.TeamSize and GameManager.TeamA or GameManager.TeamB
		player.Team = team
		PlayerData.LoadPlayerData(player)
		CombatSystem.InitializePlayer(player)
		EssenceSystem.InitializePlayer(player)
	end

	GameManager.Score = { TeamA = 0, TeamB = 0 }
	GameManager.ActiveBlooms = {}
	GameManager.BloomIdCounter = 0

	SetMatchState("Starting")
	task.wait(GameConstants.Match.PreMatchDelay)

	GameManager.MatchStartTime = tick()
	SetMatchState("InProgress")

	-- Start match loop
	task.spawn(GameManager.MatchLoop)
	Utility.Log("Match started on", mapName, "with", #players, "players")
end

function GameManager.MatchLoop()
	while GameManager.MatchState == "InProgress" or GameManager.MatchState == "SuddenDeath" do
		local timeRemaining = GameManager.GetTimeRemaining()

		-- Check for sudden death
		if timeRemaining <= 0 and GameManager.MatchState == "InProgress" then
			if GameManager.Score.TeamA == GameManager.Score.TeamB then
				SetMatchState("SuddenDeath")
				GameManager.MatchStartTime = tick() -- Reset timer for sudden death
				Network.Broadcast("OnMatchStateChanged", "SuddenDeath", GameManager.GetMatchInfo())
			else
				GameManager.EndMatch()
				break
			end
		end

		-- Check for sudden death end
		if timeRemaining <= 0 and GameManager.MatchState == "SuddenDeath" then
			GameManager.EndMatch()
			break
		end

		-- Cleanup expired blooms
		GameManager.CleanupExpiredBlooms()

		-- Update score for Bloom Ball mode
		if GameManager.BloomCore then
			GameManager.UpdateBloomBallScore()
		end

		task.wait(1)
	end
end

function GameManager.UpdateBloomBallScore()
	-- Check which team controls the bloom core
	local corePos = GameManager.BloomCore.Position
	local radius = 15

	local teamAInZone = 0
	local teamBInZone = 0

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local dist = (player.Character.HumanoidRootPart.Position - corePos).Magnitude
			if dist <= radius then
				if player.Team == GameManager.TeamA then
					teamAInZone += 1
				elseif player.Team == GameManager.TeamB then
					teamBInZone += 1
				end
			end
		end
	end

	-- Score point for team with majority in zone
	if teamAInZone > teamBInZone and teamAInZone > 0 then
		GameManager.AddScore("TeamA", 1)
	elseif teamBInZone > teamAInZone and teamBInZone > 0 then
		GameManager.AddScore("TeamB", 1)
	end
end

function GameManager.AddScore(teamName: string, amount: number)
	GameManager.Score[teamName] = (GameManager.Score[teamName] or 0) + amount
	Network.Broadcast("OnScoreUpdate", GameManager.Score)
end

function GameManager.EndMatch()
	if GameManager.MatchState == "Ended" then return end

	local winningTeam = GameManager.Score.TeamA > GameManager.Score.TeamB and "TeamA"
		or GameManager.Score.TeamB > GameManager.Score.TeamA and "TeamB"
		or nil

	SetMatchState("Ended")
	Network.Broadcast("OnMatchEnd", winningTeam, GameManager.Score, GameManager.GetMatchInfo())

	-- Award XP and update stats
	for _, player in ipairs(Players:GetPlayers()) do
		local isWinner = winningTeam and player.Team and player.Team.Name == winningTeam
		PlayerData.UpdateMatchStats(player, isWinner, GameManager.Score)
	end

	-- Cleanup
	task.wait(GameConstants.Match.PostMatchDelay)
	GameManager.CleanupMatch()
	SetMatchState("Intermission")

	-- Return to matchmaking
	task.wait(5)
	SetMatchState("Waiting")
	Matchmaking.CheckQueue()
end

function GameManager.CleanupMatch()
	-- Reset players
	for _, player in ipairs(Players:GetPlayers()) do
		player.Team = nil
		if player.Character then
			player:LoadCharacter()
		end
	end

	-- Clear blooms
	GameManager.ActiveBlooms = {}
	GameManager.BloomIdCounter = 0

	-- Clear map
	local mapsFolder = Workspace:FindFirstChild("Maps")
	if mapsFolder then mapsFolder:Destroy() end
	local spawnsFolder = Workspace:FindFirstChild("Spawns")
	if spawnsFolder then spawnsFolder:Destroy() end
	local petalsFolder = Workspace:FindFirstChild("PetalSpawns")
	if petalsFolder then petalsFolder:Destroy() end
end

-- ========== NETWORK HANDLERS ==========
Network.OnServerInvoke("RequestMatchData", function(player: Player)
	return GameManager.GetMatchInfo()
end)

-- ========== INITIALIZATION ==========
SetupTeams()
Utility.Log("GameManager initialized")

return GameManager