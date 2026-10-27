--!strict
-- Run with: lune run tests/run
local Camera = require("../src/shared/Config/Camera")
local FrameCam = require("../src/shared/Rules/FrameCam")
local Game = require("../src/shared/Config/Game")
local Net = require("../src/shared/Net")
local Scale = require("../src/shared/Config/Scale")

local failures = 0
local function check(name: string, ok: boolean)
	if ok then
		print("PASS " .. name)
	else
		print("FAIL " .. name)
		failures += 1
	end
end

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

check("WalkSpeed is positive", Game.Player.WalkSpeed > 0)
check("JumpPower is positive", Game.Player.JumpPower > 0)

-- Scale
check("3.5 studs per metre", Scale.StudsPerMetre == 3.5)
check("Frame is 140 studs", Scale.Frame.Height == 140)
check("Seraph block-out is 300 studs", Scale.Seraph.Height == 300)
check("Frame walk is 42 studs/s", Scale.Frame.WalkSpeed == 42)
check("Frame sprint is 112 studs/s", Scale.Frame.SprintSpeed == 112)
check("real gravity at scale is 34.3", near(Scale.Gravity.Real, 34.335))
check("engine gravity stays default", Scale.Gravity.Engine == 196.2)
check("eye below Frame top", Scale.Frame.EyeHeight < Scale.Frame.Height)
check("cockpit below eye", Scale.Frame.CockpitHeight < Scale.Frame.EyeHeight)
check("root below cockpit", Scale.Frame.RootHeight < Scale.Frame.CockpitHeight)
check(
	"Scale is frozen",
	table.isfrozen(Scale) and table.isfrozen(Scale.Frame) and table.isfrozen(Scale.Gym)
)
check(
	"pilot spawn within board range",
	(function()
		local dx = Scale.Gym.PilotSpawn.x - Scale.Gym.FramePosition.x
		local dz = Scale.Gym.PilotSpawn.z - Scale.Gym.FramePosition.z
		return math.sqrt(dx * dx + dz * dz) < Scale.Frame.BoardRange
	end)()
)
check(
	"4 buildings, all inside one ground tile pair",
	(function()
		local list = Scale.Gym.Buildings
		if #list ~= 4 then
			return false
		end
		for _, b in list do
			if
				math.abs(b.x) + b.w / 2 > Scale.Gym.GroundTile
				or math.abs(b.z) + b.d / 2 > Scale.Gym.GroundTile
			then
				return false
			end
			if b.h <= 0 or b.h > 2048 then
				return false
			end
		end
		return true
	end)()
)
check(
	"street between first blocks fits the Frame",
	(function()
		local a, b = Scale.Gym.Buildings[1], Scale.Gym.Buildings[2]
		local gap = (b.x - b.w / 2) - (a.x + a.w / 2)
		return gap > Scale.Frame.HullRadius * 2 + 40
	end)()
)

-- Camera config
check(
	"camera config frozen",
	table.isfrozen(Camera) and table.isfrozen(Camera.Look) and table.isfrozen(Camera.Motion)
)
check("default camera is valid", Camera.Default == "first" or Camera.Default == "third")
check("first-person FOV 80", Camera.FirstPerson.Fov == 80)
check("third-person FOV 70", Camera.ThirdPerson.Fov == 70)
check("boom is ~65 m", near(Camera.ThirdPerson.Distance, 65 * Scale.StudsPerMetre, 0.5))
check("sprint boom is longer", Camera.ThirdPerson.SprintDistance > Camera.ThirdPerson.Distance)
check(
	"boom clears the hull",
	Camera.ThirdPerson.MinDistance > 0 and Camera.ThirdPerson.Distance > Scale.Frame.HullRadius * 4
)
check("motion default in 0..1", Camera.Motion.Default >= 0 and Camera.Motion.Default <= 1)
check(
	"gamepad deadzone in 0..1",
	Camera.Look.GamepadDeadzone > 0 and Camera.Look.GamepadDeadzone < 1
)
check(
	"pitch ranges ordered",
	Camera.FirstPerson.PitchMin < Camera.FirstPerson.PitchMax
		and Camera.ThirdPerson.PitchMin < Camera.ThirdPerson.PitchMax
)

-- FrameCam rules
check("stick: 0 inside dead zone", FrameCam.stick(0.1, 0.15, 2) == 0)
check("stick: full tilt is 1", near(FrameCam.stick(1, 0.15, 2), 1))
check("stick: keeps sign", near(FrameCam.stick(-1, 0.15, 2), -1))
check("stick: over 1 clamps", near(FrameCam.stick(1.5, 0.15, 2), 1))
check("stick: expo softens half tilt", FrameCam.stick(0.575, 0.15, 2) < 0.5)
check("approach up stops at target", FrameCam.approach(0, 10, 100, 1) == 10)
check("approach down by rate", near(FrameCam.approach(10, 0, 4, 0.5), 8))
check("approach zero dt holds", FrameCam.approach(3, 9, 5, 0) == 3)
check(
	"approach2 limits step",
	(function()
		local x, z = FrameCam.approach2(0, 0, 30, 40, 5)
		return near(x, 3) and near(z, 4)
	end)()
)
check(
	"approach2 reaches target",
	(function()
		local x, z = FrameCam.approach2(1, 1, 2, 2, 10)
		return x == 2 and z == 2
	end)()
)
check("wrap 190 -> -170", near(FrameCam.wrap(190), -170))
check("wrap -190 -> 170", near(FrameCam.wrap(-190), 170))
check("wrap 180 stays 180", FrameCam.wrap(180) == 180)
check("turn the short way across 180", near(FrameCam.turnToward(170, -170, 5), 175))
check("turn snaps when close", near(FrameCam.turnToward(10, 12, 5), 12))
check(
	"smooth ends",
	FrameCam.smooth(0) == 0 and FrameCam.smooth(1) == 1 and FrameCam.smooth(2) == 1
)
check(
	"gait standing",
	(function()
		local m, s = FrameCam.gait(0, 42, 112)
		return m == 0 and s == 0
	end)()
)
check(
	"gait walking",
	(function()
		local m, s = FrameCam.gait(42, 42, 112)
		return m == 1 and s == 0
	end)()
)
check(
	"gait sprinting",
	(function()
		local m, s = FrameCam.gait(112, 42, 112)
		return m == 1 and s == 1
	end)()
)
check(
	"bob off at motion 0",
	(function()
		local y, r = FrameCam.bob(0.3, 7, 2, 0)
		return y == 0 and r == 0
	end)()
)
check("bob dips on footfall", near((FrameCam.bob(0, 3, 1, 1)), -3))
check("bob level mid-step", near((FrameCam.bob(0.5, 3, 1, 1)), 0))
check(
	"bob roll alternates",
	(function()
		local _, r1 = FrameCam.bob(0.5, 3, 1, 1)
		local _, r2 = FrameCam.bob(1.5, 3, 1, 1)
		return r1 > 0 and r2 < 0
	end)()
)
check("bob motion clamps above 1", near((FrameCam.bob(0, 3, 1, 5)), -3))

-- Net
check(
	"board/exit remotes declared",
	Net.Messages.FrameBoard == "FrameBoard" and Net.Messages.FrameExit == "FrameExit"
)

if failures > 0 then
	error(`{failures} test(s) failed`)
end
