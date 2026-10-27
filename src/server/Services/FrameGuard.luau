--!strict
-- FrameGuard (server): samples every piloted hull each Heartbeat and checks its replicated motion against
-- the envelope in Rules/FrameGuard. P2 prototype: strikes are logged and counted only (no snap-back, no
-- kick). Counts and peaks go on each hull model (GuardStrikes, GuardPeak*) and the total on workspace
-- (FrameGuardStrikes) so a long scripted run can be read back. GuardMs is the average cost per Heartbeat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FrameConfig = require(ReplicatedStorage.Shared.Config.Frame)
local Guard = require(ReplicatedStorage.Shared.Rules.FrameGuard)
local Scale = require(ReplicatedStorage.Shared.Config.Scale)
local Frame = require(script.Parent.Frame)

local FrameGuard = {}

local G = FrameConfig.Guard
local RAY_DOWN = 2000

type Watch = {
	state: Guard.State,
	pilot: Player?,
	params: RaycastParams,
	strikes: number,
	samples: number,
}

function FrameGuard.start()
	local watches: { [Frame.Hull]: Watch } = {}
	local total = 0
	local costSum, costTicks = 0, 0
	local logAcc = 0
	workspace:SetAttribute("FrameGuardStrikes", 0)

	local function watchOf(hull: Frame.Hull): Watch
		local w = watches[hull]
		if not w then
			w = {
				state = Guard.new(G),
				pilot = nil,
				params = Frame.groundParams(hull.model),
				strikes = 0,
				samples = 0,
			}
			watches[hull] = w
		end
		return w
	end

	local function publish(hull: Frame.Hull, w: Watch)
		local m = hull.model
		local s = w.state
		m:SetAttribute("GuardStrikes", w.strikes)
		m:SetAttribute("GuardSamples", w.samples)
		m:SetAttribute("GuardPeakTick", math.floor(s.peakTick * 10) / 10)
		m:SetAttribute("GuardPeakRise", math.floor(s.peakRise * 10) / 10)
		m:SetAttribute("GuardPeakAir", math.floor(s.peakAir * 100) / 100)
		m:SetAttribute("GuardMinDash", math.floor(s.minDash * 10) / 10)
	end

	RunService.Heartbeat:Connect(function(dt)
		local t0 = os.clock()
		for _, hull in Frame.hulls() do
			local w = watchOf(hull)
			local pilot = hull.pilot
			if pilot ~= w.pilot then
				-- Board / exit: the motion history starts again.
				w.pilot = pilot
				Guard.reset(w.state, G)
			end
			if pilot and not hull.root.Anchored then
				local pos = hull.root.Position
				local hit = workspace:Raycast(pos, Vector3.new(0, -RAY_DOWN, 0), w.params)
				local height = if hit then pos.Y - hit.Position.Y - Scale.Frame.RootHeight else nil
				local reasons = Guard.step(w.state, {
					t = os.clock(),
					x = pos.X,
					y = pos.Y,
					z = pos.Z,
					height = height,
				}, G)
				w.samples += 1
				for _, reason in reasons do
					w.strikes += 1
					total += 1
					workspace:SetAttribute("FrameGuardStrikes", total)
					local action = hull.model:GetAttribute("Action")
					local at = hull.model:GetAttribute("ActionAt") :: number? or 0
					local ago = math.floor((workspace:GetServerTimeNow() - at) * 100) / 100
					local where = `{math.floor(pos.X)}, {math.floor(pos.Y)}, {math.floor(pos.Z)}`
					warn(
						`[FrameGuard] strike {reason} {hull.model.Name} pilot {pilot.Name} at ({where}) last action {action} {ago} s ago`
					)
				end
			end
		end
		costSum += os.clock() - t0
		costTicks += 1
		logAcc += dt
		if logAcc >= G.SampleLog then
			logAcc = 0
			for hull, w in watches do
				publish(hull, w)
			end
			workspace:SetAttribute("FrameGuardMs", math.floor(costSum / costTicks * 1e6) / 1e3)
			costSum, costTicks = 0, 0
		end
	end)
end

return FrameGuard
