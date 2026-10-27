--!strict
-- Run with: lune run tests/run
local Camera = require("../src/shared/Config/Camera")
local FrameConfig = require("../src/shared/Config/Frame")
local FrameGuard = require("../src/shared/Rules/FrameGuard")
local FrameMotor = require("../src/shared/Rules/FrameMotor")
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
check("Frame walk is 42 studs/s", FrameConfig.Motor.WalkSpeed == 42)
check("Frame sprint is 112 studs/s", FrameConfig.Motor.SprintSpeed == 112)
check("real gravity at scale is 34.3", near(Scale.Gravity.Real, 34.335))
check("engine gravity stays default", Scale.Gravity.Engine == 196.2)
check(
	"pilot grey is valid RGB",
	(function()
		local c = Scale.Pilot.Color
		for _, v in { c.r, c.g, c.b } do
			if v < 0 or v > 255 or v % 1 ~= 0 then
				return false
			end
		end
		return true
	end)()
)
check("Frame is 28x the pilot", near(Scale.Frame.Height / Scale.Pilot.HeightR6, 28))
check("eye below Frame top", Scale.Frame.EyeHeight < Scale.Frame.Height)
check("cockpit below eye", Scale.Frame.CockpitHeight < Scale.Frame.EyeHeight)
check("root below cockpit", Scale.Frame.RootHeight < Scale.Frame.CockpitHeight)
check(
	"Scale is frozen",
	table.isfrozen(Scale) and table.isfrozen(Scale.Frame) and table.isfrozen(Scale.Gym)
)
check(
	"pilot spawn within board range of every slot",
	(function()
		for _, slot in FrameConfig.Slots do
			local dx = Scale.Gym.PilotSpawn.x - slot.x
			local dz = Scale.Gym.PilotSpawn.z - slot.z
			if math.sqrt(dx * dx + dz * dz) >= Scale.Frame.BoardRange then
				return false
			end
		end
		return true
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
		return gap > FrameConfig.Hull.ColliderRadius * 2 + 40
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
	Camera.ThirdPerson.MinDistance > 0
		and Camera.ThirdPerson.Distance > FrameConfig.Hull.ColliderRadius * 4
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

-- FrameMotor: a tiny simulator integrates the motor's velocity over flat ground (rest height y = 0).
local M = FrameConfig.Motor
local G = FrameConfig.Guard
local DT = 1 / 60

type Sim = {
	s: FrameMotor.State,
	x: number,
	y: number,
	z: number,
	t: number,
	floor: number, -- ground rest height under the hull
}

local function newSim(): Sim
	return { s = FrameMotor.new(0, M.DashCharges), x = 0, y = 0, z = 0, t = 0, floor = 0 }
end

local function input(over: { [string]: any }?): FrameMotor.Input
	local i: FrameMotor.Input = {
		moveX = 0,
		moveY = 0,
		camYaw = 0,
		sprint = false,
		dashPressed = false,
		leapPressed = false,
		leapHeld = false,
	}
	if over then
		for k, v in over do
			(i :: any)[k] = v
		end
	end
	return i
end

local function tick(sim: Sim, i: FrameMotor.Input, dt: number?)
	local d = dt or DT
	FrameMotor.step(sim.s, i, { height = sim.y - sim.floor }, M, d)
	sim.x += sim.s.vx * d
	sim.y += sim.s.vy * d
	sim.z += sim.s.vz * d
	sim.t += d
end

local function run(sim: Sim, seconds: number, i: FrameMotor.Input)
	local n = math.floor(seconds / DT + 0.5)
	for _ = 1, n do
		tick(sim, i)
	end
end

local function hspeed(s: FrameMotor.State): number
	return math.sqrt(s.vx * s.vx + s.vz * s.vz)
end

-- Runs until the motor is grounded again; returns airtime, apex height and flight distance.
local function leap(sim: Sim, i: FrameMotor.Input, holdSeconds: number): (number, number, number)
	local x0, z0 = sim.x, sim.z
	tick(
		sim,
		input({
			moveX = i.moveX,
			moveY = i.moveY,
			sprint = i.sprint,
			leapPressed = true,
			leapHeld = true,
		})
	)
	local held = DT
	while sim.s.grounded and held < 2 do
		local holding = held < holdSeconds
		tick(
			sim,
			input({ moveX = i.moveX, moveY = i.moveY, sprint = i.sprint, leapHeld = holding })
		)
		held += DT
	end
	local air, apex = 0, 0
	x0, z0 = sim.x, sim.z -- flight distance, from launch
	while not sim.s.grounded and air < 10 do
		tick(sim, i)
		air += DT
		apex = math.max(apex, sim.y)
	end
	return air, apex, math.sqrt((sim.x - x0) ^ 2 + (sim.z - z0) ^ 2)
end

check("motor config frozen", table.isfrozen(M) and table.isfrozen(G))
check(
	"basis: yaw 0 looks -Z, right is +X",
	(function()
		local fx, fz, rx, rz = FrameMotor.basis(0)
		return near(fx, 0) and near(fz, -1) and near(rx, 1) and near(rz, 0)
	end)()
)
check(
	"basis: yaw 90 looks -X",
	(function()
		local fx, fz = FrameMotor.basis(90)
		return near(fx, -1) and near(fz, 0)
	end)()
)
check(
	"zero dt changes nothing",
	(function()
		local sim = newSim()
		FrameMotor.step(sim.s, input({ moveY = 1 }), { height = 0 }, M, 0)
		return sim.s.vx == 0 and sim.s.vz == 0 and sim.s.gait == "idle"
	end)()
)
check(
	"walk reaches 42 in 0.35 s, heading -Z",
	(function()
		local sim = newSim()
		run(sim, 0.2, input({ moveY = 1 }))
		local early = hspeed(sim.s)
		run(sim, 0.15, input({ moveY = 1 }))
		return early < 42 and near(hspeed(sim.s), 42, 0.5) and sim.z < 0 and sim.s.gait == "walk"
	end)()
)
check(
	"strafe is 70 % of walk",
	(function()
		local sim = newSim()
		run(sim, 1, input({ moveX = 1 }))
		return near(hspeed(sim.s), 42 * 0.7, 0.5) and sim.x > 0
	end)()
)
check(
	"stick over 1 is clamped",
	(function()
		local sim = newSim()
		run(sim, 1, input({ moveX = 1, moveY = 1 }))
		return hspeed(sim.s) <= 42 + 1e-6
	end)()
)
check(
	"sprint reaches 112 in about 0.9 s",
	(function()
		local sim = newSim()
		run(sim, 0.7, input({ moveY = 1, sprint = true }))
		local early = hspeed(sim.s)
		run(sim, 0.25, input({ moveY = 1, sprint = true }))
		return early < 105 and near(hspeed(sim.s), 112, 0.5) and sim.s.gait == "sprint"
	end)()
)
check(
	"sprint needs forward input",
	(function()
		local sim = newSim()
		run(sim, 1.5, input({ moveY = -1, sprint = true }))
		return hspeed(sim.s) <= 42 + 1e-6
	end)()
)
check(
	"walk stops in 0.8 s",
	(function()
		local sim = newSim()
		run(sim, 1, input({ moveY = 1 }))
		run(sim, 0.75, input())
		local moving = hspeed(sim.s) > 0
		run(sim, 0.07, input())
		return moving and hspeed(sim.s) == 0 and sim.s.gait == "idle"
	end)()
)
check(
	"sprint stop skids 1.5-1.9 s and slides far",
	(function()
		local sim = newSim()
		run(sim, 2, input({ moveY = 1, sprint = true }))
		local z0 = sim.z
		local t = 0
		local sawSkid = false
		while hspeed(sim.s) > 0 and t < 5 do
			tick(sim, input())
			t += DT
			sawSkid = sawSkid or sim.s.gait == "skid"
		end
		local slide = math.abs(sim.z - z0)
		return t > 1.5 and t < 1.9 and sawSkid and slide > 80
	end)()
)
check(
	"turning round at a run skids first",
	(function()
		local sim = newSim()
		run(sim, 2, input({ moveY = 1, sprint = true }))
		tick(sim, input({ moveY = -1 }))
		-- Still moving forward (-Z) after one step: decelerating, not flipped.
		return sim.s.vz < -100
	end)()
)
check(
	"walk turns the hull at 140 deg/s",
	(function()
		local sim = newSim()
		run(sim, 0.5, input({ moveY = 1, camYaw = 90 }))
		return near(sim.s.yaw, 70, 1)
	end)()
)
check(
	"sprint turns wide at 55 deg/s",
	(function()
		local sim = newSim()
		run(sim, 2, input({ moveY = 1, sprint = true }))
		run(sim, 1, input({ moveY = 1, sprint = true, camYaw = 90 }))
		return sim.s.yaw > 50 and sim.s.yaw < 70
	end)()
)
check(
	"standing: torso twist under 70 deg does not move the feet",
	(function()
		local sim = newSim()
		run(sim, 1, input({ camYaw = 60 }))
		return sim.s.yaw == 0
	end)()
)
check(
	"standing: turn in place 180 deg in about 0.45 s",
	(function()
		local sim = newSim()
		local t = 0
		while math.abs(sim.s.yaw) < 179.5 and t < 2 do
			tick(sim, input({ camYaw = 180 }))
			t += DT
		end
		return t > 0.4 and t < 0.5
	end)()
)

-- Dash
check(
	"dash covers 55 m in 0.3 s",
	(function()
		local sim = newSim()
		tick(sim, input({ dashPressed = true }))
		local t = DT
		while sim.s.gait == "dash" do
			tick(sim, input())
			t += DT
		end
		local d = math.abs(sim.z)
		return d >= M.DashDistance - 1
			and d <= M.DashDistance + M.DashExitSpeed * DT + 1
			and near(t, M.DashSeconds, DT * 1.5)
	end)()
)
check(
	"dash distance holds at an odd frame rate",
	(function()
		local sim = newSim()
		local dt = 1 / 37
		tick(sim, input({ dashPressed = true }), dt)
		while sim.s.gait == "dash" do
			tick(sim, input(), dt)
		end
		-- includes the exit share of the last dash step
		local d = math.abs(sim.z)
		return d >= M.DashDistance - 0.5 and d <= M.DashDistance + M.DashExitSpeed * dt + 0.5
	end)()
)
check(
	"dash goes where the stick points (sidestep), hull keeps facing",
	(function()
		local sim = newSim()
		run(sim, 0.5, input({ camYaw = 0 }))
		tick(sim, input({ moveX = 1, dashPressed = true }))
		local yawInDash = sim.s.yaw
		run(sim, 0.2, input({ moveX = 1 }))
		return sim.x > 100 and math.abs(sim.z) < 1 and yawInDash == 0
	end)()
)
check(
	"dash exits at exit speed, then skids",
	(function()
		local sim = newSim()
		tick(sim, input({ dashPressed = true }))
		while sim.s.gait == "dash" do
			tick(sim, input())
		end
		tick(sim, input())
		return hspeed(sim.s) <= M.DashExitSpeed and hspeed(sim.s) > M.DashExitSpeed - 5
	end)()
)
check(
	"two dash charges, third waits for the recharge",
	(function()
		local sim = newSim()
		local dashes = 0
		for _ = 1, 3 do
			tick(sim, input({ dashPressed = true }))
			if sim.s.gait == "dash" then
				dashes += 1
			end
			run(sim, 0.5, input())
		end
		local before = dashes
		run(sim, 3, input()) -- one charge back 4 s after the first use
		tick(sim, input({ dashPressed = true }))
		return before == 2 and sim.s.gait == "dash"
	end)()
)
check(
	"no air dash",
	(function()
		local sim = newSim()
		tick(sim, input({ leapPressed = true, leapHeld = true }))
		run(sim, 0.7, input())
		tick(sim, input({ dashPressed = true }))
		run(sim, 0.1, input())
		return not sim.s.grounded and sim.s.gait == "air" and sim.s.dashCharge > 1.5
	end)()
)
check(
	"dash pressed just before landing comes out (buffer)",
	(function()
		local sim = newSim()
		tick(sim, input({ leapPressed = true, leapHeld = true }))
		while sim.s.grounded do
			tick(sim, input())
		end
		local pressed = false
		local dashed = false
		for _ = 1, 600 do
			local press = not pressed and sim.s.vy < 0 and sim.y < 12
			pressed = pressed or press
			tick(sim, input({ dashPressed = press }))
			dashed = dashed or sim.s.gait == "dash"
		end
		return pressed and dashed
	end)()
)

-- Leap
check(
	"tap leap: 30 m high, about 2.8 s airtime",
	(function()
		local sim = newSim()
		local air, apex = leap(sim, input(), 0)
		return near(apex, M.LeapHeight, 3) and air > 2.7 and air < 2.95
	end)()
)
check(
	"held leap: +30 % height",
	(function()
		local sim = newSim()
		local _, apex = leap(sim, input(), 2)
		return near(apex, M.LeapHeight * 1.3, 4)
	end)()
)
check(
	"sprint leap goes about 110 m",
	(function()
		local sim = newSim()
		run(sim, 2, input({ moveY = 1, sprint = true }))
		local _, _, d = leap(sim, input({ moveY = 1, sprint = true }), 0)
		return d > 110 * 3.5 - 25 and d < 110 * 3.5 + 25
	end)()
)
check(
	"walk leap goes about 60 m",
	(function()
		local sim = newSim()
		run(sim, 1, input({ moveY = 1 }))
		local _, _, d = leap(sim, input({ moveY = 1 }), 0)
		return d > 60 * 3.5 - 20 and d < 60 * 3.5 + 20
	end)()
)
check(
	"standing leap goes straight up",
	(function()
		local sim = newSim()
		local _, _, d = leap(sim, input(), 0)
		return d < 1
	end)()
)
check(
	"leap wind-up keeps the run's momentum",
	(function()
		local sim = newSim()
		run(sim, 2, input({ moveY = 1, sprint = true }))
		tick(sim, input({ moveY = 1, sprint = true, leapPressed = true, leapHeld = true }))
		run(sim, 0.1, input({ moveY = 1, sprint = true, leapHeld = true }))
		return sim.s.gait == "windup" and near(hspeed(sim.s), 112, 0.5)
	end)()
)
check(
	"air steering is limited",
	(function()
		local sim = newSim()
		tick(sim, input({ leapPressed = true }))
		while sim.s.grounded do
			tick(sim, input())
		end
		run(sim, 1, input({ moveX = 1 }))
		local cap = M.AirControl * M.WalkSpeed / M.AccelSeconds * 1.01
		return hspeed(sim.s) <= cap and hspeed(sim.s) > 1
	end)()
)
check(
	"hard landing: short recovery, no leap during it, dash cancels it",
	(function()
		local sim = newSim()
		leap(sim, input(), 0)
		local landed = sim.s.gait == "land"
		tick(sim, input({ leapPressed = true, leapHeld = true }))
		local noLeap = sim.s.windup < 0
		tick(sim, input({ dashPressed = true }))
		return landed and noLeap and sim.s.gait == "dash"
	end)()
)
check(
	"leap pressed late in the recovery comes out when it ends (buffer)",
	(function()
		local sim = newSim()
		leap(sim, input(), 0)
		run(sim, M.HardLandSeconds - 0.1, input())
		tick(sim, input({ leapPressed = true, leapHeld = true }))
		run(sim, 0.15, input({ leapHeld = true }))
		return sim.s.gait == "windup"
	end)()
)
check(
	"walking off a ledge falls with Frame gravity",
	(function()
		local sim = newSim()
		sim.floor = -200
		tick(sim, input())
		run(sim, 1, input())
		return not sim.s.grounded and near(sim.s.vy, -M.Gravity * 1, 3)
	end)()
)
check(
	"a small step down stays grounded",
	(function()
		local sim = newSim()
		sim.floor = -5
		run(sim, 1, input())
		return sim.s.grounded and near(sim.y, -5, 0.5)
	end)()
)
check(
	"fall speed is capped",
	(function()
		local sim = newSim()
		sim.floor = -100000
		run(sim, 6, input())
		return sim.s.vy >= -M.TerminalFallSpeed
	end)()
)

-- Blocked by a wall / another Frame
check(
	"blocked: motor takes the actual velocity and ends the dash",
	(function()
		local sim = newSim()
		tick(sim, input({ dashPressed = true }))
		FrameMotor.collide(sim.s, 0, 0, M)
		return sim.s.vx == 0 and sim.s.vz == 0 and sim.s.dashLeft == 0
	end)()
)
check(
	"not blocked: a slightly slower hull keeps the command",
	(function()
		local sim = newSim()
		run(sim, 1, input({ moveY = 1 }))
		FrameMotor.collide(sim.s, 0, -30, M)
		return near(sim.s.vz, -42)
	end)()
)

-- FrameGuard: replays motor sessions as the server would see them (60 Hz, with replication stalls).
type Frame = { t: number, x: number, y: number, z: number, h: number }

local function guardRun(
	frames: { Frame },
	seed: number,
	stalls: boolean
): ({ string }, FrameGuard.State)
	math.randomseed(seed)
	local g = FrameGuard.new(G)
	local strikes = {}
	local seen = frames[1]
	local stallUntil = -1
	for _, f in frames do
		if stalls and f.t >= stallUntil and math.random() < 0.02 then
			stallUntil = f.t + 0.1 + math.random() * 0.4 -- replication stalls up to 0.5 s, then catches up
		end
		if not stalls or f.t >= stallUntil then
			seen = f
		end
		local sample = { t = f.t, x = seen.x, y = seen.y, z = seen.z, height = seen.h }
		for _, r in FrameGuard.step(g, sample, G) do
			table.insert(strikes, r)
		end
	end
	return strikes, g
end

-- A scripted "normal" session pushed to the limits: sprint, skid, sprint leaps (held), strafe, and a dash
-- whenever a charge is ready.
local function normalSession(
	seconds: number,
	floorAt: ((x: number, z: number) -> number)?
): { Frame }
	local sim = newSim()
	local frames: { Frame } = {}
	local t = 0
	math.randomseed(7)
	local cam = 0
	while t < seconds do
		local phase = t % 12
		cam += 25 * DT + (math.random() - 0.5) * 6 -- circles, so 10 min stays inside the map
		local i = input({ camYaw = cam, moveY = 1 })
		if phase < 3 then
			i.sprint = true
		elseif phase < 4 then
			i.moveY = 0
		elseif phase < 7 then
			i.sprint = true
			i.leapHeld = phase < 5.2
			i.leapPressed = phase >= 4 and phase < 4 + DT
		else
			i.sprint = phase < 10
			i.moveX = if phase > 9 then 1 else 0
		end
		if sim.s.dashCharge >= 1 and math.random() < 0.05 then
			i.dashPressed = true
			i.moveX = math.random() * 2 - 1
		end
		if floorAt then
			sim.floor = floorAt(sim.x, sim.z)
		end
		tick(sim, i)
		t += DT
		table.insert(frames, { t = t, x = sim.x, y = sim.y, z = sim.z, h = sim.y - sim.floor })
	end
	return frames
end

check(
	"guard config: envelope above the motor's real limits",
	G.AllowedSpeed > M.SprintSpeed
		and G.AllowedSpeed > M.LeapSprintSpeed
		and G.DashBudget >= M.DashCharges * M.DashDistance
		and G.TeleportDistance > M.DashDistance
		and G.MaxRise > M.LeapHeight * (1 + M.LeapHoldBonus)
)
local session = normalSession(600)
check(
	"guard: 10 min of hard normal play, no stalls: zero strikes",
	(function()
		local strikes = guardRun(session, 1, false)
		return #strikes == 0
	end)()
)
check(
	"guard: same session with replication stalls (ping slack): zero strikes",
	(function()
		for seed = 1, 5 do
			local strikes = guardRun(session, seed, true)
			if #strikes > 0 then
				print(`  seed {seed}: {#strikes} strikes, first {strikes[1]}`)
				return false
			end
		end
		return true
	end)()
)
check(
	"guard: rooftops and drops (stepped ground): zero strikes",
	(function()
		local function floorAt(x: number, z: number): number
			-- 245-stud blocks on a 600-stud grid
			return if (math.floor(x / 600) + math.floor(z / 600)) % 2 == 0 then 0 else -245
		end
		local strikes = guardRun(normalSession(300, floorAt), 3, true)
		return #strikes == 0
	end)()
)
check(
	"guard: dash spam beyond the charges is a speed strike",
	(function()
		local frames = {}
		local x = 0
		for i = 1, 120 do
			x += 642 / 60 -- dashing non-stop for 2 s
			table.insert(frames, { t = i / 60, x = x, y = 0, z = 0, h = 0 })
		end
		local strikes = guardRun(frames, 1, false)
		return table.find(strikes, "speed") ~= nil
	end)()
)
check(
	"guard: 1.5x sprint speed hack is a speed strike within a minute",
	(function()
		local frames = {}
		local x = 0
		for i = 1, 3600 do
			x += 168 / 60
			table.insert(frames, { t = i / 60, x = x, y = 0, z = 0, h = 0 })
		end
		local strikes = guardRun(frames, 1, false)
		return table.find(strikes, "speed") ~= nil
	end)()
)
check(
	"guard: teleport is caught",
	(function()
		local frames = {
			{ t = 0, x = 0, y = 0, z = 0, h = 0 },
			{ t = 1 / 60, x = 0, y = 0, z = 0, h = 0 },
			{ t = 2 / 60, x = 600, y = 0, z = 0, h = 0 },
		}
		local strikes = guardRun(frames, 1, false)
		return strikes[1] == "teleport"
	end)()
)
check(
	"guard: flying up is a rise strike, hovering a hover strike",
	(function()
		local frames = {}
		local y = 0
		for i = 1, 60 * 12 do
			if y < 200 then
				y += 2
			end
			table.insert(frames, { t = i / 60, x = 0, y = y, z = 0, h = y })
		end
		local strikes = guardRun(frames, 1, false)
		return table.find(strikes, "rise") ~= nil and table.find(strikes, "hover") ~= nil
	end)()
)
check(
	"guard: outside the map is a bounds strike",
	(function()
		local frames = {
			{ t = 0, x = 5340, y = 0, z = 0, h = 0 },
			{ t = 1 / 60, x = 5360, y = 0, z = 0, h = 0 },
		}
		local strikes = guardRun(frames, 1, false)
		return strikes[1] == "bounds"
	end)()
)
check(
	"guard: reset forgets history",
	(function()
		local g = FrameGuard.new(G)
		FrameGuard.step(g, { t = 0, x = 0, y = 0, z = 0, height = 0 }, G)
		FrameGuard.reset(g, G)
		local r = FrameGuard.step(g, { t = 1 / 60, x = 2000, y = 0, z = 0, height = 0 }, G)
		return #r == 0
	end)()
)
check(
	"guard: zero dt sample is ignored",
	(function()
		local g = FrameGuard.new(G)
		FrameGuard.step(g, { t = 1, x = 0, y = 0, z = 0, height = 0 }, G)
		local r = FrameGuard.step(g, { t = 1, x = 900, y = 0, z = 0, height = 0 }, G)
		return #r == 0
	end)()
)

-- Net
check(
	"board/exit remotes declared",
	Net.Messages.FrameBoard == "FrameBoard" and Net.Messages.FrameExit == "FrameExit"
)
check("frame action remote declared", Net.Messages.FrameAction == "FrameAction")

if failures > 0 then
	error(`{failures} test(s) failed`)
end
