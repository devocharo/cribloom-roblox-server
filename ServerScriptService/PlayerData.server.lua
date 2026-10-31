--[[
	PlayerData.server.lua
	DataStore persistence for player profiles, stats, and progression.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConstants = require(game.ReplicatedStorage.Modules.GameConstants)
local Network = require(game.ReplicatedStorage.Modules.Network)
local Utility = require(game.ReplicatedStorage.Modules.Utility)

local PlayerData = {}

-- ========== DATASTORES ==========
local PlayerProfiles = DataStoreService:GetDataStore("Critbloom_Profiles_v2")
local LeaderboardWins = DataStoreService:GetOrderedDataStore("Critbloom_Wins_v2")
local LeaderboardElo = DataStoreService:GetOrderedDataStore("Critbloom_Elo_v2")
local LeaderboardBlooms = DataStoreService:GetOrderedDataStore("Critbloom_Blooms_v2")

-- ========== DEFAULT PROFILE ==========
local DEFAULT_PROFILE = {
	Version = 2,
	LastUpdated = 0,
	Stats = {
		Wins = 0,
		Losses = 0,
		Elo = 1000,
		TotalMatches = 0,
		TotalBloomsTriggered = 0,
		TotalSuperBlooms = 0,
		TotalDamageDealt = 0,
		TotalDamageTaken = 0,
		TotalHealingDone = 0,
		Kills = 0,
		Deaths = 0,
		Assists = 0,
		PetalsCollected = 0,
		UltimatesUsed = 0,
		LongestWinStreak = 0,
		CurrentWinStreak = 0,
	},
	Progression = {
		Level = 1,
		XP = 0,
		TotalXP = 0,
	},
	Loadout = {
		SelectedClass = "BlossomDuelist",
		UnlockedClasses = { "BlossomDuelist" },
		EquippedCosmetics = {
			Trail = "None",
			BloomEffect = "Default",
			KOEffect = "Default",
			Emote = "Wave",
		},
		OwnedCosmetics = { "Default" },
	},
	Preferences = {
		Sensitivity = 1.0,
		InvertY = false,
		ShowDamageNumbers = true,
		ShowBloomIndicators = true,
		MusicVolume = 0.5,
		SFXVolume = 0.8,
	},
	SessionData = {
		MatchesThisSession = 0,
		BloomsThisSession = 0,
		SessionStartTime = 0,
	},
}

-- ========== CACHE ==========
local ProfileCache = {}
local SaveQueue = {}
local SAVE_INTERVAL = 30 -- seconds
local MAX_RETRIES = 3

-- ========== PROFILE MANAGEMENT ==========
function PlayerData.GetProfile(player: Player): { [string]: any }
	local cached = ProfileCache[player]
	if cached then return cached end

	-- Load from DataStore
	local success, data = pcall(function()
		return PlayerProfiles:GetAsync("Player_" .. player.UserId)
	end)

	if success and data then
		-- Merge with defaults for new fields
		data = Utility.DeepCopy(data)
		data = PlayerData.MergeWithDefaults(data)
	else
		data = Utility.DeepCopy(DEFAULT_PROFILE)
		data.SessionData.SessionStartTime = tick()
	end

	ProfileCache[player] = data
	return data
end

function PlayerData.MergeWithDefaults(profile: { [string]: any }): { [string]: any }
	local function merge(target, source)
		for key, value in pairs(source) do
			if target[key] == nil then
				target[key] = Utility.DeepCopy(value)
			elseif type(value) == "table" and type(target[key]) == "table" then
				merge(target[key], value)
			end
		end
	end

	local merged = Utility.DeepCopy(DEFAULT_PROFILE)
	merge(merged, profile)
	return merged
end

function PlayerData.SaveProfile(player: Player, force: boolean?)
	local profile = ProfileCache[player]
	if not profile then return end

	profile.LastUpdated = tick()

	if force or RunService:IsStudio() then
		PlayerData.SaveProfileAsync(player, profile)
	else
		SaveQueue[player] = profile
	end
end

function PlayerData.SaveProfileAsync(player: Player, profile: { [string]: any })
	local userId = player.UserId
	local key = "Player_" .. userId

	for attempt = 1, MAX_RETRIES do
		local success, err = pcall(function()
			PlayerProfiles:SetAsync(key, profile)
		end)

		if success then
			-- Update leaderboards
			PlayerData.UpdateLeaderboards(userId, profile)
			Utility.Log("Saved profile for", player.Name)
			return true
		else
			Utility.Warn("Save attempt", attempt, "failed for", player.Name, ":", err)
			task.wait(attempt * 0.5)
		end
	end

	Utility.Error("Failed to save profile for", player.Name, "after", MAX_RETRIES, "attempts")
	return false
end

function PlayerData.UpdateLeaderboards(userId: number, profile: { [string]: any })
	local stats = profile.Stats

	pcall(function()
		LeaderboardWins:SetAsync(userId, stats.Wins)
	end)

	pcall(function()
		LeaderboardElo:SetAsync(userId, stats.Elo)
	end)

	pcall(function()
		LeaderboardBlooms:SetAsync(userId, stats.TotalBloomsTriggered)
	end)
end

-- ========== PLAYER LIFECYCLE ==========
function PlayerData.LoadPlayerData(player: Player)
	local profile = PlayerData.GetProfile(player)
	profile.SessionData.SessionStartTime = tick()
	profile.SessionData.MatchesThisSession = 0
	profile.SessionData.BloomsThisSession = 0

	-- Send initial data to client
	Network.FireClient(player, "OnLeaderboardUpdate", PlayerData.GetLeaderboardData())
	Utility.Log("Loaded data for", player.Name, "- Level:", profile.Progression.Level, "Elo:", profile.Stats.Elo)
end

function PlayerData.UnloadPlayerData(player: Player)
	PlayerData.SaveProfile(player, true)
	ProfileCache[player] = nil
	SaveQueue[player] = nil
end

-- ========== STAT UPDATES ==========
function PlayerData.IncrementStat(player: Player, statName: string, amount: number?)
	local profile = PlayerData.GetProfile(player)
	amount = amount or 1
	profile.Stats[statName] = (profile.Stats[statName] or 0) + amount

	-- Session tracking
	if statName == "TotalBloomsTriggered" then
		profile.SessionData.BloomsThisSession += amount
	end
end

function PlayerData.UpdateMatchStats(player: Player, isWinner: boolean, score: { TeamA: number, TeamB: number })
	local profile = PlayerData.GetProfile(player)
	local stats = profile.Stats
	local prog = profile.Progression

	stats.TotalMatches += 1
	profile.SessionData.MatchesThisSession += 1

	if isWinner then
		stats.Wins += 1
		stats.CurrentWinStreak += 1
		stats.LongestWinStreak = math.max(stats.LongestWinStreak, stats.CurrentWinStreak)
		prog.XP += GameConstants.Progression.XPPerWin
	else
		stats.Losses += 1
		stats.CurrentWinStreak = 0
	end

	-- Elo calculation (simple)
	local eloChange = isWinner and 25 or -20
	stats.Elo = math.max(100, stats.Elo + eloChange)

	-- Level up check
	PlayerData.CheckLevelUp(player, profile)

	-- Queue save
	PlayerData.SaveProfile(player)
end

function PlayerData.CheckLevelUp(player: Player, profile: { [string]: any })
	local prog = profile.Progression
	while true do
		local xpNeeded = GameConstants.Progression.LevelCurve(prog.Level)
		if prog.XP >= xpNeeded and prog.Level < GameConstants.Progression.MaxLevel then
			prog.XP -= xpNeeded
			prog.Level += 1
			prog.TotalXP += xpNeeded
			Network.FireClient(player, "OnLevelUp", prog.Level)
			Utility.Log(player.Name, "leveled up to", prog.Level)
		else
			break
		end
	end
end

function PlayerData.AddXP(player: Player, amount: number)
	local profile = PlayerData.GetProfile(player)
	profile.Progression.XP += amount
	profile.Progression.TotalXP += amount
	PlayerData.CheckLevelUp(player, profile)
end

-- ========== CLASS / COSMETIC MANAGEMENT ==========
function PlayerData.SetSelectedClass(player: Player, className: string)
	local profile = PlayerData.GetProfile(player)
	if GameConstants.Classes[className] and Utility.TableContains(profile.Loadout.UnlockedClasses, className) then
		profile.Loadout.SelectedClass = className
		PlayerData.SaveProfile(player)
		return true
	end
	return false
end

function PlayerData.UnlockClass(player: Player, className: string)
	local profile = PlayerData.GetProfile(player)
	if GameConstants.Classes[className] and not Utility.TableContains(profile.Loadout.UnlockedClasses, className) then
		table.insert(profile.Loadout.UnlockedClasses, className)
		PlayerData.SaveProfile(player)
		Network.FireClient(player, "OnClassUnlocked", className)
		return true
	end
	return false
end

function PlayerData.EquipCosmetic(player: Player, category: string, cosmeticId: string)
	local profile = PlayerData.GetProfile(player)
	if Utility.TableContains(profile.Loadout.OwnedCosmetics, cosmeticId) then
		profile.Loadout.EquippedCosmetics[category] = cosmeticId
		PlayerData.SaveProfile(player)
		return true
	end
	return false
end

-- ========== LEADERBOARDS ==========
function PlayerData.GetLeaderboardData(): { [string]: any }
	local data = {}

	-- Top wins
	local winsPages = LeaderboardWins:GetSortedAsync(false, 10)
	local winsPage = winsPages:GetCurrentPage()
	data.TopWins = {}
	for i, entry in ipairs(winsPage) do
		table.insert(data.TopWins, { Rank = i, UserId = entry.key, Value = entry.value })
	end

	-- Top ELO
	local eloPages = LeaderboardElo:GetSortedAsync(false, 10)
	local eloPage = eloPages:GetCurrentPage()
	data.TopElo = {}
	for i, entry in ipairs(eloPage) do
		table.insert(data.TopElo, { Rank = i, UserId = entry.key, Value = entry.value })
	end

	-- Top Blooms
	local bloomPages = LeaderboardBlooms:GetSortedAsync(false, 10)
	local bloomPage = bloomPages:GetCurrentPage()
	data.TopBlooms = {}
	for i, entry in ipairs(bloomPage) do
		table.insert(data.TopBlooms, { Rank = i, UserId = entry.key, Value = entry.value })
	end

	return data
end

-- ========== AUTO-SAVE LOOP ==========
task.spawn(function()
	while true do
		task.wait(SAVE_INTERVAL)
		for player, profile in pairs(SaveQueue) do
			if player and player.Parent then
				PlayerData.SaveProfileAsync(player, profile)
				SaveQueue[player] = nil
			end
		end
	end
end)

-- ========== PLAYER EVENTS ==========
Players.PlayerRemoving:Connect(function(player)
	PlayerData.UnloadPlayerData(player)
end)

game:BindToClose(function()
	for player, profile in pairs(ProfileCache) do
		PlayerData.SaveProfileAsync(player, profile)
	end
	task.wait(2)
end)

Utility.Log("PlayerData system initialized")
return PlayerData