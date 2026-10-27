--!strict
-- Pilots are R6 whatever the place's avatar setting says (StarterPlayer.GameSettingsAvatar from the
-- project file did not reach Studio play tests). Each character is the player's own avatar on an R6 rig,
-- spawned on the gym's pilot pad.

local Players = game:GetService("Players")

local Avatar = {}

local function spawnPoint(): CFrame
	local gym = workspace:FindFirstChild("Gym")
	local pad = gym and gym:FindFirstChild("PilotSpawn")
	if pad and pad:IsA("BasePart") then
		return pad.CFrame + Vector3.new(0, 4, 0)
	end
	return CFrame.new(0, 10, 0)
end

local function spawnR6(player: Player)
	if not player.Parent then
		return
	end
	local okDesc, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(math.max(player.UserId, 1))
	end)
	if not okDesc then
		desc = Instance.new("HumanoidDescription")
	end
	local okModel, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)
	if not okModel or not model then
		warn("[Avatar] R6 build failed, default spawn:", model)
		player:LoadCharacter()
		return
	end

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
