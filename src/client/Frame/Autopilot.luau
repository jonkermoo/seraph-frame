--!strict
-- Studio-only test driver for long FrameGuard runs and bump tests: feeds the motor scripted input in
-- place of the player's. Switched on from a Studio client (no input binding, never in a live game):
--   game.Players.LocalPlayer:SetAttribute("FrameAutopilot", "loop")  -- 12 s cycle of every move
--   game.Players.LocalPlayer:SetAttribute("FrameAutopilot", "ram")   -- run and dash into the nearest Frame
--   game.Players.LocalPlayer:SetAttribute("FrameAutopilot", nil)     -- off

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrameMotor = require(ReplicatedStorage.Shared.Rules.FrameMotor)

local Autopilot = {}

export type Mode = "loop" | "ram"

local rng = Random.new(7)
local camYaw = 0

-- Input for this step. `t` counts seconds since autopilot started; `target` is the nearest other hull.
function Autopilot.input(
	mode: Mode,
	t: number,
	dt: number,
	motor: FrameMotor.State,
	pos: Vector3,
	target: Vector3?
): FrameMotor.Input
	local i: FrameMotor.Input = {
		moveX = 0,
		moveY = 1,
		camYaw = camYaw,
		sprint = false,
		dashPressed = false,
		leapPressed = false,
		leapHeld = false,
	}
	if mode == "ram" and target then
		local d = target - pos
		camYaw = math.deg(math.atan2(-d.X, -d.Z))
		i.camYaw = camYaw
		local phase = t % 8
		i.sprint = phase < 5
		i.moveY = if phase < 6 then 1 else -1 -- back off, then charge again
		i.dashPressed = phase >= 3 and phase < 3 + dt and motor.dashCharge >= 1
		return i
	end
	-- loop: circles about 200 studs wide so it stays in the gym and meets buildings and the other Frame.
	local phase = t % 12
	camYaw += 25 * dt + (rng:NextNumber() - 0.5) * 6
	i.camYaw = camYaw
	if phase < 3 then
		i.sprint = true
	elseif phase < 4 then
		i.moveY = 0
	elseif phase < 7 then
		i.sprint = true
		i.leapHeld = phase < 5.2
		i.leapPressed = phase >= 4 and phase < 4 + dt
	else
		i.sprint = phase < 10
		i.moveX = if phase > 9 then 1 else 0
	end
	if motor.dashCharge >= 1 and rng:NextNumber() < 0.05 then
		i.dashPressed = true
		i.moveX = rng:NextNumber() * 2 - 1
	end
	return i
end

return Autopilot
