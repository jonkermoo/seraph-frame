--!strict
-- Frame hulls (P2): one per gym slot. A hull has no Humanoid: an invisible root at the pelvis, an invisible
-- collision cylinder in the FrameHull group (bumps buildings and other Frames, never pilots) and massless
-- block-out parts welded on. Parked hulls are anchored. A piloted hull is network-owned by its pilot, whose
-- client drives it with FrameMotor through the DriveVelocity / DriveUpright constraints built here; the
-- server checks the owner every OwnerCheckSeconds and puts it back if it ever changed (counted).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FrameConfig = require(ReplicatedStorage.Shared.Config.Frame)
local Net = require(ReplicatedStorage.Shared.Net)
local Scale = require(ReplicatedStorage.Shared.Config.Scale)
local Gym = require(script.Parent.Gym)

local Frame = {}

export type Hull = {
	model: Model,
	root: BasePart,
	cockpit: BasePart,
	collider: BasePart,
	drive: LinearVelocity,
	upright: AlignOrientation,
	pilot: Player?,
	ownerFlips: number,
}

type PartSpec = Gym.PartSpec

local HULL = Color3.fromRGB(88, 96, 120)
local HULL_DARK = Color3.fromRGB(52, 56, 70)
local VISOR = Color3.fromRGB(255, 150, 40)
local ACTIONS = { dash = true, leap = true }

-- Frame block-out, facing -Z, ground point at the origin. Top of the horn is at 140.
local FRAME_PARTS: { PartSpec } = {
	{
		name = "LegL",
		size = Vector3.new(16, 62, 18),
		pos = Vector3.new(-13, 31, 0),
		color = HULL_DARK,
	},
	{
		name = "LegR",
		size = Vector3.new(16, 62, 18),
		pos = Vector3.new(13, 31, 0),
		color = HULL_DARK,
	},
	{ name = "Pelvis", size = Vector3.new(42, 12, 22), pos = Vector3.new(0, 66, 0), color = HULL },
	{ name = "Torso", size = Vector3.new(46, 40, 26), pos = Vector3.new(0, 92, 0), color = HULL },
	{
		name = "ArmL",
		size = Vector3.new(12, 56, 14),
		pos = Vector3.new(-31, 80, 0),
		color = HULL_DARK,
	},
	{
		name = "ArmR",
		size = Vector3.new(12, 56, 14),
		pos = Vector3.new(31, 80, 0),
		color = HULL_DARK,
	},
	{ name = "PadL", size = Vector3.new(18, 12, 20), pos = Vector3.new(-31, 108, 0), color = HULL },
	{ name = "PadR", size = Vector3.new(18, 12, 20), pos = Vector3.new(31, 108, 0), color = HULL },
	{
		name = "Neck",
		size = Vector3.new(10, 6, 10),
		pos = Vector3.new(0, 115, 0),
		color = HULL_DARK,
		head = true,
	},
	{
		name = "Head",
		size = Vector3.new(16, 18, 18),
		pos = Vector3.new(0, 125, 0),
		color = HULL,
		head = true,
	},
	{
		name = "Visor",
		size = Vector3.new(12, 3, 1),
		pos = Vector3.new(0, 127, -9.5),
		color = VISOR,
		material = Enum.Material.Neon,
		head = true,
	},
	{
		name = "Horn",
		size = Vector3.new(2, 6, 2),
		pos = Vector3.new(0, 137, -2),
		color = VISOR,
		head = true,
	},
}

local hulls: { Hull } = {}
local G = FrameConfig.CollisionGroups

local function registerGroups()
	for _, name in { G.Hull, G.Pilot } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(G.Hull, G.Pilot, false)
end

-- Raycast params that see what a hull stands on: everything the FrameHull group collides with
-- (ground, buildings, other hulls), never pilots or non-colliding visuals.
function Frame.groundParams(own: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { own }
	params.CollisionGroup = G.Hull
	params.RespectCanCollide = true
	return params
end

local function setVisualCollide(hull: Hull, on: boolean)
	for _, p in hull.model:GetDescendants() do
		if p:IsA("BasePart") and p ~= hull.root and p ~= hull.cockpit and p ~= hull.collider then
			p.CanCollide = on
		end
	end
end

local function build(
	index: number,
	slot: { x: number, z: number, yaw: number },
	parent: Instance
): Hull
	local cfg = Scale.Frame
	local hc = FrameConfig.Hull
	local origin = CFrame.new(slot.x, Scale.Gym.GroundTop, slot.z)
		* CFrame.Angles(0, math.rad(slot.yaw), 0)
	local model = Instance.new("Model")
	model.Name = `Frame{index}`

	local props = PhysicalProperties.new(hc.Density, hc.Friction, 0, 100, 100)
	local root = Gym.box(
		"Root",
		Vector3.new(20, 20, 20),
		origin * CFrame.new(0, cfg.RootHeight, 0),
		HULL,
		model
	)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Anchored = true
	root.CollisionGroup = G.Hull
	root.CustomPhysicalProperties = props
	model.PrimaryPart = root

	-- Vertical cylinder (a Cylinder's axis is its X), from ColliderBottom to ColliderTop above the ground.
	local height = hc.ColliderTop - hc.ColliderBottom
	local collider = Gym.box(
		"Collider",
		Vector3.new(height, hc.ColliderRadius * 2, hc.ColliderRadius * 2),
		origin
			* CFrame.new(0, hc.ColliderBottom + height / 2, 0)
			* CFrame.Angles(0, 0, math.rad(90)),
		HULL,
		model
	)
	collider.Shape = Enum.PartType.Cylinder
	collider.Transparency = 1
	collider.CanTouch = false
	collider.CollisionGroup = G.Hull
	collider.CustomPhysicalProperties = props

	local cockpit = Gym.box(
		"Cockpit",
		Vector3.new(6, 6, 10),
		origin * CFrame.new(0, cfg.CockpitHeight, 6),
		HULL_DARK,
		model
	)
	cockpit.Transparency = 1
	cockpit.CanCollide = false
	cockpit.Massless = true

	local welded = { collider, cockpit }
	for _, spec in FRAME_PARTS do
		local p = Gym.part(spec, origin, model)
		p.Massless = true
		p.CanTouch = false
		table.insert(welded, p)
	end
	-- Trap: WeldConstraints re-record offsets when reactivated; use Weld with an explicit C0.
	for _, p in welded do
		local weld = Instance.new("Weld")
		weld.Part0 = root
		weld.Part1 = p
		weld.C0 = root.CFrame:ToObjectSpace(p.CFrame)
		weld.Parent = p
	end

	-- Drive constraints: the pilot's client writes their targets every physics step. Distinct names
	-- (trap: FindFirstChild matched an Attachment named like its force).
	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.Parent = root
	local drive = Instance.new("LinearVelocity")
	drive.Name = "DriveVelocity"
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	drive.VectorVelocity = Vector3.zero
	drive.Enabled = false
	drive.Parent = root
	local upright = Instance.new("AlignOrientation")
	upright.Name = "DriveUpright"
	upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
	upright.Attachment0 = attachment
	upright.RigidityEnabled = true
	upright.CFrame = CFrame.Angles(0, math.rad(slot.yaw), 0)
	upright.Enabled = false
	upright.Parent = root

	model.WorldPivot = origin
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("PilotId", 0)
	model:SetAttribute("OwnerFlips", 0)
	model:SetAttribute("OwnerChecks", 0)
	model:SetAttribute("Action", "")
	model:SetAttribute("ActionAt", 0)
	model.Parent = parent
	return {
		model = model,
		root = root,
		cockpit = cockpit,
		collider = collider,
		drive = drive,
		upright = upright,
		pilot = nil,
		ownerFlips = 0,
	}
end

function Frame.hulls(): { Hull }
	return hulls
end

function Frame.hullOf(player: Player): Hull?
	for _, hull in hulls do
		if hull.pilot == player then
			return hull
		end
	end
	return nil
end

-- Hands the hull to its pilot: unanchored, driven by the pilot's client, network-owned by the pilot.
function Frame.board(hull: Hull, player: Player)
	hull.pilot = player
	setVisualCollide(hull, false)
	local _, yaw, _ = hull.root.CFrame:ToOrientation()
	hull.upright.CFrame = CFrame.Angles(0, yaw, 0)
	hull.drive.VectorVelocity = Vector3.zero
	hull.root.Anchored = false
	hull.drive.MaxForce = hull.root.AssemblyMass * FrameConfig.Motor.DriveAccel
	hull.drive.Enabled = true
	hull.upright.Enabled = true
	hull.root:SetNetworkOwner(player)
	hull.model:SetAttribute("PilotId", player.UserId)
end

-- Parks the hull, anchored and upright at `cf` (the root's CFrame).
function Frame.park(hull: Hull, cf: CFrame)
	hull.pilot = nil
	hull.drive.Enabled = false
	hull.upright.Enabled = false
	hull.root.Anchored = true
	hull.root.CFrame = cf
	hull.root.AssemblyLinearVelocity = Vector3.zero
	hull.root.AssemblyAngularVelocity = Vector3.zero
	setVisualCollide(hull, true)
	hull.model:SetAttribute("PilotId", 0)
end

-- Ownership keeper: a piloted hull's owner must stay its pilot (bumps between two owned assemblies
-- must never move it). Any change is counted on the model (OwnerFlips) and undone.
local function keepOwners()
	for _, hull in hulls do
		local pilot = hull.pilot
		if pilot and not hull.root.Anchored then
			hull.model:SetAttribute(
				"OwnerChecks",
				(hull.model:GetAttribute("OwnerChecks") :: number? or 0) + 1
			)
			local owner = hull.root:GetNetworkOwner()
			if owner ~= pilot then
				hull.ownerFlips += 1
				hull.model:SetAttribute("OwnerFlips", hull.ownerFlips)
				warn(
					`[Frame] {hull.model.Name} owner flipped to {owner and owner.Name or "server"}, back to {pilot.Name}`
				)
				hull.root:SetNetworkOwner(pilot)
			end
		end
	end
end

function Frame.start()
	registerGroups()
	local gym = workspace:WaitForChild("Gym")
	for i, slot in FrameConfig.Slots do
		table.insert(hulls, build(i, slot, gym))
	end

	-- Pilots never collide with hulls (no crushing; the seated pilot rides inside its own hull).
	local function groupCharacter(character: Model)
		for _, p in character:GetDescendants() do
			if p:IsA("BasePart") then
				p.CollisionGroup = G.Pilot
			end
		end
		character.DescendantAdded:Connect(function(p)
			if p:IsA("BasePart") then
				p.CollisionGroup = G.Pilot
			end
		end)
	end
	local function watch(player: Player)
		player.CharacterAdded:Connect(groupCharacter)
		if player.Character then
			groupCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= FrameConfig.OwnerCheckSeconds then
			acc = 0
			keepOwners()
		end
	end)

	-- Action intents (dash, leap): stamped on the model for watchers and the FrameGuard log.
	local lastAction: { [Player]: number } = {}
	Net.remote("FrameAction").OnServerEvent:Connect(function(player: Player, action: unknown)
		if typeof(action) ~= "string" or not ACTIONS[action :: string] then
			return
		end
		local now = os.clock()
		if now - (lastAction[player] or -math.huge) < FrameConfig.ActionMinInterval then
			return
		end
		lastAction[player] = now
		local hull = Frame.hullOf(player)
		if hull then
			hull.model:SetAttribute("Action", action)
			hull.model:SetAttribute("ActionAt", workspace:GetServerTimeNow())
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return Frame
