--!strict
-- P1 block-out walk: board / exit the gym Frame and walk it on flat ground. No gait animation, no leap
-- or dash (that is P2's FrameMotor). The hull is network-owned by the pilot; this client sets its CFrame
-- each frame and the server anchors it back on exit.
-- Every input goes through ContextActionService with keyboard/mouse and gamepad bindings.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraConfig = require(ReplicatedStorage.Shared.Config.Camera)
local FrameCam = require(ReplicatedStorage.Shared.Rules.FrameCam)
local Net = require(ReplicatedStorage.Shared.Net)
local Scale = require(ReplicatedStorage.Shared.Config.Scale)
local Camera = require(script.Parent.Camera)
local Hud = require(script.Parent.Hud)

local Controller = {}

local player = Players.LocalPlayer
local F = Scale.Frame
local LOOK = CameraConfig.Look
local MOTION = CameraConfig.Motion

local RENDER_NAME = "FrameGym"
local PRIORITY = Enum.ContextActionPriority.High.Value

local piloting = false
local keys: { [Enum.KeyCode]: boolean } = {}
local stick1 = Vector2.zero
local stick2 = Vector2.zero
local mouseDelta = Vector2.zero
local sprintHeld = false
local sprintToggle = false
local motion = MOTION.Default

local yaw = 0 -- camera look, degrees
local pitch = CameraConfig.ThirdPerson.DefaultPitch
local hullYaw = 0
local vx, vz = 0, 0
local bobPhase = 0
local exitAt: CFrame? = nil -- hull CFrame sent with the exit request; the hull holds still until the server answers
local exitSentAt = 0
local cockpit: BasePart? = nil

local function hudText()
	local motionText = `motion {math.floor(motion * 100 + 0.5)}% ([ ] / D-pad L R)`
	if piloting then
		Hud.set(
			`PILOTING  |  camera {string.upper(Camera.mode())} (T / D-pad up)  |  {motionText}  |  sprint Shift / L3  |  exit E / X`
		)
	else
		Hud.set(`On foot  |  walk to the Frame's feet, board with E / X  |  {motionText}`)
	end
end

local function setCharacterHidden(hidden: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, p in character:GetDescendants() do
		if p:IsA("BasePart") or p:IsA("Decal") then
			p.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function moveInput(): Vector2
	local x, y = 0, 0
	if keys[Enum.KeyCode.W] then
		y += 1
	end
	if keys[Enum.KeyCode.S] then
		y -= 1
	end
	if keys[Enum.KeyCode.D] then
		x += 1
	end
	if keys[Enum.KeyCode.A] then
		x -= 1
	end
	x += FrameCam.stick(stick1.X, LOOK.MoveDeadzone, 1)
	y += FrameCam.stick(stick1.Y, LOOK.MoveDeadzone, 1)
	local v = Vector2.new(x, y)
	if v.Magnitude > 1 then
		v = v.Unit
	end
	return v
end

-- Moves the hull by (dx, dz) at waist height, stopping at buildings and sliding along their faces.
local function collide(pos: Vector3, dx: number, dz: number, params: RaycastParams): Vector3
	local delta = Vector3.new(dx, 0, dz)
	for _ = 1, 2 do
		if delta.Magnitude < 1e-4 then
			break
		end
		local probe = Vector3.new(pos.X, Scale.Gym.GroundTop + F.WaistHeight, pos.Z)
		local hit = workspace:Spherecast(probe, F.HullRadius, delta, params)
		if not hit then
			return pos + delta
		end
		local unit = delta.Unit
		local allowed = math.max(hit.Distance - 0.5, 0)
		pos += unit * allowed
		local rest = delta - unit * allowed
		local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
		if n.Magnitude < 1e-4 then
			break
		end
		n = n.Unit
		delta = rest - n * rest:Dot(n)
	end
	return pos
end

local function step(root: BasePart, model: Model, params: RaycastParams, dt: number)
	local cfgLook = LOOK
	-- Look: mouse (degrees per pixel) + right stick (degrees per second, dead zone + expo).
	local invert = if cfgLook.InvertY then -1 else 1
	yaw -= mouseDelta.X * cfgLook.MouseDegPerPixel
	pitch -= mouseDelta.Y * cfgLook.MouseDegPerPixel * invert
	mouseDelta = Vector2.zero
	yaw -= FrameCam.stick(stick2.X, cfgLook.GamepadDeadzone, cfgLook.GamepadExpo) * cfgLook.GamepadYawDegPerSec * dt
	pitch += FrameCam.stick(stick2.Y, cfgLook.GamepadDeadzone, cfgLook.GamepadExpo) * cfgLook.GamepadPitchDegPerSec * dt * invert
	yaw = FrameCam.wrap(yaw)
	local pMin = math.min(CameraConfig.FirstPerson.PitchMin, CameraConfig.ThirdPerson.PitchMin)
	local pMax = math.max(CameraConfig.FirstPerson.PitchMax, CameraConfig.ThirdPerson.PitchMax)
	pitch = math.clamp(pitch, pMin, pMax)

	-- Walk: target velocity relative to the camera's yaw.
	local input = moveInput()
	if exitAt then
		if os.clock() - exitSentAt > F.ExitTimeout then
			exitAt = nil -- server refused (cooldown): keep walking
		else
			input = Vector2.zero
			vx, vz = 0, 0
		end
	end
	if input.Magnitude < 0.05 then
		sprintToggle = false
	end
	local sprinting = (sprintHeld or sprintToggle) and input.Y > 0.1
	local maxSpeed = if sprinting then F.SprintSpeed else F.WalkSpeed
	local look = CFrame.Angles(0, math.rad(yaw), 0)
	local fwd = look.LookVector
	local right = look.RightVector
	local target = fwd * (input.Y * maxSpeed) + right * (input.X * maxSpeed * F.StrafeFactor)
	local accel = if input.Magnitude > 0.05
		then maxSpeed / (if sprinting then F.SprintAccelSeconds else F.AccelSeconds)
		else F.WalkSpeed / F.StopSeconds
	if not sprinting and math.sqrt(vx * vx + vz * vz) > F.WalkSpeed then
		accel = F.SprintSpeed / F.StopSeconds -- coming out of a sprint
	end
	vx, vz = FrameCam.approach2(vx, vz, target.X, target.Z, accel * dt)
	local speed = math.sqrt(vx * vx + vz * vz)

	-- Hull turns toward the camera yaw while moving (slower at sprint).
	local moving, sprintFrac = FrameCam.gait(speed, F.WalkSpeed, F.SprintSpeed)
	if input.Magnitude > 0.05 then
		local turn = FrameCam.lerp(F.TurnDegPerSec, F.SprintTurnDegPerSec, sprintFrac)
		hullYaw = FrameCam.turnToward(hullYaw, yaw, turn * dt)
	end

	local pos = collide(root.Position, vx * dt, vz * dt, params)
	if (pos - root.Position).Magnitude < speed * dt * 0.5 then
		-- blocked: bleed speed so the bob does not keep running against a wall
		vx, vz = FrameCam.approach2(vx, vz, 0, 0, F.SprintSpeed / F.StopSeconds * dt)
	end
	root.CFrame = CFrame.new(pos.X, Scale.Gym.GroundTop + F.RootHeight, pos.Z)
		* CFrame.Angles(0, math.rad(hullYaw), 0)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	local stepSeconds = FrameCam.lerp(MOTION.WalkStepSeconds, MOTION.SprintStepSeconds, sprintFrac)
	bobPhase += dt / stepSeconds * moving

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	Camera.update({
		root = root,
		model = model,
		yaw = yaw,
		pitch = pitch,
		bobPhase = bobPhase,
		moving = moving,
		sprint = sprintFrac,
		motion = motion,
	}, dt)
end

local function onMove(
	_: string,
	state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		stick1 = if state == Enum.UserInputState.End
			then Vector2.zero
			else Vector2.new(input.Position.X, input.Position.Y)
	else
		keys[input.KeyCode] = state == Enum.UserInputState.Begin
			or state == Enum.UserInputState.Change
	end
	return Enum.ContextActionResult.Sink
end

local function onLook(
	_: string,
	state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stick2 = if state == Enum.UserInputState.End
			then Vector2.zero
			else Vector2.new(input.Position.X, input.Position.Y)
	elseif input.UserInputType == Enum.UserInputType.MouseMovement then
		mouseDelta += Vector2.new(input.Delta.X, input.Delta.Y)
	end
	return Enum.ContextActionResult.Sink
end

local function onSprint(
	_: string,
	state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if input.KeyCode == Enum.KeyCode.ButtonL3 then
		if state == Enum.UserInputState.Begin then
			sprintToggle = not sprintToggle
		end
	else
		sprintHeld = state == Enum.UserInputState.Begin
	end
	return Enum.ContextActionResult.Sink
end

local function onSink(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function enterPilot(model: Model, root: BasePart)
	if piloting then
		return
	end
	piloting = true
	keys = {}
	stick1, stick2, mouseDelta = Vector2.zero, Vector2.zero, Vector2.zero
	sprintHeld, sprintToggle = false, false
	vx, vz = 0, 0
	exitAt = nil
	local _, ry, _ = root.CFrame:ToOrientation()
	hullYaw = math.deg(ry)
	yaw = hullYaw
	pitch = CameraConfig.ThirdPerson.DefaultPitch

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local gym = workspace:FindFirstChild("Gym")
	local solid = {}
	if gym then
		for _, name in { "Buildings", "Seraph" } do
			local f = gym:FindFirstChild(name)
			if f then
				table.insert(solid, f)
			end
		end
	end
	params.FilterDescendantsInstances = solid

	ContextActionService:BindActionAtPriority(
		"FrameMove",
		onMove,
		false,
		PRIORITY,
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.Thumbstick1
	)
	ContextActionService:BindActionAtPriority(
		"FrameLook",
		onLook,
		false,
		PRIORITY,
		Enum.UserInputType.MouseMovement,
		Enum.KeyCode.Thumbstick2
	)
	ContextActionService:BindActionAtPriority(
		"FrameSprint",
		onSprint,
		false,
		PRIORITY,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:BindActionAtPriority(
		"FrameSink",
		onSink,
		false,
		PRIORITY,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA
	)

	setCharacterHidden(true)
	Camera.enter(model)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		step(root, model, params, dt)
	end)
	hudText()
end

local function leavePilot()
	if not piloting then
		return
	end
	piloting = false
	RunService:UnbindFromRenderStep(RENDER_NAME)
	for _, name in { "FrameMove", "FrameLook", "FrameSprint", "FrameSink" } do
		ContextActionService:UnbindAction(name)
	end
	Camera.leave()
	setCharacterHidden(false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local cam = workspace.CurrentCamera
		cam.CameraSubject = humanoid
	end
	-- This client owns the character, so it puts itself down beside the Frame (a server PivotTo is overwritten).
	local final = exitAt
	exitAt = nil
	if final and character and cockpit then
		task.spawn(function()
			local seat = cockpit:FindFirstChild("PilotSeat")
			local waited = 0
			-- Wait for the weld to go and PlatformStand to clear; pivoting before either left the pilot lying down.
			while
				((seat and seat.Parent) or (humanoid and humanoid.PlatformStand))
				and waited < F.ExitTimeout
			do
				waited += task.wait()
			end
			local drop = final
				* CFrame.new(
					F.ExitOffset,
					Scale.Gym.GroundTop - final.Position.Y + F.ExitDropHeight,
					0
				)
			local _, ry, _ = final:ToOrientation()
			character:PivotTo(CFrame.new(drop.Position) * CFrame.Angles(0, ry, 0))
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
			end
			if humanoid then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			end
		end)
	end
	hudText()
end

function Controller.start()
	local gym = workspace:WaitForChild("Gym")
	local model = gym:WaitForChild("Frame") :: Model
	local root = model:WaitForChild("Root") :: BasePart
	cockpit = model:WaitForChild("Cockpit") :: BasePart
	local board = Net.remote("FrameBoard")
	local exit = Net.remote("FrameExit")

	ContextActionService:BindAction("FrameInteract", function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if piloting then
			if not exitAt then
				local cf = root.CFrame
				local _, ry, _ = cf:ToOrientation()
				exitAt = cf
				exitSentAt = os.clock()
				exit:FireServer(cf.Position.X, cf.Position.Z, ry)
			end
			return Enum.ContextActionResult.Sink
		end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local flat = (hrp.Position - root.Position) * Vector3.new(1, 0, 1)
			if flat.Magnitude <= F.BoardRange then
				board:FireServer()
				return Enum.ContextActionResult.Sink
			end
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonX)

	ContextActionService:BindAction("FrameCamToggle", function(_, state)
		if state ~= Enum.UserInputState.Begin or not piloting then
			return Enum.ContextActionResult.Pass
		end
		Camera.toggle()
		hudText()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.T, Enum.KeyCode.DPadUp)

	ContextActionService:BindAction(
		"FrameMotion",
		function(_, state, input)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			local up = input.KeyCode == Enum.KeyCode.RightBracket
				or input.KeyCode == Enum.KeyCode.DPadRight
			motion = math.clamp(motion + (if up then MOTION.Step else -MOTION.Step), 0, 1)
			motion = math.floor(motion * 10 + 0.5) / 10
			hudText()
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.KeyCode.LeftBracket,
		Enum.KeyCode.RightBracket,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.DPadRight
	)

	local function sync()
		if model:GetAttribute("PilotId") == player.UserId then
			enterPilot(model, root)
		else
			leavePilot()
		end
	end
	model:GetAttributeChangedSignal("PilotId"):Connect(sync)
	player.CharacterAdded:Connect(function()
		leavePilot()
	end)
	sync()
	hudText()
end

return Controller
