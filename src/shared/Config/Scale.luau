--!strict
-- World scale for every Frame, Seraph and building. Pure numbers (Lune-tested).
-- Sizes are written as metres * SPM, so changing StudsPerMetre rescales the Frame and its speeds at once.

local SPM = 3.5 -- studs per metre: keeps the default avatar unscaled and the Frame at 140 studs

return table.freeze({
	StudsPerMetre = SPM,

	Pilot = table.freeze({
		HeightR6 = 5, -- default R6 avatar, ~1.43 m at 3.5 studs/m
	}),

	Frame = table.freeze({
		HeightM = 40,
		Height = 40 * SPM, -- 140
		RootHeight = 66, -- pelvis root part centre above the ground
		EyeHeight = 126, -- first-person camera (the Frame's eyes)
		EyeForward = 11, -- eye sits this far in front of the head centre, outside the head block
		CockpitHeight = 95, -- where the pilot sits, inside the torso
		HullRadius = 26, -- collision radius against buildings (block-out walk)
		WaistHeight = 40, -- height of the collision probe

		WalkSpeed = 12 * SPM, -- 42 studs/s
		SprintSpeed = 32 * SPM, -- 112 studs/s
		StrafeFactor = 0.7,
		AccelSeconds = 0.35, -- 0 -> walk speed
		SprintAccelSeconds = 0.9, -- 0 -> sprint speed
		StopSeconds = 0.8,
		TurnDegPerSec = 140,
		SprintTurnDegPerSec = 55,

		BoardRange = 70, -- flat distance from the Frame root a pilot may board from
		ExitOffset = 40, -- pilot is put down this far to the Frame's right on exit
		BoardCooldown = 0.5, -- seconds between board/exit requests per player
	}),

	Seraph = table.freeze({
		Height = 300, -- block-out, ~86 m (Greater class is 210-420 studs)
	}),

	Gravity = table.freeze({
		Engine = 196.2, -- workspace.Gravity stays default: pilots walk as normal avatars
		Real = 9.81 * SPM, -- 34.3 studs/s^2: real gravity at this scale
		Frame = 40, -- Frame/Seraph motor gravity (P2), "huge but slow" leaps
	}),

	Gym = table.freeze({
		GroundTop = 0,
		GroundTile = 2048, -- part size limit; the ground is 2 x 2 tiles
		FramePosition = table.freeze({ x = 0, z = 0 }),
		PilotSpawn = table.freeze({ x = 50, z = 10 }),
		SeraphPosition = table.freeze({ x = 0, z = -1000 }),
		-- City-scale blocks along the street the Frame faces (-Z). h in studs: 18 m, 28 m, 38 m, 70 m.
		Buildings = table.freeze({
			table.freeze({ name = "BlockA", w = 120, h = 18 * SPM, d = 90, x = -150, z = -150 }),
			table.freeze({ name = "BlockB", w = 100, h = 28 * SPM, d = 100, x = 150, z = -170 }),
			table.freeze({ name = "TowerC", w = 70, h = 38 * SPM, d = 70, x = -140, z = -420 }),
			table.freeze({ name = "TowerD", w = 80, h = 70 * SPM, d = 80, x = 160, z = -460 }),
		}),
		MarkerHeight = 10 * SPM, -- "10 m" reference post
	}),
})
