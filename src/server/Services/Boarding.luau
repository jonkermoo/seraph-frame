--!strict
-- Board / exit the gym Frame. The server welds the pilot into the cockpit and hands the hull to the
-- pilot's client (network owner), which walks it. On exit the hull is anchored back on the ground.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Scale = require(ReplicatedStorage.Shared.Config.Scale)

local Boarding = {}

type FrameRefs = { model: Model, root: BasePart, cockpit: BasePart }

function Boarding.start(frame: FrameRefs)
	local cfg = Scale.Frame
	local pilot: Player? = nil
	local seatWeld: Weld? = nil
	local lastRequest: { [Player]: number } = {}

	local function setHullCollide(on: boolean)
		for _, p in frame.model:GetDescendants() do
			if p:IsA("BasePart") and p ~= frame.root and p ~= frame.cockpit then
				p.CanCollide = on
			end
		end
	end

	local function rateOk(player: Player): boolean
		local now = os.clock()
		if now - (lastRequest[player] or -math.huge) < cfg.BoardCooldown then
			return false
		end
		lastRequest[player] = now
		return true
	end

	-- Puts the hull back on the ground (yaw only) and anchors it. `final` is the pilot client's last hull
	-- position (x, z, yaw radians); the replicated root lags behind it, so the hull would jump back.
	-- The pilot's client places its own character beside the Frame: it owns the character, so a server
	-- PivotTo is overwritten by the client.
	local function release(player: Player, final: { x: number, z: number, yaw: number }?)
		if pilot ~= player then
			return
		end
		pilot = nil
		if seatWeld then
			seatWeld:Destroy()
			seatWeld = nil
		end
		local root = frame.root
		local _, yaw, _ = root.CFrame:ToOrientation()
		local x, z = root.Position.X, root.Position.Z
		if final then
			x, z, yaw = final.x, final.z, final.yaw
		end
		root.Anchored = true
		root.CFrame = CFrame.new(x, Scale.Gym.GroundTop + cfg.RootHeight, z)
			* CFrame.Angles(0, yaw, 0)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		setHullCollide(true)
		frame.model:SetAttribute("PilotId", 0)

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
	end

	-- Validates the exit payload: finite numbers, close to where the server last saw the hull.
	local function readFinal(
		x: unknown,
		z: unknown,
		yaw: unknown
	): { x: number, z: number, yaw: number }?
		if typeof(x) ~= "number" or typeof(z) ~= "number" or typeof(yaw) ~= "number" then
			return nil
		end
		local nx, nz, ny = x :: number, z :: number, yaw :: number
		if nx ~= nx or nz ~= nz or ny ~= ny or math.abs(ny) > math.pi * 4 then
			return nil
		end
		local p = frame.root.Position
		if (Vector2.new(nx, nz) - Vector2.new(p.X, p.Z)).Magnitude > cfg.ExitTrust then
			return nil
		end
		return { x = nx, z = nz, yaw = ny }
	end

	Net.remote("FrameBoard").OnServerEvent:Connect(function(player: Player)
		if not rateOk(player) or pilot ~= nil then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and hrp and hrp:IsA("BasePart")) or humanoid.Health <= 0 then
			return
		end
		local flat = (hrp.Position - frame.root.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude > cfg.BoardRange then
			return
		end

		pilot = player
		humanoid.PlatformStand = true
		hrp.CFrame = frame.cockpit.CFrame
		local weld = Instance.new("Weld")
		weld.Name = "PilotSeat"
		weld.Part0 = frame.cockpit
		weld.Part1 = hrp
		weld.C0 = CFrame.identity
		weld.Parent = frame.cockpit
		seatWeld = weld

		setHullCollide(false)
		frame.root.Anchored = false
		frame.root:SetNetworkOwner(player)
		frame.model:SetAttribute("PilotId", player.UserId)
	end)

	Net.remote("FrameExit").OnServerEvent
		:Connect(function(player: Player, x: unknown, z: unknown, yaw: unknown)
			if rateOk(player) then
				release(player, readFinal(x, z, yaw))
			end
		end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			release(player, nil)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		release(player, nil)
		lastRequest[player] = nil
	end)
end

return Boarding
