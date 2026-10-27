--!strict
-- Frame cameras while piloting: first person at the Frame's eyes, third person chase boom over the
-- right shoulder. Toggle flies between them in Config.ToggleSeconds.
-- No clipping: buildings between the camera and the Frame fade; if the camera point itself would be
-- inside a building it is pulled in in front of that building (instant), then eases back out.
-- The camera never goes under the ground, and the own hull fades if the camera is ever inside it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Camera)
local FrameCam = require(ReplicatedStorage.Shared.Rules.FrameCam)
local Scale = require(ReplicatedStorage.Shared.Config.Scale)

local Camera = {}

export type View = {
	root: BasePart,
	model: Model,
	yaw: number, -- degrees, camera look
	pitch: number,
	bobPhase: number,
	moving: number, -- 0..1
	sprint: number, -- 0..1
	motion: number, -- comfort slider 0..1
}

local TP = Config.ThirdPerson
local FP = Config.FirstPerson

local mode: "first" | "third" = Config.Default :: any
local blend = if mode == "first" then 1 else 0 -- 0 third .. 1 first
local boomTarget = TP.Distance
local boomLength = TP.Distance
local fades: { [BasePart]: number } = {}
local hullParts: { BasePart } = {}
local headHidden = false
local hullFaded = false
local occluders: RaycastParams? = nil

local function gymFolders(): { Instance }
	local gym = workspace:FindFirstChild("Gym")
	local list = {}
	if gym then
		for _, name in { "Buildings", "Seraph" } do
			local f = gym:FindFirstChild(name)
			if f then
				table.insert(list, f)
			end
		end
	end
	return list
end

local function insideBox(part: BasePart, point: Vector3, margin: number): boolean
	local p = part.CFrame:PointToObjectSpace(point)
	local h = part.Size / 2 + Vector3.one * margin
	return math.abs(p.X) < h.X and math.abs(p.Y) < h.Y and math.abs(p.Z) < h.Z
end

-- Walks the ray focus -> desired through buildings. Returns the allowed boom length and the parts to fade.
local function solveBoom(focus: Vector3, unit: Vector3, length: number): (number, { BasePart })
	local params = occluders :: RaycastParams
	local faded = {}
	local origin = focus
	local travelled = 0
	local desired = focus + unit * length
	for _ = 1, 8 do
		local hit = workspace:Raycast(origin, unit * (length - travelled), params)
		if not hit then
			break
		end
		local part = hit.Instance
		travelled += (hit.Position - origin).Magnitude
		if part:IsA("BasePart") then
			if insideBox(part, desired, TP.Margin) then
				return math.max(travelled - TP.Margin, TP.MinDistance), faded
			end
			table.insert(faded, part)
		end
		-- A ray that starts inside a part does not hit it again, so step just past the face.
		origin = hit.Position + unit * 0.05
		travelled += 0.05
		if travelled >= length then
			break
		end
	end
	return length, faded
end

local function setHead(hidden: boolean)
	if hidden == headHidden then
		return
	end
	headHidden = hidden
	for _, p in hullParts do
		if p:GetAttribute("FrameHead") then
			p.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function setHullFade(on: boolean)
	if on == hullFaded then
		return
	end
	hullFaded = on
	for _, p in hullParts do
		if not p:GetAttribute("FrameHead") or not headHidden then
			p.LocalTransparencyModifier = if on then TP.HullFade else 0
		end
	end
end

local function updateFades(targets: { BasePart }, dt: number)
	local want: { [BasePart]: boolean } = {}
	for _, p in targets do
		want[p] = true
		if fades[p] == nil then
			fades[p] = 0
		end
	end
	for p, t in fades do
		local goal = if want[p] then TP.FadeTransparency else 0
		local nt = FrameCam.approach(t, goal, TP.FadeRate, dt)
		p.LocalTransparencyModifier = nt
		if nt == 0 and not want[p] then
			fades[p] = nil
		else
			fades[p] = nt
		end
	end
end

function Camera.mode(): string
	return mode
end

function Camera.toggle()
	mode = if mode == "first" then "third" else "first"
end

function Camera.enter(model: Model)
	hullParts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(hullParts, p)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = gymFolders()
	occluders = params
	blend = if mode == "first" then 1 else 0
	boomTarget = TP.Distance
	boomLength = TP.Distance
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
end

function Camera.leave()
	for p in fades do
		p.LocalTransparencyModifier = 0
	end
	fades = {}
	setHullFade(false)
	setHead(false)
	hullParts = {}
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = Config.PilotFov
end

local function firstPersonCFrame(view: View): CFrame
	local rootPos = view.root.Position
	local look = CFrame.Angles(0, math.rad(view.yaw), 0)
	-- Eye in front of the head, turning with the look so looking around never puts the camera in the head.
	local eye = rootPos
		+ Vector3.new(0, Scale.Frame.EyeHeight - Scale.Frame.RootHeight, 0)
		+ look.LookVector * Scale.Frame.EyeForward
	local m = Config.Motion
	local height = FrameCam.lerp(m.WalkBobHeight, m.SprintBobHeight, view.sprint) * view.moving
	local roll = FrameCam.lerp(m.WalkBobRollDeg, m.SprintBobRollDeg, view.sprint) * view.moving
	local dy, rollDeg = FrameCam.bob(view.bobPhase, height, roll, view.motion)
	local pitch = math.clamp(view.pitch, FP.PitchMin, FP.PitchMax)
	return CFrame.new(eye + Vector3.new(0, dy, 0))
		* look
		* CFrame.Angles(math.rad(pitch), 0, 0)
		* CFrame.Angles(0, 0, math.rad(rollDeg))
end

local function thirdPersonCFrame(view: View, dt: number): (CFrame, { BasePart })
	local rootPos = view.root.Position
	local feetY = rootPos.Y - Scale.Frame.RootHeight -- follows the hull up in a leap and onto roofs
	local focus = Vector3.new(rootPos.X, feetY + TP.FocusHeight, rootPos.Z)
	local pitch = math.clamp(view.pitch, TP.PitchMin, TP.PitchMax)
	local rot = CFrame.Angles(0, math.rad(view.yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)

	local goal = FrameCam.lerp(TP.Distance, TP.SprintDistance, view.sprint)
	boomTarget = FrameCam.approach(boomTarget, goal, TP.DistanceRate, dt)
	local offset = rot:VectorToWorldSpace(Vector3.new(TP.ShoulderOffset, 0, boomTarget))
	local length = offset.Magnitude
	local unit = offset.Unit

	local allowed, faded = solveBoom(focus, unit, length)
	if allowed < boomLength then
		boomLength = allowed -- pull in at once: never a frame inside a building
	else
		boomLength = FrameCam.approach(boomLength, allowed, TP.PullOutRate, dt)
	end
	local pos = focus + unit * boomLength
	local minY = Scale.Gym.GroundTop + TP.GroundClearance
	if pos.Y < minY then
		pos = Vector3.new(pos.X, minY, pos.Z)
	end
	-- Also fade anything hiding the legs and hips: a low block can cover them while the focus line clears its roof.
	local params = occluders :: RaycastParams
	for _, h in TP.FadeProbeHeights do
		local probe = Vector3.new(rootPos.X, feetY + h, rootPos.Z)
		local hit = workspace:Raycast(pos, probe - pos, params)
		if hit and hit.Instance:IsA("BasePart") then
			table.insert(faded, hit.Instance)
		end
	end
	-- Look along the boom's rotation (shoulder offset keeps the Frame left of centre).
	return CFrame.new(pos) * rot, faded
end

function Camera.update(view: View, dt: number)
	local target = if mode == "first" then 1 else 0
	blend = FrameCam.approach(blend, target, 1 / Config.ToggleSeconds, dt)
	local s = FrameCam.smooth(blend)

	local tpCF, faded = thirdPersonCFrame(view, dt)
	local cf = tpCF
	if s > 0 then
		cf = tpCF:Lerp(firstPersonCFrame(view), s)
	end
	if s >= 1 then
		faded = {}
	end
	updateFades(faded, dt)
	setHead(s > 0.5)

	local inHull = false
	if s < 1 then
		for _, p in hullParts do
			if p.Transparency < 1 and not (headHidden and p:GetAttribute("FrameHead")) then
				if insideBox(p, cf.Position, 1) then
					inHull = true
					break
				end
			end
		end
	end
	setHullFade(inHull)

	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cf
	cam.FieldOfView = FrameCam.lerp(TP.Fov, FP.Fov, s)
end

return Camera
