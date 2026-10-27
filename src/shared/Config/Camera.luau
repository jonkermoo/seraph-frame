--!strict
-- Frame camera numbers. Pure numbers (Lune-tested). Pilots on foot keep the default Roblox camera.
-- Distances in studs (3.5 studs/m).

return table.freeze({
	Default = "third", -- "first" | "third"
	ToggleSeconds = 0.4, -- animated fly into / out of the head
	PilotFov = 70, -- restored for the default on-foot camera after exiting

	FirstPerson = table.freeze({
		Fov = 80,
		PitchMin = -80,
		PitchMax = 80,
	}),

	ThirdPerson = table.freeze({
		Fov = 70,
		Distance = 228, -- 65 m behind
		SprintDistance = 315, -- 90 m when sprinting
		DistanceRate = 90, -- studs/s the boom lengthens or shortens toward its target
		ShoulderOffset = 35, -- 10 m to the right
		FocusHeight = 90, -- chest: slightly low so the Frame towers
		DefaultPitch = -5,
		PitchMin = -55,
		PitchMax = 65,
		Margin = 4, -- the camera stays this far outside any building
		MinDistance = 20,
		PullOutRate = 150, -- studs/s back out after a pull-in (pull-in is instant)
		GroundClearance = 6,
		FadeTransparency = 0.75, -- buildings between camera and Frame fade instead of the camera snapping in
		FadeRate = 4, -- transparency per second
		FadeProbeHeights = table.freeze({ 15, 40, 66 }), -- feet, knees, hips: extra fade rays to the hull
		HullFade = 0.8, -- own hull fades if the camera is ever inside it
	}),

	Look = table.freeze({
		MouseDegPerPixel = 0.2,
		GamepadYawDegPerSec = 200,
		GamepadPitchDegPerSec = 140,
		GamepadDeadzone = 0.15,
		GamepadExpo = 2, -- fine aim near the centre, fast at full tilt
		MoveDeadzone = 0.2,
		InvertY = false,
	}),

	-- Comfort: the motion slider scales head bob in first person (0 = off, 1 = full).
	Motion = table.freeze({
		Default = 0.5,
		Step = 0.1,
		WalkBobHeight = 3,
		SprintBobHeight = 7,
		WalkBobRollDeg = 0.8,
		SprintBobRollDeg = 2,
		WalkStepSeconds = 1.1, -- heavy footfall every ~1.1 s at walk
		SprintStepSeconds = 0.45,
	}),
})
