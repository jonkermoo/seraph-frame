--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Avatar = require(script.Services.Avatar)
local Boarding = require(script.Services.Boarding)
local Gym = require(script.Services.Gym)

Net.remote("Ping")
Net.remote("FrameBoard")
Net.remote("FrameExit")

Boarding.start(Gym.start())
Avatar.start()
