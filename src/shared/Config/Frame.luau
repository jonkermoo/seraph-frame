--!strict
-- Frame motor and FrameGuard numbers (P2). Pure numbers (Lune-tested).
-- Written as metres * SPM where the design gives metres (01-combat-movement §2), base chassis at Sync 50 %.
-- Sizes and boarding numbers stay in Config/Scale.

local SPM = 3.5 -- studs per metre (Config/Scale.StudsPerMetre)

local Gravity = 105 -- ~3x real at this scale: a 30 m leap lands in ~2.8 s ("no floatiness")
local LeapHeight = 30 * SPM -- 105 studs
local LeapHoldBonus = 0.3 -- +30 % height when the wind-up is held to the max
local WalkSpeed = 12 * SPM -- 42
local SprintSpeed = 32 * SPM -- 112
local DashDistance = 55 * SPM -- 192.5
local DashSeconds = 0.3
local DashCharges = 2
local DashRechargeSeconds = 4
local LeapSprintSpeed = 136 -- horizontal: 110 m forward over a ~2.8 s leap from a full sprint
local LeapWalkSpeed = 74 -- 60 m from walk speed

local Motor = table.freeze({
	WalkSpeed = WalkSpeed,
	SprintSpeed = SprintSpeed,
	StrafeFactor = 0.7,
	AccelSeconds = 0.35, -- 0 -> walk
	SprintAccelSeconds = 0.9, -- 0 -> sprint (3 strides)
	StopSeconds = 0.8, -- walk -> 0
	SprintStopSeconds = 1.6, -- sprint -> 0: the skid ("weight lives in the stop")
	TurnDegPerSec = 140,
	SprintTurnDegPerSec = 55, -- at sprint the hull (and the run) turns wide toward the camera
	TurnInPlaceDegPerSec = 400, -- 180 deg in 0.45 s
	TwistDeg = 70, -- standing: the torso twists this far before the feet follow

	Gravity = Gravity,
	TerminalFallSpeed = 300,
	GroundSnapHeight = 2, -- airborne and this close to rest height: landed
	StepDownHeight = 20, -- grounded and the ground drops more than this: falling
	GroundSnapRate = 12, -- 1/s: vertical speed that pulls the root back to rest height
	GroundSnapMaxSpeed = 80,

	DashDistance = DashDistance,
	DashSeconds = DashSeconds,
	DashCharges = DashCharges,
	DashRechargeSeconds = DashRechargeSeconds, -- per charge, one at a time
	DashExitSpeed = WalkSpeed * 1.5, -- carried out of the dash, then the normal skid
	DashMinInput = 0.2, -- below this the dash goes straight ahead

	LeapHeight = LeapHeight,
	LeapHoldBonus = LeapHoldBonus,
	LeapWindupSeconds = 0.25, -- crouch before launch
	LeapWindupMaxSeconds = 1, -- holding to here gives the full bonus
	LeapWalkSpeed = LeapWalkSpeed,
	LeapSprintSpeed = LeapSprintSpeed,
	AirControl = 0.15, -- share of ground walk accel available in the air
	HardLandAirSeconds = 1, -- longer in the air than this: hard landing
	HardLandSeconds = 0.4, -- recovery: no leap, moves bleed (dash cancels it)

	BufferSeconds = 0.15, -- dash / leap pressed this early still come out
	BlockedRatio = 0.35, -- actual speed under this share of commanded: blocked by something
	BlockedMinSpeed = 10,

	DriveAccel = 20000, -- studs/s^2 the LinearVelocity may apply (x assembly mass): reaches dash speed in ~2 frames
})

local MaxRise = LeapHeight * (1 + LeapHoldBonus)
-- Fastest non-dash ground speed the server should ever see: a sprint leap's horizontal speed.
local AllowedSpeed = math.max(SprintSpeed, LeapSprintSpeed)

local Guard = table.freeze({
	AllowedSpeed = AllowedSpeed * 1.15,
	-- Ping slack: replication can stall and then deliver a burst. Unused allowance banks up to this many
	-- seconds' worth, so a late burst of normal movement is never read as speed.
	PingSlackSeconds = 0.75,
	DashBudget = DashCharges * DashDistance + 60, -- extra distance over AllowedSpeed (dashes) + slack
	DashRegen = DashDistance / DashRechargeSeconds, -- studs/s, the dash recharge rate
	TeleportDistance = DashDistance + 200, -- one server tick: more than a whole dash plus a burst
	MaxRise = MaxRise + 40, -- above the last support (ground, roof, another Frame), studs
	GroundedHeight = 15, -- root within this of its rest height: on support
	MaxAirSeconds = 9, -- held leap ~3.2 s + falling off a 245-stud tower ~2.6 s + slack
	MapHalf = 5250 + 100, -- v1 map 10,500 x 10,500 studs centred on the origin
	SampleLog = 1, -- seconds between stat attribute updates
})

return table.freeze({
	Motor = Motor,
	Guard = Guard,

	Hull = table.freeze({
		ColliderRadius = 26, -- vertical cylinder, Frame vs Frame / buildings
		ColliderBottom = 12, -- above the ground: steps over cars and low rubble
		ColliderTop = 122,
		Density = 0.7,
		Friction = 0, -- slides along walls and other Frames
	}),

	CollisionGroups = table.freeze({
		Hull = "FrameHull",
		Pilot = "Pilot",
	}),

	-- Gym parking slots (x, z, yaw degrees). Two Frames for the 2-player test, both in board range of the pad.
	Slots = table.freeze({
		table.freeze({ x = -60, z = 0, yaw = 0 }),
		table.freeze({ x = 60, z = 0, yaw = 0 }),
	}),

	OwnerCheckSeconds = 0.25, -- server re-checks each piloted hull's network owner
	ActionMinInterval = 0.1, -- FrameAction rate limit per player
})
