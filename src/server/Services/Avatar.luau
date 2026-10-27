--!strict
-- Every pilot is our own plain R6 body; players' Roblox avatars are never loaded (DECISIONS: custom
-- pilots only). R6 whatever the place's avatar setting says (StarterPlayer.GameSettingsAvatar from the
-- project file did not reach Studio play tests). Spawned on the gym's pilot pad.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Scale = require(ReplicatedStorage.Shared.Config.Scale)

local Avatar = {}

local function spawnPoint(): CFrame
	local gym = workspace:FindFirstChild("Gym")
	local pad = gym and gym:FindFirstChild("PilotSpawn")
	if pad and pad:IsA("BasePart") then
		return pad.CFrame + Vector3.new(0, 4, 0)
	end
	return CFrame.new(0, 10, 0)
end

-- A blank description: default R6 body parts, no face, hair, accessories or clothing, one grey colour.
local function plainDescription(): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")
	local c = Scale.Pilot.Color
	local grey = Color3.fromRGB(c.r, c.g, c.b)
	desc.HeadColor = grey
	desc.TorsoColor = grey
	desc.LeftArmColor = grey
	desc.RightArmColor = grey
	desc.LeftLegColor = grey
	desc.RightLegColor = grey
	return desc
end

local function stripLooks(model: Model)
	for _, d in model:GetDescendants() do
		if
			d:IsA("Accessory")
			or d:IsA("Clothing")
			or d:IsA("ShirtGraphic")
			or d:IsA("CharacterMesh")
			or (d:IsA("Decal") and d.Name == "face")
		then
			d:Destroy()
		end
	end
end

local function spawnR6(player: Player)
	if not player.Parent then
		return
	end
	local desc = plainDescription()
	local okModel, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)
	if not okModel or not model then
		-- Never fall back to LoadCharacter: that would load the player's own avatar.
		warn("[Avatar] R6 build failed, retrying:", model)
		task.delay(Players.RespawnTime, spawnR6, player)
		return
	end

	stripLooks(model)
	local old = player.Character
	model.Name = player.Name
	model:PivotTo(spawnPoint())
	player.Character = model
	model.Parent = workspace
	if old and old ~= model then
		old:Destroy()
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			task.wait(Players.RespawnTime)
			if player.Character == model then
				spawnR6(player)
			end
		end)
	end
end

function Avatar.start()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(spawnR6)
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not (humanoid and humanoid.RigType == Enum.HumanoidRigType.R6) then
			task.spawn(spawnR6, player)
		end
	end
end

return Avatar
