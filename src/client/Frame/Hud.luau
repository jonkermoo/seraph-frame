--!strict
-- One line of prototype help text at the top of the screen.

local Players = game:GetService("Players")

local Hud = {}

local label: TextLabel? = nil

function Hud.set(text: string)
	local current = label
	if current then
		current.Text = text
		return
	end
	do
		local gui = Instance.new("ScreenGui")
		gui.Name = "GymHud"
		gui.ResetOnSpawn = false
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, 0, 0, 28)
		l.Position = UDim2.fromOffset(0, 6)
		l.BackgroundTransparency = 1
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0.3
		l.Font = Enum.Font.GothamMedium
		l.TextSize = 18
		l.Text = text
		l.Parent = gui
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		label = l
	end
end

return Hud
