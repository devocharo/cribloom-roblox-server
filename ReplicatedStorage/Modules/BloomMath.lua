--[[
	BloomMath.lua
	Shared mathematical utilities for bloom calculations (client + server).
]]

local BloomMath = {}

-- Check if a position is within a bloom zone
function BloomMath.IsInBloom(position: Vector3, bloomCenter: Vector3, bloomRadius: number): boolean
	return (position - bloomCenter).Magnitude <= bloomRadius
end

-- Get all bloom zones affecting a position
function BloomMath.GetActiveBloomsAt(position: Vector3, activeBlooms: { [number]: { Center: Vector3, Radius: number, EndTime: number, IsSuper: boolean } }): { { Center: Vector3, Radius: number, IsSuper: boolean } }
	local now = tick()
	local result = {}
	for _, bloom in pairs(activeBlooms) do
		if bloom.EndTime > now and BloomMath.IsInBloom(position, bloom.Center, bloom.Radius) then
			table.insert(result, { Center = bloom.Center, Radius = bloom.Radius, IsSuper = bloom.IsSuper })
		end
	end
	return result
end

-- Calculate damage multiplier based on overlapping blooms
function BloomMath.GetDamageMultiplier(position: Vector3, activeBlooms: { [number]: any }, constants: any): number
	local blooms = BloomMath.GetActiveBloomsAt(position, activeBlooms)
	if #blooms == 0 then return 1 end

	local superCount = 0
	local normalCount = 0
	for _, bloom in ipairs(blooms) do
		if bloom.IsSuper then
			superCount += 1
		else
			normalCount += 1
		end
	end

	if superCount >= constants.Bloom.MaxOverlapsForSuper then
		return 1 + constants.Bloom.SuperBloomDamageBonus
	elseif normalCount > 0 then
		return 1 + constants.Bloom.DamageBonus * normalCount
	end
	return 1
end

-- Check if position triggers a super bloom (overlapping blooms)
function BloomMath.CheckSuperBloom(newBloomCenter: Vector3, activeBlooms: { [number]: any }, constants: any): boolean
	local overlapCount = 0
	for _, bloom in pairs(activeBlooms) do
		if bloom.EndTime > tick() and not bloom.IsSuper then
			local distance = (newBloomCenter - bloom.Center).Magnitude
			if distance < (constants.Bloom.Radius * 2) then
				overlapCount += 1
				if overlapCount >= constants.Bloom.MaxOverlapsForSuper then
					return true
				end
			end
		end
	end
	return false
end

-- Calculate super bloom center (average of overlapping blooms)
function BloomMath.GetSuperBloomCenter(newBloomCenter: Vector3, activeBlooms: { [number]: any }, constants: any): Vector3
	local centers = { newBloomCenter }
	local count = 1
	for _, bloom in pairs(activeBlooms) do
		if bloom.EndTime > tick() and not bloom.IsSuper then
			local distance = (newBloomCenter - bloom.Center).Magnitude
			if distance < (constants.Bloom.Radius * 2) then
				table.insert(centers, bloom.Center)
				count += 1
			end
		end
	end

	local sum = Vector3.zero
	for _, center in ipairs(centers) do
		sum += center
	end
	return sum / count
end

-- Lerp utility for smooth visual transitions
function BloomMath.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * math.clamp(t, 0, 1)
end

function BloomMath.LerpVector3(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

-- Easing functions for bloom animations
function BloomMath.EaseOutQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end

function BloomMath.EaseInOutQuad(t: number): number
	if t < 0.5 then return 2 * t * t else return 1 - 2 * (1 - t) * (1 - t) end
end

function BloomMath.EaseOutElastic(t: number): number
	local c4 = (2 * math.pi) / 3
	if t == 0 then return 0 elseif t == 1 then return 1 end
	return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * c4) + 1
end

-- Color interpolation for bloom visuals
function BloomMath.LerpColor(c1: Color3, c2: Color3, t: number): Color3
	return Color3.new(
		BloomMath.Lerp(c1.R, c2.R, t),
		BloomMath.Lerp(c1.G, c2.G, t),
		BloomMath.Lerp(c1.B, c2.B, t)
	)
end

-- Generate bloom particle properties
function BloomMath.GenerateBloomParticles(isSuper: boolean, constants: any): { [string]: any }
	local base = constants.Bloom.ParticleColor
	if isSuper then
		return {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 0)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 200)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
			}),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.5, 1.5),
			Rate = 100,
			Speed = NumberRange.new(5, 15),
			SpreadAngle = Vector2.new(180, 180),
		}
	else
		return {
			Color = base,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.3, 1),
			Rate = 50,
			Speed = NumberRange.new(3, 10),
			SpreadAngle = Vector2.new(120, 120),
		}
	end
end

return BloomMath