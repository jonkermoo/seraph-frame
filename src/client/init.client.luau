--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Controller = require(script.Frame.Controller)

Net.remote("Ping")

Controller.start()
