--!strict
-- Pilots a Frame (P2): board / exit, then drive the client-owned hull with FrameMotor. The motor steps once
-- per physics step (PreSimulation) and writes the hull's DriveVelocity / DriveUpright targets; physics
-- moves the hull and resolves bumps with buildings and other Frames. The camera runs in RenderStep.
-- Every input goes through ContextActionService with keyboard/mouse and gamepad bindings.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraConfig = require(ReplicatedStorage.Shared.Config.Camera)
local FrameCam = require(ReplicatedStorage.Shared.Rules.FrameCam)
local FrameConfig = require(ReplicatedStorage.Shared.Config.Frame)
local FrameMotor = require(ReplicatedStorage.Shared.Rules.FrameMotor)
local Net = require(ReplicatedStorage.Shared.Net)
local Scale = require(ReplicatedStorage.Shared.Config.Scale)
local Autopilot = require(script.Parent.Autopilot)
local Camera = require(script.Parent.Camera)
local Hud = require(script.Parent.Hud)

local Controller = {}

local player = Players.LocalPlayer
local F = Scale.Frame
local M = FrameConfig.Motor
local LOOK = CameraConfig.Look
local MOTION = CameraConfig.Motion

local RENDER_NAME = "FrameCamera"
local PRIORITY = Enum.ContextActionPriority.High.Value
local RAY_DOWN = 2000
local ACTIONS = { "FrameMove", "FrameLook", "FrameSprint", "FrameDash", "FrameLeap" }

type Hull = {
	model: Model,
	root: BasePart,
	cockpit: BasePart,
	drive: LinearVelocity,
	upright: AlignOrientation,
}

local hulls: { [Model]: Hull } = {}
local piloting: Hull? = nil
local motor: FrameMotor.State = FrameMotor.new(0, M.DashCharges)
local groundParams: RaycastParams? = nil
local physicsConn: RBXScriptConnection? = nil
local actionRemote: RemoteEvent? = nil

local keys: { [Enum.KeyCode]: boolean } = {}
local stick1 = Vector2.zero
local stick2 = Vector2.zero
local mouseDelta = Vector2.zero
local sprintHeld = false
local sprintToggle = false
local dashPressed = false
local leapPressed = false
local leapHeld = false
local motion = MOTION.Default

local yaw = 0 -- camera look, degrees
local pitch = CameraConfig.ThirdPerson.DefaultPitch
local bobPhase = 0
local exitAt: CFrame? = nil -- hull CFrame sent with the exit request; the hull holds still until the server answers
local exitSentAt = 0
local autoTime = 0
local hudAcc = 0

local function hudText()
	local motionText = `motion {math.floor(motion * 100 + 0.5)}% ([ ] / D-pad L R)`
	if piloting then
		local speed = math.sqrt(motor.vx * motor.vx + motor.vz * motor.vz) / Scale.StudsPerMetre
		Hud.set(
			`{string.upper(motor.gait)} {math.floor(speed)} m/s  dash x{math.floor(motor.dashCharge)}  |  sprint Shift / L3  |  dash Ctrl / B  |  leap Space / A (hold = higher)  |  camera T / D-pad up  |  {motionText}  |  exit E / X`
		)
	else
		Hud.set(`On foot  |  walk to a Frame's feet, board with E / X  |  {motionText}`)
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

local function nearestOther(pos: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDist = math.huge
	for model, hull in hulls do
		if hull ~= piloting and model.Parent then
			local d = (hull.root.Position - pos).Magnitude
			if d < bestDist then
				best, bestDist = hull.root.Position, d
			end
		end
	end
	return best
end

-- One motor step per physics step: read what physics did, step the motor, write the drive targets.
local function physicsStep(hull: Hull, dt: number)
	local root = hull.root
	local v = root.AssemblyLinearVelocity
	FrameMotor.collide(motor, v.X, v.Z, M)

	local pos = root.Position
	local hit = workspace:Raycast(pos, Vector3.new(0, -RAY_DOWN, 0), groundParams :: RaycastParams)
	local height = if hit then pos.Y - hit.Position.Y - F.RootHeight else nil

	local stick = moveInput()
	local input: FrameMotor.Input = {
		moveX = stick.X,
		moveY = stick.Y,
		camYaw = yaw,
		sprint = sprintHeld or sprintToggle,
		dashPressed = dashPressed,
		leapPressed = leapPressed,
		leapHeld = leapHeld,
	}
	local auto = if RunService:IsStudio() then player:GetAttribute("FrameAutopilot") else nil
	if auto == "loop" or auto == "ram" then
		autoTime += dt
		input = Autopilot.input(auto :: Autopilot.Mode, autoTime, dt, motor, pos, nearestOther(pos))
		yaw = input.camYaw
	end
	dashPressed, leapPressed = false, false
	if stick.Magnitude < 0.05 then
		sprintToggle = false
	end
	if exitAt then
		if os.clock() - exitSentAt > F.ExitTimeout then
			exitAt = nil -- server refused (cooldown): keep driving
		else
			input.moveX, input.moveY = 0, 0
			input.dashPressed, input.leapPressed, input.leapHeld = false, false, false
			motor.vx, motor.vz = 0, 0
		end
	end

	local before = motor.gait
	FrameMotor.step(motor, input, { height = height }, M, dt)
	local remote = actionRemote
	if remote and motor.gait ~= before then
		if motor.gait == "dash" then
			remote:FireServer("dash")
		elseif before == "windup" and motor.gait == "air" then
			remote:FireServer("leap")
		end
	end

	hull.drive.VectorVelocity = Vector3.new(motor.vx, motor.vy, motor.vz)
	hull.upright.CFrame = CFrame.Angles(0, math.rad(motor.yaw), 0)
end

local function renderStep(hull: Hull, dt: number)
	local invert = if LOOK.InvertY then -1 else 1
	yaw -= mouseDelta.X * LOOK.MouseDegPerPixel
	pitch -= mouseDelta.Y * LOOK.MouseDegPerPixel * invert
	mouseDelta = Vector2.zero
	yaw -= FrameCam.stick(stick2.X, LOOK.GamepadDeadzone, LOOK.GamepadExpo) * LOOK.GamepadYawDegPerSec * dt
	pitch += FrameCam.stick(stick2.Y, LOOK.GamepadDeadzone, LOOK.GamepadExpo) * LOOK.GamepadPitchDegPerSec * dt * invert
	yaw = FrameCam.wrap(yaw)
	local pMin = math.min(CameraConfig.FirstPerson.PitchMin, CameraConfig.ThirdPerson.PitchMin)
	local pMax = math.max(CameraConfig.FirstPerson.PitchMax, CameraConfig.ThirdPerson.PitchMax)
	pitch = math.clamp(pitch, pMin, pMax)

	local speed = math.sqrt(motor.vx * motor.vx + motor.vz * motor.vz)
	local moving, sprintFrac = FrameCam.gait(speed, M.WalkSpeed, M.SprintSpeed)
	if not motor.grounded or motor.gait == "dash" then
		moving = 0 -- no footfalls in the air or mid-dash
	end
	local stepSeconds = FrameCam.lerp(MOTION.WalkStepSeconds, MOTION.SprintStepSeconds, sprintFrac)
	bobPhase += dt / stepSeconds * moving

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	Camera.update({
		root = hull.root,
		model = hull.model,
		yaw = yaw,
		pitch = pitch,
		bobPhase = bobPhase,
		moving = moving,
		sprint = sprintFrac,
		motion = motion,
	}, dt)

	hudAcc += dt
	if hudAcc >= 0.25 then
		hudAcc = 0
		hudText()
	end
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

local function onDash(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		dashPressed = true
	end
	return Enum.ContextActionResult.Sink
end

local function onLeap(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		leapPressed = true
		leapHeld = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		leapHeld = false
	end
	return Enum.ContextActionResult.Sink
end

local function enterPilot(hull: Hull)
	if piloting == hull then
		return
	end
	piloting = hull
	keys = {}
	stick1, stick2, mouseDelta = Vector2.zero, Vector2.zero, Vector2.zero
	sprintHeld, sprintToggle, dashPressed, leapPressed, leapHeld = false, false, false, false, false
	exitAt = nil
	autoTime = 0
	local _, ry, _ = hull.root.CFrame:ToOrientation()
	motor = FrameMotor.new(math.deg(ry), M.DashCharges)
	yaw = motor.yaw
	pitch = CameraConfig.ThirdPerson.DefaultPitch

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { hull.model }
	params.CollisionGroup = FrameConfig.CollisionGroups.Hull
	params.RespectCanCollide = true
	groundParams = params

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
		"FrameDash",
		onDash,
		false,
		PRIORITY,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:BindActionAtPriority(
		"FrameLeap",
		onLeap,
		false,
		PRIORITY,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA
	)

	setCharacterHidden(true)
	Camera.enter(hull.model)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		renderStep(hull, dt)
	end)
	physicsConn = RunService.PreSimulation:Connect(function(dt)
		physicsStep(hull, dt)
	end)
	hudText()
end

local function leavePilot()
	local hull = piloting
	if not hull then
		return
	end
	piloting = nil
	RunService:UnbindFromRenderStep(RENDER_NAME)
	if physicsConn then
		physicsConn:Disconnect()
		physicsConn = nil
	end
	for _, name in ACTIONS do
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
	if final and character then
		task.spawn(function()
			local seat = hull.cockpit:FindFirstChild("PilotSeat")
			local waited = 0
			-- Wait for the weld to go and PlatformStand to clear; pivoting before either left the pilot lying down.
			while
				((seat and seat.Parent) or (humanoid and humanoid.PlatformStand))
				and waited < F.ExitTimeout
			do
				waited += task.wait()
			end
			-- Beside the Frame on whatever it stands on (the hull is parked on the ground or roof below).
			local drop = final * CFrame.new(F.ExitOffset, -F.RootHeight + F.ExitDropHeight, 0)
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

local function sync()
	for model, hull in hulls do
		if model:GetAttribute("PilotId") == player.UserId then
			enterPilot(hull)
			return
		end
	end
	leavePilot()
end

local function addHull(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("PilotId") == nil then
		return
	end
	local root = model:WaitForChild("Root") :: BasePart
	local hull: Hull = {
		model = model,
		root = root,
		cockpit = model:WaitForChild("Cockpit") :: BasePart,
		drive = root:WaitForChild("DriveVelocity") :: LinearVelocity,
		upright = root:WaitForChild("DriveUpright") :: AlignOrientation,
	}
	hulls[model] = hull
	model:GetAttributeChangedSignal("PilotId"):Connect(sync)
	sync()
end

function Controller.start()
	local gym = workspace:WaitForChild("Gym")
	local board = Net.remote("FrameBoard")
	local exit = Net.remote("FrameExit")
	actionRemote = Net.remote("FrameAction")

	ContextActionService:BindAction("FrameInteract", function(_, state)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local hull = piloting
		if hull then
			-- Exit only standing on something and not mid-dash, so the parked hull matches what the pilot saw.
			if not exitAt and motor.grounded and motor.dashLeft <= 0 then
				local cf = hull.root.CFrame
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
			for _, h in hulls do
				local flat = (hrp.Position - h.root.Position) * Vector3.new(1, 0, 1)
				if flat.Magnitude <= F.BoardRange and h.model:GetAttribute("PilotId") == 0 then
					board:FireServer()
					return Enum.ContextActionResult.Sink
				end
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

	player.CharacterAdded:Connect(function()
		leavePilot()
	end)
	gym.ChildAdded:Connect(function(child)
		task.spawn(addHull, child)
	end)
	for _, child in gym:GetChildren() do
		task.spawn(addHull, child)
	end
	hudText()
end

return Controller
