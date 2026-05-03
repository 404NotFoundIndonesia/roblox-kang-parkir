local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Shared.Knit)

local servicesFolder = script:FindFirstChild("services")
if servicesFolder then
	for _, module in servicesFolder:GetChildren() do
		if module:IsA("ModuleScript") then
			require(module)
		end
	end
end

Knit.Start():andThen(function()
	-- all services started
end):catch(function(err)
	warn("[KangParkir] Knit.Start() failed:", tostring(err))
	game:SetAttribute("BootFailed", true)
end)
