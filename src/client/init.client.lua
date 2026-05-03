local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Shared.Knit)

local controllersFolder = script:FindFirstChild("controllers")
if controllersFolder then
	for _, module in controllersFolder:GetChildren() do
		if module:IsA("ModuleScript") then
			require(module)
		end
	end
end

Knit.Start():andThen(function()
	-- Knit resolved; now wait for the character to load before controllers interact with it
	Players.LocalPlayer.CharacterAdded:Wait()
end):catch(function(err)
	warn("[KangParkir] Knit.Start() failed:", tostring(err))
end)
