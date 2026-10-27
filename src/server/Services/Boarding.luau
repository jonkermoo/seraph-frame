--!strict
-- Board / exit a Frame. Board takes the nearest free hull in range: the server welds the pilot into its
-- cockpit and hands the hull to the pilot (Frame.board). Exit parks the hull at the pilot client's final
-- position on the ground (or roof) below it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Scale = require(ReplicatedStorage.Shared.Config.Scale)
local Frame = require(script.Parent.Frame)

local Boarding = {}

function Boarding.start()
	local cfg = Scale.Frame
	local seatWelds: { [Player]: Weld } = {}
	local lastRequest: { [Player]: number } = {}

	local function rateOk(player: Player): boolean
		local now = os.clock()
		if now - (lastRequest[player] or -math.huge) < cfg.BoardCooldown then
			return false
		end
		lastRequest[player] = now
		return true
	end

	-- Root CFrame for a hull parked at (x, z) facing yaw: on whatever the hull would stand on there.
	local function parkCFrame(hull: Frame.Hull, x: number, z: number, yaw: number): CFrame
		local top = hull.root.Position.Y + cfg.Height
		local hit = workspace:Raycast(
			Vector3.new(x, top, z),
			Vector3.new(0, -(top - Scale.Gym.GroundTop + 50), 0),
			Frame.groundParams(hull.model)
		)
		local groundY = if hit then hit.Position.Y else Scale.Gym.GroundTop
		return CFrame.new(x, groundY + cfg.RootHeight, z) * CFrame.Angles(0, yaw, 0)
	end

	-- `final` is the pilot client's last hull position (x, z, yaw radians); the replicated root lags
	-- behind it, so parking at the replicated one would make the hull jump back.
	-- The pilot's client places its own character beside the Frame (it owns the character).
	local function release(player: Player, final: { x: number, z: number, yaw: number }?)
		local hull = Frame.hullOf(player)
		if not hull then
			return
		end
		local weld = seatWelds[player]
		if weld then
			weld:Destroy()
			seatWelds[player] = nil
		end
		local _, yaw, _ = hull.root.CFrame:ToOrientation()
		local x, z = hull.root.Position.X, hull.root.Position.Z
		if final then
			x, z, yaw = final.x, final.z, final.yaw
		end
		Frame.park(hull, parkCFrame(hull, x, z, yaw))

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
	end

	-- Validates the exit payload: finite numbers, close to where the server last saw the hull.
	local function readFinal(
		hull: Frame.Hull,
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
		local p = hull.root.Position
		if (Vector2.new(nx, nz) - Vector2.new(p.X, p.Z)).Magnitude > cfg.ExitTrust then
			return nil
		end
		return { x = nx, z = nz, yaw = ny }
	end

	Net.remote("FrameBoard").OnServerEvent:Connect(function(player: Player)
		if not rateOk(player) or Frame.hullOf(player) then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and hrp and hrp:IsA("BasePart")) or humanoid.Health <= 0 then
			return
		end
		local best: Frame.Hull? = nil
		local bestDist = cfg.BoardRange
		for _, hull in Frame.hulls() do
			if hull.pilot == nil then
				local flat = (hrp.Position - hull.root.Position) * Vector3.new(1, 0, 1)
				if flat.Magnitude <= bestDist then
					best, bestDist = hull, flat.Magnitude
				end
			end
		end
		local hull = best
		if not hull then
			return
		end

		-- Anchor at once on death: waiting for CharacterRemoving left the hull drifting ~1 s.
		humanoid.Died:Once(function()
			release(player, nil)
		end)
		humanoid.PlatformStand = true
		hrp.CFrame = hull.cockpit.CFrame
		local weld = Instance.new("Weld")
		weld.Name = "PilotSeat"
		weld.Part0 = hull.cockpit
		weld.Part1 = hrp
		weld.C0 = CFrame.identity
		weld.Parent = hull.cockpit
		seatWelds[player] = weld
		Frame.board(hull, player)
	end)

	Net.remote("FrameExit").OnServerEvent
		:Connect(function(player: Player, x: unknown, z: unknown, yaw: unknown)
			local hull = Frame.hullOf(player)
			if hull and rateOk(player) then
				release(player, readFinal(hull, x, z, yaw))
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
