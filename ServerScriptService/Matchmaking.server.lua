--[[
	Matchmaking.server.lua
	Handles player queue, team balancing, and match creation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConstants = require(ReplicatedStorage.Modules.GameConstants)
local Network = require(ReplicatedStorage.Modules.Network)
local Utility = require(ReplicatedStorage.Modules.Utility)
local GameManager = require(script.Parent.GameManager)
local PlayerData = require(script.Parent.PlayerData)

local Matchmaking = {}

-- ========== QUEUE STATE ==========
type QueueEntry = {
	Player: Player,
	JoinTime: number,
	PreferredMode: string?,
	Elo: number,
}

local Queue = {} -- [Player] = QueueEntry
local QueueList = {} -- Ordered list for matchmaking
local MIN_PLAYERS = GameConstants.Match.MaxPlayers
local MAX_WAIT_TIME = 60 -- seconds before forcing match with fewer players
local BALANCE_THRESHOLD = 200 -- Max Elo difference for balanced teams

-- ========== QUEUE MANAGEMENT ==========
Network.OnServerInvoke("RequestJoinQueue", function(player: Player, mode: string?)
	if Queue[player] then
		return false, "Already in queue"
	end

	if GameManager.MatchState ~= "Waiting" and GameManager.MatchState ~= "Intermission" then
		return false, "Match in progress"
	end

	local profile = PlayerData.GetProfile(player)
	local entry: QueueEntry = {
		Player = player,
		JoinTime = tick(),
		PreferredMode = mode or "BloomBall",
		Elo = profile.Stats.Elo,
	}

	Queue[player] = entry
	table.insert(QueueList, player)

	Network.FireClient(player, "OnQueueJoined", #QueueList, entry.PreferredMode)
	Utility.Log(player.Name, "joined queue. Queue size:", #QueueList)

	CheckQueue()
	return true, "Joined queue"
end)

Network.OnServerInvoke("RequestLeaveQueue", function(player: Player)
	if not Queue[player] then
		return false, "Not in queue"
	end

	Queue[player] = nil
	Utility.RemoveFromArray(QueueList, player)

	Network.FireClient(player, "OnQueueLeft")
	Utility.Log(player.Name, "left queue. Queue size:", #QueueList)

	return true, "Left queue"
end)

function Utility.RemoveFromArray(arr: { any }, value: any)
	for i, v in ipairs(arr) do
		if v == value then
			table.remove(arr, i)
			return true
		end
	end
	return false
end

-- ========== MATCHMAKING LOGIC ==========
function Matchmaking.CheckQueue()
	if GameManager.MatchState ~= "Waiting" and GameManager.MatchState ~= "Intermission" then
		return
	end

	if #QueueList < 2 then return end -- Need at least 2 players

	-- Check if we have enough for a full match or timeout
	local oldestEntry = Queue[QueueList[1]]
	local waitTime = tick() - oldestEntry.JoinTime
	local canStartFull = #QueueList >= MIN_PLAYERS
	local canStartPartial = waitTime >= MAX_WAIT_TIME and #QueueList >= 4

	if not canStartFull and not canStartPartial then
		-- Update queue position for all players
		for i, player in ipairs(QueueList) do
			Network.FireClient(player, "OnQueueUpdate", i, #QueueList, waitTime)
		end
		return
	end

	-- Select players for match
	local selectedPlayers = Matchmaking.SelectPlayers(canStartFull and MIN_PLAYERS or #QueueList)
	if #selectedPlayers < 4 then return end -- Minimum 2v2

	-- Remove from queue
	for _, player in ipairs(selectedPlayers) do
		Queue[player] = nil
	end
	Utility.Shuffle(QueueList) -- Will be rebuilt

	-- Start match
	local mapName = GameConstants.Match.MapRotation[math.random(#GameConstants.Match.MapRotation)]
	GameManager.StartMatch(selectedPlayers, mapName)

	Utility.Log("Starting match with", #selectedPlayers, "players on", mapName)
end

function Matchmaking.SelectPlayers(count: number): { Player }
	-- Sort by Elo for balanced teams
	table.sort(QueueList, function(a, b)
		return Queue[a].Elo < Queue[b].Elo
	end)

	local selected = {}
	for i = 1, math.min(count, #QueueList) do
		table.insert(selected, QueueList[i])
	end

	return selected
end

function Matchmaking.CreateBalancedTeams(players: { Player }): ({ Player }, { Player })
	-- Sort by Elo
	table.sort(players, function(a, b)
		local profileA = PlayerData.GetProfile(a)
		local profileB = PlayerData.GetProfile(b)
		return profileA.Stats.Elo > profileB.Stats.Elo
	end)

	local teamA, teamB = {}, {}
	local eloA, eloB = 0, 0

	for _, player in ipairs(players) do
		local profile = PlayerData.GetProfile(player)
		local elo = profile.Stats.Elo

		if eloA <= eloB then
			table.insert(teamA, player)
			eloA += elo
		else
			table.insert(teamB, player)
			eloB += elo
		end
	end

	return teamA, teamB
end

-- ========== QUEUE MONITORING ==========
task.spawn(function()
	while true do
		task.wait(5)
		Matchmaking.CheckQueue()
	end
end)

-- ========== PLAYER DISCONNECT ==========
Players.PlayerRemoving:Connect(function(player)
	if Queue[player] then
		Queue[player] = nil
		Utility.RemoveFromArray(QueueList, player)
	end
end)

Utility.Log("Matchmaking initialized")
return Matchmaking