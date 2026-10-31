--[[
	CombatSystem.server.lua
	Server-authoritative combat: damage, crits, bloom triggers, knockback.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local GameConstants = require(ReplicatedStorage.Modules.GameConstants)
local Network = require(ReplicatedStorage.Modules.Network)
local Utility = require(ReplicatedStorage.Modules.Utility)
local BloomMath = require(ReplicatedStorage.Modules.BloomMath)
local GameManager = require(script.Parent.GameManager)
local EssenceSystem = require(script.Parent.EssenceSystem)
local PlayerData = require(script.Parent.PlayerData)

local CombatSystem = {}

-- ========== PLAYER COMBAT STATE ==========
local PlayerCombatState = {} -- [Player] = { LastAttack, ComboCount, IsAttacking, DashCooldown, etc }

-- ========== INITIALIZATION ==========
function CombatSystem.InitializePlayer(player: Player)
	PlayerCombatState[player] = {
		LastAttackTime = 0,
		ComboCount = 0,
		IsAttacking = false,
		DashCooldown = 0,
		LastDashTime = 0,
		InvulnerableUntil = 0,
		CurrentWeapon = "PetalRapier",
		CritChanceBonus = 0,
		DamageBonus = 0,
	}
end

function CombatSystem.CleanupPlayer(player: Player)
	PlayerCombatState[player] = nil
end

-- ========== DAMAGE CALCULATION ==========
function CombatSystem.CalculateDamage(attacker: Player, victim: Player, weaponName: string, isCrit: boolean, hitPosition: Vector3): number
	local attackerState = PlayerCombatState[attacker]
	local constants = GameConstants.Combat
	local weaponData = GameConstants.Weapons[weaponName] or GameConstants.Weapons.PetalRapier

	local baseDamage = weaponData.Damage + (attackerState.DamageBonus or 0)
	local damage = baseDamage

	-- Critical hit
	if isCrit then
		damage = damage * constants.CritMultiplier
	end

	-- Bloom damage bonus
	local bloomMultiplier = BloomMath.GetDamageMultiplier(hitPosition, GameManager.GetActiveBlooms(), GameConstants)
	damage = damage * bloomMultiplier

	-- Headshot check (simplified - would need raycast in real implementation)
	-- For now, random headshot chance
	if math.random() < 0.1 then
		damage = damage * constants.HeadshotMultiplier
		isCrit = true -- Headshots count as crits for bloom
	end

	return math.floor(damage), isCrit, bloomMultiplier > 1
end

-- ========== ATTACK HANDLING ==========
Network.OnServerEvent("RequestAttack", function(player: Player, weaponName: string, targetPosition: Vector3, clientTime: number)
	if not CombatSystem.ValidateAttack(player, clientTime) then return end

	local state = PlayerCombatState[player]
	state.LastAttackTime = tick()
	state.IsAttacking = true

	-- Find targets in range
	local weaponData = GameConstants.Weapons[weaponName] or GameConstants.Weapons.PetalRapier
	local range = weaponData.Range
	local targets = CombatSystem.GetTargetsInRange(player, targetPosition, range)

	if #targets == 0 then
		state.IsAttacking = false
		return
	end

	-- Determine crit
	local critChance = weaponData.CritChance + (state.CritChanceBonus or 0)
	local isCrit = math.random() < critChance

	-- Process each target
	for _, target in ipairs(targets) do
		if target == player then continue end -- No self-damage

		local hitPos = target.Character and target.Character:FindFirstChild("HumanoidRootPart") and target.Character.HumanoidRootPart.Position or targetPosition
		local damage, finalCrit, inBloom = CombatSystem.CalculateDamage(player, target, weaponName, isCrit, hitPos)

		CombatSystem.ApplyDamage(player, target, damage, finalCrit, inBloom, hitPos, weaponName)
	end

	-- Combo system
	if #targets > 0 then
		state.ComboCount += 1
		if state.ComboCount >= 3 then
			-- Combo bonus: next attack has increased crit chance
			state.CritChanceBonus = 0.1
		end
	else
		state.ComboCount = 0
		state.CritChanceBonus = 0
	end

	state.IsAttacking = false
end)

function CombatSystem.ValidateAttack(player: Player, clientTime: number): boolean
	local state = PlayerCombatState[player]
	if not state then return false end

	-- Basic rate limiting
	local weaponData = GameConstants.Weapons[state.CurrentWeapon] or GameConstants.Weapons.PetalRapier
	if tick() - state.LastAttackTime < weaponData.FireRate * 0.9 then
		return false -- Too fast
	end

	-- Check if player is alive
	if not player.Character or not player.Character:FindFirstChild("Humanoid") or player.Character.Humanoid.Health <= 0 then
		return false
	end

	return true
end

function CombatSystem.GetTargetsInRange(attacker: Player, attackPosition: Vector3, range: number): { Player }
	local targets = {}
	local attackerChar = attacker.Character
	if not attackerChar or not attackerChar:FindFirstChild("HumanoidRootPart") then return targets end

	for _, player in ipairs(Players:GetPlayers()) do
		if player == attacker then continue end
		if not player.Character then continue end
		if not player.Character:FindFirstChild("HumanoidRootPart") then continue end
		if player.Character.Humanoid.Health <= 0 then continue end

		-- Team check (no friendly fire)
		if player.Team == attacker.Team then continue end

		local distance = (player.Character.HumanoidRootPart.Position - attackPosition).Magnitude
		if distance <= range then
			table.insert(targets, player)
		end
	end

	return targets
end

-- ========== APPLY DAMAGE ==========
function CombatSystem.ApplyDamage(attacker: Player, victim: Player, damage: number, isCrit: boolean, inBloom: boolean, hitPosition: Vector3, weaponName: string)
	local victimChar = victim.Character
	if not victimChar then return end

	local humanoid = victimChar:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Invulnerability frames
	local victimState = PlayerCombatState[victim]
	if victimState and tick() < (victimState.InvulnerableUntil or 0) then
		return
	end

	-- Apply damage
	humanoid:TakeDamage(damage)

	-- Set invulnerability
	if victimState then
		victimState.InvulnerableUntil = tick() + GameConstants.Combat.InvulnerabilityFrames
	end

	-- Knockback
	CombatSystem.ApplyKnockback(attacker, victim, damage)

	-- Track stats
	PlayerData.IncrementStat(attacker, "TotalDamageDealt", damage)
	PlayerData.IncrementStat(victim, "TotalDamageTaken", damage)

	-- Essence gain
	if inBloom then
		EssenceSystem.GainEssence(attacker, damage * GameConstants.Essence.EssencePerDamageInBloom)
	end

	-- Bloom trigger on crit
	if isCrit then
		local bloomId = GameManager.CreateBloom(hitPosition, attacker, false)
		PlayerData.IncrementStat(attacker, "TotalBloomsTriggered")

		-- Essence for creating bloom
		EssenceSystem.GainEssence(attacker, GameConstants.Essence.EssencePerDamageInBloom * 5)
	end

	-- Visual feedback
	Network.FireClient(victim, "OnPlayerHit", damage, isCrit, inBloom, hitPosition)
	Network.Broadcast("OnDamageDealt", attacker, victim, damage, isCrit, inBloom, hitPosition)

	-- Check for kill
	if humanoid.Health <= 0 then
		CombatSystem.HandleKill(attacker, victim, weaponName)
	end
end

function CombatSystem.ApplyKnockback(attacker: Player, victim: Player, damage: number)
	local attackerChar = attacker.Character
	local victimChar = victim.Character
	if not attackerChar or not victimChar then return end

	local attackerRoot = attackerChar:FindFirstChild("HumanoidRootPart")
	local victimRoot = victimChar:FindFirstChild("HumanoidRootPart")
	if not attackerRoot or not victimRoot then return end

	local direction = (victimRoot.Position - attackerRoot.Position).Unit
	direction = Vector3.new(direction.X, 0, direction.Y) -- Horizontal only

	local force = GameConstants.Combat.KnockbackForce * (damage / 25)
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Velocity = direction * force
	bodyVelocity.MaxForce = Vector3.new(4000, 0, 4000)
	bodyVelocity.Parent = victimRoot
	Debris:AddItem(bodyVelocity, 0.1)
end

function CombatSystem.HandleKill(killer: Player, victim: Player, weaponName: string)
	PlayerData.IncrementStat(killer, "Kills")
	PlayerData.IncrementStat(victim, "Deaths")

	-- Essence for kill
	EssenceSystem.GainEssence(killer, GameConstants.Essence.EssencePerKill)

	-- Reset victim
	victim:LoadCharacter()

	-- Notify
	Network.Broadcast("OnPlayerDeath", killer, victim, weaponName)

	-- Check match end conditions (for elimination mode)
	GameManager.CheckEliminationWin()
end

-- ========== ABILITY SYSTEM ==========
Network.OnServerEvent("RequestAbility", function(player: Player, abilityName: string, ...)
	local state = PlayerCombatState[player]
	if not state then return end

	local classData = GameConstants.Classes[PlayerData.GetProfile(player).Loadout.SelectedClass]
	if not classData then return end

	if abilityName == classData.Ability then
		CombatSystem.ActivateAbility(player, abilityName, ...)
	end
end)

function CombatSystem.ActivateAbility(player: Player, abilityName: string, ...)
	local args = { ... }
	local char = player.Character
	if not char then return end

	if abilityName == "BloomBurst" then
		-- AoE bloom around self
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			GameManager.CreateBloom(root.Position, player, false)
			-- Damage nearby enemies
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and p.Team ~= player.Team and p.Character then
					local pRoot = p.Character:FindFirstChild("HumanoidRootPart")
					if pRoot and (pRoot.Position - root.Position).Magnitude <= 15 then
						CombatSystem.ApplyDamage(player, p, 30, true, true, pRoot.Position, "Ability")
					end
				end
			end
		end

	elseif abilityName == "PiercingBloom" then
		-- Line bloom in aim direction
		local root = char:FindFirstChild("HumanoidRootPart")
		local direction = args[1] or Vector3.new(0, 0, -1)
		if root then
			for i = 1, 5 do
				local pos = root.Position + direction * (i * 8)
				GameManager.CreateBloom(pos, player, false)
			end
		end

	elseif abilityName == "NurturingBloom" then
		-- Heal allies in bloom
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local bloomId = GameManager.CreateBloom(root.Position, player, false)
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Team == player.Team and p.Character then
					local pRoot = p.Character:FindFirstChild("HumanoidRootPart")
					if pRoot and (pRoot.Position - root.Position).Magnitude <= 12 then
						local humanoid = p.Character:FindFirstChild("Humanoid")
						if humanoid then
							humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 25)
							PlayerData.IncrementStat(player, "TotalHealingDone", 25)
							EssenceSystem.GainEssence(player, 25 * GameConstants.Essence.EssencePerHealInBloom)
						end
					end
				end
			end
		end

	elseif abilityName == "ShadowBloom" then
		-- Invisibility + guaranteed crit next hit
		local state = PlayerCombatState[player]
		state.CritChanceBonus = 1.0 -- 100% crit next hit
		-- Invisibility would be handled client-side
		Network.FireClient(player, "OnShadowBloomActivated")
	end
end

-- ========== ULTIMATE SYSTEM ==========
Network.OnServerEvent("RequestUltimate", function(player: Player, ultimateName: string, ...)
	local essence = EssenceSystem.GetEssence(player)
	if essence < GameConstants.Essence.MaxEssence then return end

	local classData = GameConstants.Classes[PlayerData.GetProfile(player).Loadout.SelectedClass]
	if not classData or ultimateName ~= classData.Ultimate then return end

	EssenceSystem.UseUltimate(player)
	CombatSystem.ActivateUltimate(player, ultimateName, ...)
end)

function CombatSystem.ActivateUltimate(player: Player, ultimateName: string, ...)
	local args = { ... }
	local char = player.Character
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	Network.Broadcast("OnUltimateActivated", player, ultimateName)

	if ultimateName == "PetalStorm" then
		-- Massive AoE bloom rain
		for i = 1, 20 do
			task.delay(i * 0.1, function()
				local pos = root.Position + Vector3.new(
					math.random(-30, 30),
					20,
					math.random(-30, 30)
				)
				GameManager.CreateBloom(pos, player, true)
			end)
		end

	elseif ultimateName == "ThornVolley" then
		-- Massive multi-shot
		local direction = args[1] or Vector3.new(0, 0, -1)
		for i = -2, 2 do
			local angle = math.rad(i * 15)
			local dir = Vector3.new(
				direction.X * math.cos(angle) - direction.Z * math.sin(angle),
				0,
				direction.X * math.sin(angle) + direction.Z * math.cos(angle)
			)
			-- Fire projectile (handled by client visuals)
			Network.FireAllExcept(player, "OnThornVolleyShot", player, root.Position, dir)
		end

	elseif ultimateName == "EternalGarden" then
		-- Persistent massive bloom zone
		local bloomId = GameManager.CreateBloom(root.Position, player, true)
		-- Make it last longer
		local bloom = GameManager.GetActiveBlooms()[bloomId]
		if bloom then
			bloom.EndTime = tick() + 20
			bloom.Radius = 30
		end

	elseif ultimateName == "BloomAssassination" then
		-- Teleport to marked target, massive damage
		local targetPlayer = args[1]
		if targetPlayer and targetPlayer.Character then
			local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				-- Teleport behind target
				local backPos = targetRoot.Position - targetRoot.CFrame.LookVector * 4
				root.CFrame = CFrame.new(backPos, targetRoot.Position)
				CombatSystem.ApplyDamage(player, targetPlayer, 200, true, true, targetRoot.Position, "Ultimate")
			end
		end
	end

	PlayerData.IncrementStat(player, "UltimatesUsed")
end

-- ========== DASH SYSTEM ==========
Network.OnServerEvent("RequestDash", function(player: Player, direction: Vector3)
	local state = PlayerCombatState[player]
	if not state then return end

	local now = tick()
	if now - state.LastDashTime < GameConstants.Movement.DashCooldown then return end

	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChild("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return end

	state.LastDashTime = now

	-- Check if dashing through bloom
	local inBloom = false
	for _, bloom in pairs(GameManager.GetActiveBlooms()) do
		if bloom.EndTime > now and (root.Position - bloom.Center).Magnitude < bloom.Radius then
			inBloom = true
			break
		end
	end

	if inBloom and GameConstants.Movement.DashThroughBloomRefresh then
		state.LastDashTime = now - GameConstants.Movement.DashCooldown * 0.5 -- Partial refresh
	end

	-- Apply dash velocity
	local dashVelocity = Instance.new("BodyVelocity")
	dashVelocity.Velocity = direction.Unit * GameConstants.Movement.DashSpeed
	dashVelocity.MaxForce = Vector3.new(10000, 0, 10000)
	dashVelocity.Parent = root
	Debris:AddItem(dashVelocity, GameConstants.Movement.DashDuration)

	-- Invulnerability during dash
	if GameConstants.Movement.DashInvulnerability then
		state.InvulnerableUntil = now + GameConstants.Movement.DashDuration + 0.1
	end

	Network.FireClient(player, "OnDashActivated", direction, inBloom)
end)

-- ========== CLEANUP ON DEATH ==========
Players.PlayerRemoving:Connect(function(player)
	CombatSystem.CleanupPlayer(player)
end)

Utility.Log("CombatSystem initialized")
return CombatSystem