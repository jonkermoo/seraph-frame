--!strict
-- FrameGuard motion envelope: checks a client-owned hull's replicated motion on the server. Pure maths,
-- no Roblox types. Feed one sample per server tick; it returns the reasons the sample broke the envelope.
--
-- Speed: unused allowance (AllowedSpeed x time) banks up to PingSlackSeconds, so replication stalls followed
-- by a burst never read as speed. Distance beyond that draws on a dash budget that refills at the dash
-- recharge rate on ticks within the allowance; an empty budget is a "speed" strike.
-- Rise: height above the last support (ground, roof, another Frame) beyond a held leap is a "rise" strike.
-- Air: longer off any support than MaxAirSeconds is a "hover" strike.
-- Teleport: one tick moving more than TeleportDistance. Bounds: outside the map.

local FrameGuard = {}

export type Config = {
	AllowedSpeed: number,
	PingSlackSeconds: number,
	DashBudget: number,
	DashRegen: number,
	TeleportDistance: number,
	MaxRise: number,
	GroundedHeight: number,
	MaxAirSeconds: number,
	MapHalf: number,
	[string]: any,
}

export type State = {
	has: boolean,
	t: number,
	x: number,
	y: number,
	z: number,
	credit: number,
	dash: number,
	supportY: number,
	airTime: number,
	-- Stats for the prototype's log.
	peakTick: number, -- largest single-tick distance
	peakRise: number,
	peakAir: number,
	minDash: number, -- lowest dash budget seen
}

export type Sample = {
	t: number,
	x: number,
	y: number,
	z: number,
	-- Root height above its rest height over the support below; nil when nothing is below.
	height: number?,
}

export type Reason = "teleport" | "speed" | "rise" | "hover" | "bounds"

function FrameGuard.new(cfg: Config): State
	return {
		has = false,
		t = 0,
		x = 0,
		y = 0,
		z = 0,
		credit = cfg.AllowedSpeed * cfg.PingSlackSeconds,
		dash = cfg.DashBudget,
		supportY = 0,
		airTime = 0,
		peakTick = 0,
		peakRise = 0,
		peakAir = 0,
		minDash = cfg.DashBudget,
	}
end

-- Forget the motion history (board, exit, a server-driven move). Stats are kept.
function FrameGuard.reset(s: State, cfg: Config)
	s.has = false
	s.credit = cfg.AllowedSpeed * cfg.PingSlackSeconds
	s.dash = cfg.DashBudget
	s.airTime = 0
end

function FrameGuard.step(s: State, sample: Sample, cfg: Config): { Reason }
	local reasons: { Reason } = {}
	if not s.has then
		s.has = true
		s.t, s.x, s.y, s.z = sample.t, sample.x, sample.y, sample.z
		s.supportY = sample.y
		return reasons
	end
	local dt = sample.t - s.t
	if dt <= 0 then
		return reasons
	end
	local dx, dy, dz = sample.x - s.x, sample.y - s.y, sample.z - s.z
	s.t, s.x, s.y, s.z = sample.t, sample.x, sample.y, sample.z

	if math.abs(sample.x) > cfg.MapHalf or math.abs(sample.z) > cfg.MapHalf then
		table.insert(reasons, "bounds")
	end

	local d3 = math.sqrt(dx * dx + dy * dy + dz * dz)
	s.peakTick = math.max(s.peakTick, d3)
	if d3 > cfg.TeleportDistance then
		table.insert(reasons, "teleport")
		FrameGuard.reset(s, cfg)
		s.has = true
		s.supportY = sample.y
		return reasons
	end

	-- Speed (horizontal).
	local dh = math.sqrt(dx * dx + dz * dz)
	local cap = cfg.AllowedSpeed * cfg.PingSlackSeconds
	s.credit = math.min(cap, s.credit + cfg.AllowedSpeed * dt)
	local spend = math.min(dh, s.credit)
	s.credit -= spend
	local over = dh - spend
	-- The budget refills only on ticks within the allowance, so a steady speed hack cannot live on the refill.
	if over > 0 then
		s.dash -= over
	else
		s.dash = math.min(cfg.DashBudget, s.dash + cfg.DashRegen * dt)
	end
	s.minDash = math.min(s.minDash, s.dash)
	if s.dash < 0 then
		table.insert(reasons, "speed")
		s.dash = cfg.DashBudget
	end

	-- Rise and air time.
	local h = sample.height
	if h ~= nil and h <= cfg.GroundedHeight then
		s.supportY = sample.y
		s.airTime = 0
	else
		s.airTime += dt
		local rise = sample.y - s.supportY
		s.peakRise = math.max(s.peakRise, rise)
		if rise > cfg.MaxRise then
			table.insert(reasons, "rise")
			s.supportY = sample.y
		end
	end
	s.peakAir = math.max(s.peakAir, s.airTime)
	if s.airTime > cfg.MaxAirSeconds then
		table.insert(reasons, "hover")
		s.airTime = 0
	end
	return reasons
end

return FrameGuard
