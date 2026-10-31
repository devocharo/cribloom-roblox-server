--[[
	EssenceSystem.server.lua
	Manages essence resource, ultimate charging, and essence-based abilities.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConstants = require(ReplicatedStorage.Modules.GameConstants)
local Network = require(ReplicatedStorage.Modules.Network)
local Utility = require(ReplicatedStorage.Modules.Utility)
local PlayerData = require(script.Parent.PlayerData)

local EssenceSystem = {}

-- ========== STATE ==========
local PlayerEssence = {} -- [Player] = { Current, LastGainTime, UltimateReady, UltimateCooldownEnd }

-- ========== INITIALIZATION ==========
function EssenceSystem.InitializePlayer(player: Player)
	PlayerEssence[player] = {
		Current = 0,
		LastGainTime = tick(),
		UltimateReady = false,
		UltimateCooldownEnd = 0,
	}
	Network.FireClient(player, "OnEssenceChanged", 0, false)
end

function EssenceSystem.CleanupPlayer(player: Player)
	PlayerEssence[player] = nil
end

-- ========== ESSENCE GAIN ==========
function EssenceSystem.GainEssence(player: Player, amount: number)
	local data = PlayerEssence[player]
	if not data then return end

	local now = tick()
	data.Current = math.min(GameConstants.Essence.MaxEssence, data.Current + amount)
	data.LastGainTime = now

	-- Check for ultimate ready
	if not data.UltimateReady and data.Current >= GameConstants.Essence.MaxEssence then
		data.UltimateReady = true
		Network.FireClient(player, "OnUltimateReady")
	end

	Network.FireClient(player, "OnEssenceChanged", data.Current, data.UltimateReady)
end

function EssenceSystem.GetEssence(player: Player): number
	local data = PlayerEssence[player]
	return data and data.Current or 0
end

function EssenceSystem.GetEssencePercent(player: Player): number
	return EssenceSystem.GetEssence(player) / GameConstants.Essence.MaxEssence
end

-- ========== ESSENCE DECAY ==========
function EssenceSystem.UpdateEssenceDecay()
	local now = tick()
	for player, data in pairs(PlayerEssence) do
		if player and player.Parent then
			-- Decay when not in combat (no essence gain for 5 seconds)
			if now - data.LastGainTime > 5 and data.Current > 0 then
				local decay = GameConstants.Essence.EssenceDecayPerSecond * (1/30) -- Per frame at 30Hz
				data.Current = math.max(0, data.Current - decay)

				if data.Current < GameConstants.Essence.MaxEssence then
					data.UltimateReady = false
				end

				Network.FireClient(player, "OnEssenceChanged", data.Current, data.UltimateReady)
			end

			-- Ultimate cooldown
			if data.UltimateCooldownEnd > 0 and now >= data.UltimateCooldownEnd then
				data.UltimateCooldownEnd = 0
			end
		end
	end
end

-- Run decay at 30Hz
RunService.Heartbeat:Connect(function()
	EssenceSystem.UpdateEssenceDecay()
end)

-- ========== ULTIMATE MANAGEMENT ==========
function EssenceSystem.UseUltimate(player: Player)
	local data = PlayerEssence[player]
	if not data or not data.UltimateReady then return false end

	data.Current = 0
	data.UltimateReady = false
	data.UltimateCooldownEnd = tick() + GameConstants.Essence.UltimateCooldown

	Network.FireClient(player, "OnEssenceChanged", 0, false)
	Network.FireClient(player, "OnUltimateCooldown", GameConstants.Essence.UltimateCooldown)

	return true
end

function EssenceSystem.IsUltimateReady(player: Player): boolean
	local data = PlayerEssence[player]
	return data and data.UltimateReady or false
end

function EssenceSystem.GetUltimateCooldownRemaining(player: Player): number
	local data = PlayerEssence[player]
	if not data then return 0 end
	return math.max(0, data.UltimateCooldownEnd - tick())
end

-- ========== PETAL COLLECTION ==========
Network.OnServerEvent("RequestPetalCollect", function(player: Player, petalId: number)
	-- Petals are spawned by Super Blooms
	-- Server validates collection
	EssenceSystem.GainEssence(player, 10)
	PlayerData.IncrementStat(player, "PetalsCollected")
	Network.Broadcast("OnPetalCollected", player, petalId)
end)

-- ========== ESSENCE EVENTS FOR EXTERNAL SYSTEMS ==========
function EssenceSystem.OnDamageDealtInBloom(player: Player, damage: number)
	EssenceSystem.GainEssence(player, damage * GameConstants.Essence.EssencePerDamageInBloom)
end

function EssenceSystem.OnHealInBloom(player: Player, amount: number)
	EssenceSystem.GainEssence(player, amount * GameConstants.Essence.EssencePerHealInBloom)
end

function EssenceSystem.OnSuperBloomTriggered(player: Player)
	EssenceSystem.GainEssence(player, GameConstants.Essence.EssencePerSuperBloomTrigger)
	PlayerData.IncrementStat(player, "TotalSuperBlooms")
end

function EssenceSystem.OnKill(player: Player)
	EssenceSystem.GainEssence(player, GameConstants.Essence.EssencePerKill)
end

-- ========== CLEANUP ==========
Players.PlayerRemoving:Connect(function(player)
	EssenceSystem.CleanupPlayer(player)
end)

Utility.Log("EssenceSystem initialized")
return EssenceSystem