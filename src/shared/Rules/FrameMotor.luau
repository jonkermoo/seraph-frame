--!strict
-- Frame motor: walk, sprint, skid, dash, leap and land as pure maths. No Roblox types: the pilot's client
-- feeds input and the ground height, then drives the hull with the velocity and yaw in the state.
-- Yaw in degrees, Roblox convention: 0 looks along -Z, positive turns left.
-- "Responsive start, heavy finish": accel is quick, the stop is long, dashes are instant.

local FrameCam = if typeof(script) == "Instance"
	then require((script :: any).Parent.FrameCam)
	else require("./FrameCam")

local FrameMotor = {}

export type Gait = "idle" | "walk" | "sprint" | "skid" | "dash" | "windup" | "air" | "land"

export type State = {
	vx: number,
	vy: number,
	vz: number,
	yaw: number,
	grounded: boolean,
	gait: Gait,
	airTime: number,
	airSpeed: number, -- horizontal speed air steering may reach
	dashCharge: number, -- 0..DashCharges, fractional while recharging
	dashLeft: number, -- seconds of dash left
	dashX: number,
	dashZ: number,
	dashEnded: boolean,
	windup: number, -- seconds crouched for a leap, -1 when not winding up
	landLeft: number, -- hard landing recovery left
	skidRate: number, -- deceleration latched when a stop starts (0 while not stopping)
	dashBuffer: number,
	leapBuffer: number,
	idleTurn: boolean,
}

export type Input = {
	moveX: number, -- strafe right, -1..1 (camera relative)
	moveY: number, -- forward, -1..1
	camYaw: number, -- degrees
	sprint: boolean,
	dashPressed: boolean, -- this step only
	leapPressed: boolean, -- this step only
	leapHeld: boolean,
}

export type Env = {
	-- Root height above its rest height over the ground below; nil when no ground is in reach.
	height: number?,
}

export type Config = {
	WalkSpeed: number,
	SprintSpeed: number,
	StrafeFactor: number,
	AccelSeconds: number,
	SprintAccelSeconds: number,
	StopSeconds: number,
	SprintStopSeconds: number,
	TurnDegPerSec: number,
	SprintTurnDegPerSec: number,
	TurnInPlaceDegPerSec: number,
	TwistDeg: number,
	Gravity: number,
	TerminalFallSpeed: number,
	GroundSnapHeight: number,
	StepDownHeight: number,
	GroundSnapRate: number,
	GroundSnapMaxSpeed: number,
	DashDistance: number,
	DashSeconds: number,
	DashCharges: number,
	DashRechargeSeconds: number,
	DashExitSpeed: number,
	DashMinInput: number,
	LeapHeight: number,
	LeapHoldBonus: number,
	LeapWindupSeconds: number,
	LeapWindupMaxSeconds: number,
	LeapWalkSpeed: number,
	LeapSprintSpeed: number,
	AirControl: number,
	HardLandAirSeconds: number,
	HardLandSeconds: number,
	BufferSeconds: number,
	BlockedRatio: number,
	BlockedMinSpeed: number,
	[string]: any,
}

function FrameMotor.new(yaw: number, charges: number): State
	return {
		vx = 0,
		vy = 0,
		vz = 0,
		yaw = yaw,
		grounded = true,
		gait = "idle",
		airTime = 0,
		airSpeed = 0,
		dashCharge = charges,
		dashLeft = 0,
		dashX = 0,
		dashZ = -1,
		dashEnded = false,
		windup = -1,
		landLeft = 0,
		skidRate = 0,
		dashBuffer = 0,
		leapBuffer = 0,
		idleTurn = false,
	}
end

-- Unit forward and right (x, z) for a yaw in degrees.
function FrameMotor.basis(yawDeg: number): (number, number, number, number)
	local r = math.rad(yawDeg)
	local s, c = math.sin(r), math.cos(r)
	return -s, -c, c, -s
end

-- Camera-relative stick to a world direction (x, z), length 0..1.
local function worldInput(input: Input): (number, number, number)
	local mx, my = input.moveX, input.moveY
	local m = math.sqrt(mx * mx + my * my)
	if m > 1 then
		mx, my, m = mx / m, my / m, 1
	end
	local fx, fz, rx, rz = FrameMotor.basis(input.camYaw)
	return fx * my + rx * mx, fz * my + rz * mx, m
end

-- Horizontal speed a leap launches with, from the speed at take-off.
function FrameMotor.leapSpeed(speed: number, cfg: Config): number
	if speed <= cfg.WalkSpeed then
		return cfg.LeapWalkSpeed * math.max(speed, 0) / cfg.WalkSpeed
	end
	local t = math.clamp((speed - cfg.WalkSpeed) / (cfg.SprintSpeed - cfg.WalkSpeed), 0, 1)
	return FrameCam.lerp(cfg.LeapWalkSpeed, cfg.LeapSprintSpeed, t)
end

-- Launch speed for a leap held `held` seconds (wind-up included).
function FrameMotor.leapLaunch(held: number, cfg: Config): number
	local span = cfg.LeapWindupMaxSeconds - cfg.LeapWindupSeconds
	local bonus = if span > 0 then math.clamp((held - cfg.LeapWindupSeconds) / span, 0, 1) else 0
	local h = cfg.LeapHeight * (1 + cfg.LeapHoldBonus * bonus)
	return math.sqrt(2 * cfg.Gravity * h)
end

local function horizontalSpeed(s: State): number
	return math.sqrt(s.vx * s.vx + s.vz * s.vz)
end

local function startDash(s: State, input: Input, cfg: Config)
	local ix, iz, m = worldInput(input)
	if m >= cfg.DashMinInput then
		s.dashX, s.dashZ = ix / m, iz / m
	else
		local fx, fz = FrameMotor.basis(s.yaw)
		s.dashX, s.dashZ = fx, fz
	end
	s.dashCharge -= 1
	s.dashLeft = cfg.DashSeconds
	s.dashBuffer = 0
	s.windup = -1
	s.landLeft = 0
end

local function launch(s: State, cfg: Config)
	s.vy = FrameMotor.leapLaunch(s.windup, cfg)
	local speed = horizontalSpeed(s)
	local hs = FrameMotor.leapSpeed(speed, cfg)
	if speed > 1e-3 then
		s.vx, s.vz = s.vx / speed * hs, s.vz / speed * hs
	end
	s.airSpeed = math.max(hs, cfg.WalkSpeed)
	s.windup = -1
	s.grounded = false
	s.airTime = 0
end

local function groundMove(s: State, input: Input, cfg: Config, dt: number)
	if s.windup >= 0 then
		return -- crouched for a leap: momentum carries into the launch
	end
	local _, _, m = worldInput(input)
	local speed = horizontalSpeed(s)
	local sprinting = input.sprint and input.moveY > 0.1 and s.landLeft <= 0
	local tx, tz = 0, 0
	if s.landLeft <= 0 and m > 0.05 then
		if sprinting then
			-- The sprint runs where the hull faces; the hull turns toward the camera at the sprint turn rate.
			local fx, fz = FrameMotor.basis(s.yaw)
			tx, tz = fx * cfg.SprintSpeed * m, fz * cfg.SprintSpeed * m
		else
			local fx, fz, rx, rz = FrameMotor.basis(input.camYaw)
			local my, mx = input.moveY, input.moveX
			local raw = math.sqrt(mx * mx + my * my)
			if raw > 1 then
				mx, my = mx / raw, my / raw
			end
			tx = fx * my * cfg.WalkSpeed + rx * mx * cfg.WalkSpeed * cfg.StrafeFactor
			tz = fz * my * cfg.WalkSpeed + rz * mx * cfg.WalkSpeed * cfg.StrafeFactor
		end
	end
	local targetSpeed = math.sqrt(tx * tx + tz * tz)
	local reversing = targetSpeed > 0
		and speed > cfg.WalkSpeed * 0.5
		and (tx * s.vx + tz * s.vz) < 0
	local rate
	if targetSpeed < 1e-3 or reversing or targetSpeed < speed then
		-- Stopping, turning round or slowing out of a sprint: the skid. Its rate is set by the speed it
		-- starts from and held, so a full sprint takes SprintStopSeconds and a walk StopSeconds.
		if s.skidRate <= 0 then
			local sprintFrac =
				math.clamp((speed - cfg.WalkSpeed) / (cfg.SprintSpeed - cfg.WalkSpeed), 0, 1)
			s.skidRate = FrameCam.lerp(
				cfg.WalkSpeed / cfg.StopSeconds,
				cfg.SprintSpeed / cfg.SprintStopSeconds,
				sprintFrac
			)
		end
		rate = s.skidRate
	elseif sprinting then
		s.skidRate = 0
		rate = cfg.SprintSpeed / cfg.SprintAccelSeconds
	else
		s.skidRate = 0
		rate = cfg.WalkSpeed / cfg.AccelSeconds
	end
	s.vx, s.vz = FrameCam.approach2(s.vx, s.vz, tx, tz, rate * dt)
end

local function airMove(s: State, input: Input, cfg: Config, dt: number)
	local ix, iz, m = worldInput(input)
	if m <= 0.05 then
		return
	end
	local rate = cfg.AirControl * cfg.WalkSpeed / cfg.AccelSeconds
	s.vx, s.vz = FrameCam.approach2(s.vx, s.vz, ix * s.airSpeed, iz * s.airSpeed, rate * dt)
end

local function turn(s: State, input: Input, cfg: Config, dt: number)
	if s.dashLeft > 0 then
		return -- dashes are sidesteps: the hull keeps facing
	end
	local m = math.sqrt(input.moveX * input.moveX + input.moveY * input.moveY)
	if not s.grounded or m > 0.05 then
		s.idleTurn = false
		local speed = horizontalSpeed(s)
		local sprintFrac =
			math.clamp((speed - cfg.WalkSpeed) / (cfg.SprintSpeed - cfg.WalkSpeed), 0, 1)
		local rate = FrameCam.lerp(cfg.TurnDegPerSec, cfg.SprintTurnDegPerSec, sprintFrac)
		s.yaw = FrameCam.turnToward(s.yaw, input.camYaw, rate * dt)
		return
	end
	local diff = FrameCam.wrap(input.camYaw - s.yaw)
	if math.abs(diff) > cfg.TwistDeg then
		s.idleTurn = true
	end
	if s.idleTurn then
		s.yaw = FrameCam.turnToward(s.yaw, input.camYaw, cfg.TurnInPlaceDegPerSec * dt)
		if math.abs(FrameCam.wrap(input.camYaw - s.yaw)) < 0.5 then
			s.idleTurn = false
		end
	end
end

local function gaitOf(s: State, input: Input, cfg: Config): Gait
	if s.dashLeft > 0 then
		return "dash"
	elseif s.windup >= 0 then
		return "windup"
	elseif not s.grounded then
		return "air"
	elseif s.landLeft > 0 then
		return "land"
	end
	local speed = horizontalSpeed(s)
	local m = math.sqrt(input.moveX * input.moveX + input.moveY * input.moveY)
	if speed > cfg.WalkSpeed * 1.05 and input.sprint and input.moveY > 0.1 then
		return "sprint"
	elseif speed > cfg.WalkSpeed * 0.5 and (m <= 0.05 or speed > cfg.WalkSpeed * 1.05) then
		return "skid"
	elseif speed > 1 then
		return "walk"
	end
	return "idle"
end

-- One motor step. Mutates and returns the state.
function FrameMotor.step(s: State, input: Input, env: Env, cfg: Config, dt: number): State
	if dt <= 0 then
		return s
	end
	if input.dashPressed then
		s.dashBuffer = cfg.BufferSeconds
	end
	if input.leapPressed then
		s.leapBuffer = cfg.BufferSeconds
	end
	if s.dashCharge < cfg.DashCharges then
		s.dashCharge = math.min(cfg.DashCharges, s.dashCharge + dt / cfg.DashRechargeSeconds)
	end

	-- Ground contact.
	local h = env.height
	if s.grounded then
		if h == nil or h > cfg.StepDownHeight then
			s.grounded = false -- walked off an edge
			s.airTime = 0
			s.airSpeed = math.max(horizontalSpeed(s), cfg.WalkSpeed)
			s.windup = -1
		end
	elseif h ~= nil and h <= cfg.GroundSnapHeight and s.vy <= 0 then
		s.grounded = true
		if s.airTime > cfg.HardLandAirSeconds then
			s.landLeft = cfg.HardLandSeconds
		end
		s.airTime = 0
	end
	s.landLeft = math.max(0, s.landLeft - dt)

	-- Actions (buffered presses come out on the first step they are allowed).
	if s.dashBuffer > 0 and s.grounded and s.dashLeft <= 0 and s.dashCharge >= 1 then
		startDash(s, input, cfg)
	end
	if s.leapBuffer > 0 and s.grounded and s.dashLeft <= 0 and s.landLeft <= 0 and s.windup < 0 then
		s.windup = 0
		s.leapBuffer = 0
	end
	s.dashBuffer = math.max(0, s.dashBuffer - dt)
	s.leapBuffer = math.max(0, s.leapBuffer - dt)

	-- Horizontal.
	if s.dashEnded then
		-- The last dash step blended dash and exit speed; the move after it starts from the exit speed.
		s.dashEnded = false
		local speed = horizontalSpeed(s)
		if speed > cfg.DashExitSpeed then
			s.vx, s.vz = s.vx / speed * cfg.DashExitSpeed, s.vz / speed * cfg.DashExitSpeed
		end
	end
	if s.dashLeft > 0 or not s.grounded then
		s.skidRate = 0
	end
	if s.dashLeft > 0 then
		local speed = cfg.DashDistance / cfg.DashSeconds
		local inDash = math.min(dt, s.dashLeft)
		-- Time-sliced so the dash covers exactly DashDistance whatever the step length.
		local v = (speed * inDash + cfg.DashExitSpeed * (dt - inDash)) / dt
		s.vx, s.vz = s.dashX * v, s.dashZ * v
		s.dashLeft -= dt
		if s.dashLeft <= 0 then
			s.dashLeft = 0
			s.dashEnded = true
		end
	elseif s.grounded then
		groundMove(s, input, cfg, dt)
	else
		airMove(s, input, cfg, dt)
	end

	-- Vertical.
	if s.grounded then
		if s.windup >= 0 then
			s.windup += dt
			local minDone = s.windup >= cfg.LeapWindupSeconds
			if (minDone and not input.leapHeld) or s.windup >= cfg.LeapWindupMaxSeconds then
				launch(s, cfg)
			end
		end
	end
	if s.grounded then
		s.vy = math.clamp(
			-(h or 0) * cfg.GroundSnapRate,
			-cfg.GroundSnapMaxSpeed,
			cfg.GroundSnapMaxSpeed
		)
	elseif s.airTime > 0 or s.vy <= 0 then
		s.vy = math.max(s.vy - cfg.Gravity * dt, -cfg.TerminalFallSpeed)
		s.airTime += dt
	else
		s.airTime += dt -- launch step: keep the full launch speed this step
	end

	turn(s, input, cfg, dt)
	s.gait = gaitOf(s, input, cfg)
	return s
end

-- After physics: the hull's actual horizontal velocity. When something stopped it (a building, another
-- Frame), the motor takes the actual velocity so the next step starts from where the hull really is.
function FrameMotor.collide(s: State, ax: number, az: number, cfg: Config): State
	local cmd = horizontalSpeed(s)
	if cmd < cfg.BlockedMinSpeed then
		return s
	end
	local actual = math.sqrt(ax * ax + az * az)
	if actual < cmd * cfg.BlockedRatio then
		s.vx, s.vz = ax, az
		s.dashLeft = 0
		s.dashEnded = false
		if not s.grounded then
			s.airSpeed = math.max(actual, cfg.WalkSpeed)
		end
	end
	return s
end

return FrameMotor
