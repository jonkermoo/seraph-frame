--!strict
-- P1 scale gym: builds the flat test area with block-outs (ground, pilot spawn,
-- 300-stud Seraph, 4 city-scale buildings, a few car-sized props and a 10 m post).
-- Every piece is a plain box so the camera can test "inside a building" exactly.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Scale = require(ReplicatedStorage.Shared.Config.Scale)

local Gym = {}

export type PartSpec = {
	name: string,
	size: Vector3,
	pos: Vector3, -- centre, relative to the model's ground point
	color: Color3,
	shape: Enum.PartType?,
	material: Enum.Material?,
	head: boolean?, -- hidden locally in first person
}

local SERAPH = Color3.fromRGB(226, 222, 210)
local CORE = Color3.fromRGB(200, 20, 30)

-- Seraph block-out, facing +Z (toward the Frame). Top of the crown is at 300.
local SERAPH_PARTS: { PartSpec } = {
	{
		name = "LegL",
		size = Vector3.new(24, 70, 24),
		pos = Vector3.new(-25, 35, 0),
		color = SERAPH,
	},
	{ name = "LegR", size = Vector3.new(24, 70, 24), pos = Vector3.new(25, 35, 0), color = SERAPH },
	{
		name = "Body",
		size = Vector3.new(90, 170, 70),
		pos = Vector3.new(0, 150, 0),
		color = SERAPH,
	},
	{
		name = "ArmL",
		size = Vector3.new(20, 150, 20),
		pos = Vector3.new(-60, 160, 0),
		color = SERAPH,
	},
	{
		name = "ArmR",
		size = Vector3.new(20, 150, 20),
		pos = Vector3.new(60, 160, 0),
		color = SERAPH,
	},
	{ name = "Neck", size = Vector3.new(30, 6, 30), pos = Vector3.new(0, 238, 0), color = SERAPH },
	{ name = "Head", size = Vector3.new(50, 50, 50), pos = Vector3.new(0, 265, 0), color = SERAPH },
	{ name = "Crown", size = Vector3.new(6, 10, 6), pos = Vector3.new(0, 295, 0), color = SERAPH },
	{
		name = "Core",
		size = Vector3.new(28, 28, 28),
		pos = Vector3.new(0, 170, 36),
		color = CORE,
		shape = Enum.PartType.Ball,
		material = Enum.Material.Neon,
	},
}

function Gym.part(spec: PartSpec, origin: CFrame, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = spec.name
	p.Size = spec.size
	p.CFrame = origin * CFrame.new(spec.pos)
	p.Color = spec.color
	p.Material = spec.material or Enum.Material.SmoothPlastic
	if spec.shape then
		p.Shape = spec.shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if spec.head then
		p:SetAttribute("FrameHead", true)
	end
	p.Parent = parent
	return p
end

function Gym.box(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): BasePart
	return Gym.part({ name = name, size = size, pos = Vector3.zero, color = color }, cf, parent)
end

-- Trap: a place's default Baseplate (top at y 0) z-fights a code-built ground. Lower it out of the way.
local function lowerBaseplate()
	local base = workspace:FindFirstChild("Baseplate")
	if base and base:IsA("BasePart") and math.abs(base.Position.Y + base.Size.Y / 2) < 0.01 then
		base.CFrame = base.CFrame * CFrame.new(0, -20, 0)
		base.Transparency = 1
		base.CanCollide = false
	end
end

local function buildGround(gym: Instance)
	local cfg = Scale.Gym
	local t = cfg.GroundTile
	local folder = Instance.new("Folder")
	folder.Name = "Ground"
	folder.Parent = gym
	for ix = 0, 1 do
		for iz = 0, 1 do
			local cx = (ix - 0.5) * t
			local cz = (iz - 0.5) * t
			local g = Gym.box(
				"Tile",
				Vector3.new(t, 4, t),
				CFrame.new(cx, cfg.GroundTop - 2, cz),
				Color3.fromRGB(60, 62, 66),
				folder
			)
			g.Anchored = true
			g.Material = Enum.Material.Asphalt
		end
	end
end

local function buildCity(gym: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Buildings"
	folder.Parent = gym
	for i, b in Scale.Gym.Buildings do
		local shade = 150 + i * 15
		local p = Gym.box(
			b.name,
			Vector3.new(b.w, b.h, b.d),
			CFrame.new(b.x, Scale.Gym.GroundTop + b.h / 2, b.z),
			Color3.fromRGB(shade, shade - 10, shade - 25),
			folder
		)
		p.Anchored = true
		p.Material = Enum.Material.Concrete
	end

	-- Pilot-scale references: car-sized blocks (4.5 m) along the kerb and a 10 m post.
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = gym
	for i = 0, 4 do
		local car = Gym.box(
			"Car",
			Vector3.new(7, 5, 16),
			CFrame.new(-70, Scale.Gym.GroundTop + 2.5, -60 - i * 60),
			Color3.fromHSV(i / 5, 0.6, 0.8),
			props
		)
		car.Anchored = true
	end
	local h = Scale.Gym.MarkerHeight
	local post = Gym.box(
		"Post10m",
		Vector3.new(2, h, 2),
		CFrame.new(80, Scale.Gym.GroundTop + h / 2, -40),
		Color3.new(1, 1, 0),
		props
	)
	post.Anchored = true
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(80, 30)
	sign.StudsOffset = Vector3.new(0, h / 2 + 3, 0)
	sign.AlwaysOnTop = true
	sign.MaxDistance = 400
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 0)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Text = "10 m"
	label.Parent = sign
	sign.Parent = post
end

local function buildSeraph(gym: Instance)
	local model = Instance.new("Model")
	model.Name = "Seraph"
	local pos = Scale.Gym.SeraphPosition
	local origin = CFrame.new(pos.x, Scale.Gym.GroundTop, pos.z) * CFrame.Angles(0, math.pi, 0)
	for _, spec in SERAPH_PARTS do
		Gym.part(spec, origin, model).Anchored = true
	end
	model.WorldPivot = origin
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = gym
end

local function buildSpawn(gym: Instance)
	local s = Scale.Gym.PilotSpawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PilotSpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(s.x, Scale.Gym.GroundTop + 0.5, s.z)
		* CFrame.Angles(0, math.rad(90), 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(80, 180, 90)
	spawn.Parent = gym
end

local function addHaze()
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.3
		atmo.Offset = 0.2
		atmo.Parent = Lighting
	end
end

function Gym.start()
	lowerBaseplate()
	addHaze()
	local gym = Instance.new("Folder")
	gym.Name = "Gym"
	buildGround(gym)
	buildCity(gym)
	buildSeraph(gym)
	buildSpawn(gym)
	gym.Parent = workspace
end

return Gym
