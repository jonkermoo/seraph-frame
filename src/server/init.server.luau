--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Avatar = require(script.Services.Avatar)
local Boarding = require(script.Services.Boarding)
local Frame = require(script.Services.Frame)
local FrameGuard = require(script.Services.FrameGuard)
local Gym = require(script.Services.Gym)

Net.remote("Ping")
Net.remote("FrameBoard")
Net.remote("FrameExit")
Net.remote("FrameAction")

Gym.start()
Frame.start()
Boarding.start()
FrameGuard.start()
Avatar.start()
