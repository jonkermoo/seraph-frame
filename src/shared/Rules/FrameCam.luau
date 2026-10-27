--!strict
-- Pure maths for the Frame block-out walk and cameras: numbers in, numbers out, no Roblox types.
-- Angles in degrees. Yaw follows Roblox: 0 looks along -Z, positive turns left.

local FrameCam = {}

-- Stick axis (-1..1) after a dead zone and an expo curve. Keeps the sign; 0 inside the dead zone, 1 at full.
function FrameCam.stick(x: number, deadzone: number, expo: number): number
	local a = math.abs(x)
	if a <= deadzone then
		return 0
	end
	local t = math.min((a - deadzone) / (1 - deadzone), 1)
	return math.sign(x) * t ^ expo
end

-- Moves current toward target by at most rate * dt.
function FrameCam.approach(current: number, target: number, rate: number, dt: number): number
	local step = rate * dt
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

-- 2D vector version: moves (x, z) toward (tx, tz) by at most maxStep in length.
function FrameCam.approach2(
	x: number,
	z: number,
	tx: number,
	tz: number,
	maxStep: number
): (number, number)
	local dx, dz = tx - x, tz - z
	local len = math.sqrt(dx * dx + dz * dz)
	if len <= maxStep or len == 0 then
		return tx, tz
	end
	local k = maxStep / len
	return x + dx * k, z + dz * k
end

-- Wraps an angle to (-180, 180].
function FrameCam.wrap(deg: number): number
	local a = (deg + 180) % 360 - 180
	if a == -180 then
		return 180
	end
	return a
end

-- Turns current toward target the short way round, by at most maxStep degrees.
function FrameCam.turnToward(current: number, target: number, maxStep: number): number
	local diff = FrameCam.wrap(target - current)
	if math.abs(diff) <= maxStep then
		return FrameCam.wrap(target)
	end
	return FrameCam.wrap(current + math.sign(diff) * maxStep)
end

function FrameCam.smooth(t: number): number
	local c = math.clamp(t, 0, 1)
	return c * c * (3 - 2 * c)
end

-- How much the Frame is walking (0 standing .. 1 at walk speed) and sprinting (0 at walk .. 1 at sprint).
function FrameCam.gait(speed: number, walkSpeed: number, sprintSpeed: number): (number, number)
	local moving = math.clamp(speed / walkSpeed, 0, 1)
	local sprint = math.clamp((speed - walkSpeed) / (sprintSpeed - walkSpeed), 0, 1)
	return moving, sprint
end

-- Head bob. phase counts footfalls (one per whole number); motion is the comfort slider 0..1.
-- Returns the vertical offset in studs (dips on each footfall) and roll in degrees (alternates per step).
function FrameCam.bob(
	phase: number,
	height: number,
	rollDeg: number,
	motion: number
): (number, number)
	local m = math.clamp(motion, 0, 1)
	local s = math.sin(math.pi * phase)
	return -height * m * (1 - math.abs(s)), rollDeg * m * s
end

function FrameCam.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

return FrameCam
