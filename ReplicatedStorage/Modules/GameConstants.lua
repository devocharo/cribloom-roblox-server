--[[
	GameConstants.lua
	Central configuration for Critbloom — tune gameplay without touching logic.
]]

local GameConstants = {}

-- ========== MATCH SETTINGS ==========
GameConstants.Match = {
	TeamSize = 4,
	MaxPlayers = 8,
	MatchDuration = 5 * 60, -- 5 minutes
	SuddenDeathDuration = 60,
	PreMatchDelay = 10,
	PostMatchDelay = 15,
	MapRotation = { "SakuraGardens", "MoonlitCourtyard", "CrystalGreenhouse", "TwilightArboretum" },
}

-- ========== COMBAT ==========
GameConstants.Combat = {
	BaseDamage = 25,
	CritChance = 0.15, -- 15% base crit chance
	CritMultiplier = 2.0,
	HeadshotMultiplier = 1.5,
	KnockbackForce = 50,
	InvulnerabilityFrames = 0.3, -- after taking damage
}

-- ========== BLOOM SYSTEM ==========
GameConstants.Bloom = {
	Radius = 12, -- studs
	Duration = 3, -- seconds
	DamageBonus = 0.25, -- 25% more damage in bloom
	SuperBloomRadius = 18,
	SuperBloomDuration = 4,
	SuperBloomDamageBonus = 0.5,
	SuperBloomSlow = 0.4, -- 40% slow
	MaxOverlapsForSuper = 2, -- how many blooms overlapping = super bloom
	VisualLifetime = 3.5,
	ParticleColor = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(138, 43, 226)), -- violet
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 20, 147)), -- deep pink
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 215, 0)), -- gold
	}),
}

-- ========== MOVEMENT ==========
GameConstants.Movement = {
	WalkSpeed = 16,
	SprintSpeed = 22,
	DashSpeed = 60,
	DashDuration = 0.25,
	DashCooldown = 3,
	DashInvulnerability = true,
	DashThroughBloomRefresh = true, -- dashing through bloom refreshes dash
	DoubleTapWindow = 0.3, -- seconds between taps for dash
}

-- ========== ESSENCE / ULTIMATE ==========
GameConstants.Essence = {
	MaxEssence = 100,
	EssencePerDamageInBloom = 0.5,
	EssencePerHealInBloom = 0.8,
	EssencePerSuperBloomTrigger = 15,
	EssencePerKill = 10,
	EssenceDecayPerSecond = 2, -- when not in combat
	UltimateCooldown = 120, -- seconds
	UltimateDuration = 8,
}

-- ========== CLASSES / LOADOUTS ==========
GameConstants.Classes = {
	["BlossomDuelist"] = {
		Name = "Blossom Duelist",
		Health = 100,
		Speed = 1.1,
		PrimaryWeapon = "PetalRapier",
		Ability = "BloomBurst", -- AoE bloom around self
		Ultimate = "PetalStorm", -- rain of petals in large area
		Description = "Agile melee, excels at close-range bloom chains",
	},
	["ThornArcher"] = {
		Name = "Thorn Archer",
		Health = 85,
		Speed = 1.0,
		PrimaryWeapon = "ThornBow",
		Ability = "PiercingBloom", -- shot creates bloom line
		Ultimate = "ThornVolley", -- massive multi-shot
		Description = "Ranged precision, creates bloom corridors",
	},
	["Gardener"] = {
		Name = "Gardener",
		Health = 130,
		Speed = 0.9,
		PrimaryWeapon = "VineStaff",
		Ability = "NurturingBloom", -- heals allies in bloom
		Ultimate = "EternalGarden", -- massive persistent bloom zone
		Description = "Support/tank, amplifies team bloom power",
	},
	["PetalAssassin"] = {
		Name = "Petal Assassin",
		Health = 75,
		Speed = 1.2,
		PrimaryWeapon = "TwinPetalDaggers",
		Ability = "ShadowBloom", -- invisibility + next hit guaranteed crit
		Ultimate = "BloomAssassination", -- teleport to marked target, massive damage
		Description = "High risk/reward, burst through blooms",
	},
}

-- ========== WEAPONS ==========
GameConstants.Weapons = {
	PetalRapier = { Damage = 22, FireRate = 0.4, Range = 6, CritChance = 0.2 },
	ThornBow = { Damage = 30, FireRate = 1.2, Range = 80, CritChance = 0.25 },
	VineStaff = { Damage = 18, FireRate = 0.8, Range = 10, CritChance = 0.1 },
	TwinPetalDaggers = { Damage = 15, FireRate = 0.25, Range = 5, CritChance = 0.3 },
}

-- ========== MAPS ==========
GameConstants.Maps = {
	SakuraGardens = {
		Size = Vector3.new(200, 50, 200),
		SpawnPoints = {
			TeamA = { Vector3.new(-80, 5, -80), Vector3.new(-80, 5, 80), Vector3.new(-60, 5, -60), Vector3.new(-60, 5, 60) },
			TeamB = { Vector3.new(80, 5, 80), Vector3.new(80, 5, -80), Vector3.new(60, 5, 60), Vector3.new(60, 5, -60) },
		},
		BloomCoreSpawn = Vector3.new(0, 10, 0),
		PetalSpawnZones = 8,
	},
	MoonlitCourtyard = {
		Size = Vector3.new(180, 40, 180),
		SpawnPoints = {
			TeamA = { Vector3.new(-70, 5, -70), Vector3.new(-70, 5, 70), Vector3.new(-50, 5, -50), Vector3.new(-50, 5, 50) },
			TeamB = { Vector3.new(70, 5, 70), Vector3.new(70, 5, -70), Vector3.new(50, 5, 50), Vector3.new(50, 5, -50) },
		},
		BloomCoreSpawn = Vector3.new(0, 8, 0),
		PetalSpawnZones = 6,
	},
	CrystalGreenhouse = {
		Size = Vector3.new(160, 60, 160),
		SpawnPoints = {
			TeamA = { Vector3.new(-60, 5, -60), Vector3.new(-60, 5, 60), Vector3.new(-40, 5, -40), Vector3.new(-40, 5, 40) },
			TeamB = { Vector3.new(60, 5, 60), Vector3.new(60, 5, -60), Vector3.new(40, 5, 40), Vector3.new(40, 5, -40) },
		},
		BloomCoreSpawn = Vector3.new(0, 12, 0),
		PetalSpawnZones = 10,
	},
	TwilightArboretum = {
		Size = Vector3.new(220, 50, 220),
		SpawnPoints = {
			TeamA = { Vector3.new(-90, 5, -90), Vector3.new(-90, 5, 90), Vector3.new(-70, 5, -70), Vector3.new(-70, 5, 70) },
			TeamB = { Vector3.new(90, 5, 90), Vector3.new(90, 5, -90), Vector3.new(70, 5, 70), Vector3.new(70, 5, -70) },
		},
		BloomCoreSpawn = Vector3.new(0, 15, 0),
		PetalSpawnZones = 12,
	},
}

-- ========== ECONOMY / PROGRESSION ==========
GameConstants.Progression = {
	XPPerMatch = 100,
	XPPerWin = 50,
	XPPerBloomTrigger = 5,
	XPPerSuperBloom = 20,
	LevelCurve = function(level) return 100 * (level ^ 1.5) end,
	MaxLevel = 100,
}

-- ========== NETWORK ==========
GameConstants.Network = {
	UpdateRate = 1/30, -- 30 Hz replication
	PredictionEnabled = true,
	LagCompensation = true,
	MaxRewindTime = 0.2,
}

return GameConstants