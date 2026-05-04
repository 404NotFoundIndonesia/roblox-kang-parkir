-- PostSessionController displays the end-of-shift summary screen.
-- Listens to ShiftSummary (S→C): populates PostSessionGui with earnings, penalties,
-- banked total, and top earner. If local player is the top earner, a golden UIStroke
-- highlights their name entry.
-- SIAP button fires ReadyUp to server and closes the GUI.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PostSessionController = Knit.CreateController({ Name = "PostSessionController" })

function PostSessionController:KnitStart()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local postGui   = PlayerGui:WaitForChild("PostSessionGui", 20) :: ScreenGui?
	if not postGui then
		warn("[PostSessionController] PostSessionGui not found in PlayerGui")
		return
	end
	postGui.Enabled = false

	-- UI references — look recursively so exact nesting doesn't matter.
	local totalLabel     = postGui:FindFirstChild("TotalEarnedLabel",  true) :: TextLabel?
	local penaltyLabel   = postGui:FindFirstChild("PenaltiesLabel",    true) :: TextLabel?
	local bankedLabel    = postGui:FindFirstChild("BankedLabel",       true) :: TextLabel?
	local topEarnerLabel = postGui:FindFirstChild("TopEarnerLabel",    true) :: TextLabel?
	local playerFrame    = postGui:FindFirstChild("PlayerNameFrame",   true) :: Frame?
	local siapBtn        = postGui:FindFirstChild("SiapButton",        true) :: GuiButton?

	Remotes.ShiftSummary:Connect(function(data: {
		totalEarned:       number,
		penalties:         number,
		bankedThisSession: number,
		topEarnerName:     string,
		topEarnerAmount:   number,
	})
		postGui.Enabled = true

		if totalLabel then
			totalLabel.Text = "Total: " .. tostring(math.floor(data.totalEarned))
		end
		if penaltyLabel then
			penaltyLabel.Text = "Penalti: -" .. tostring(math.floor(data.penalties))
		end
		if bankedLabel then
			bankedLabel.Text = "Tersimpan: " .. tostring(math.floor(data.bankedThisSession))
		end
		if topEarnerLabel then
			topEarnerLabel.Text = data.topEarnerName
				.. " — " .. tostring(math.floor(data.topEarnerAmount))
		end

		-- Golden border if this player is the top earner.
		if playerFrame and Players.LocalPlayer.Name == data.topEarnerName then
			local stroke = playerFrame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color     = Color3.fromRGB(255, 215, 0)
				stroke.Thickness = 3
			end
		end
	end)

	if siapBtn then
		siapBtn.Activated:Connect(function()
			Remotes.ReadyUp:FireServer()
			postGui.Enabled = false
		end)
	end
end

return PostSessionController
