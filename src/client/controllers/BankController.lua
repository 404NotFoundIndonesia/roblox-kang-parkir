-- BankController opens BankGui when the player activates the BankTerminal ProximityPrompt.
-- Displays the current unbanked shift earnings (tracked via PayoutReceived / PenaltyApplied).
-- SETOR button fires BankEarnings to server; the subsequent PayoutReceived(0,0) event
-- updates the HUDController unbanked label. A "Tersimpan!" overlay shows for 2 seconds.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local BankController = Knit.CreateController({ Name = "BankController" })

local _currentUnbanked: number = 0
local _bankGui:          ScreenGui?
local _unbankedLabel:    TextLabel?

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function updateLabel()
	if _bankGui and _bankGui.Enabled and _unbankedLabel then
		_unbankedLabel.Text = "Saldo: " .. tostring(math.floor(_currentUnbanked))
	end
end

local function showFeedback(playerGui: Instance)
	local lbl      = Instance.new("TextLabel")
	lbl.Text       = "Tersimpan!"
	lbl.TextColor3 = Color3.fromRGB(85, 200, 85)
	lbl.Font       = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.BackgroundTransparency = 1
	lbl.Size     = UDim2.new(0, 220, 0, 55)
	lbl.Position = UDim2.new(0.5, -110, 0.45, 0)
	lbl.ZIndex   = 30
	lbl.Parent   = playerGui
	task.delay(2, function()
		lbl:Destroy()
	end)
end

-- ── KnitStart ─────────────────────────────────────────────────────────────────

function BankController:KnitStart()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local bankGui   = PlayerGui:WaitForChild("BankGui", 20) :: ScreenGui?
	if not bankGui then
		warn("[BankController] BankGui not found in PlayerGui")
		return
	end
	_bankGui = bankGui
	bankGui.Enabled = false

	_unbankedLabel = bankGui:FindFirstChild("UnbankedLabel", true) :: TextLabel?
	local confirmBtn = bankGui:FindFirstChild("ConfirmButton", true) :: GuiButton?

	-- Keep _currentUnbanked in sync with economy events.
	Remotes.PayoutReceived:Connect(function(_delta: number, newUnbanked: number)
		_currentUnbanked = newUnbanked
		updateLabel()
	end)

	Remotes.PenaltyApplied:Connect(function(_delta: number, newUnbanked: number)
		_currentUnbanked = newUnbanked
		updateLabel()
	end)

	-- SETOR button.
	if confirmBtn then
		confirmBtn.Activated:Connect(function()
			Remotes.BankEarnings:FireServer()
			bankGui.Enabled = false
			showFeedback(PlayerGui)
		end)
	end

	-- Find BankTerminal and wire ProximityPrompt.
	task.spawn(function()
		local terminal = workspace:WaitForChild("BankTerminal", 30)
		if not terminal then
			warn("[BankController] BankTerminal not found in workspace")
			return
		end

		local prompt = terminal:FindFirstChildOfClass("ProximityPrompt")
			or terminal:FindFirstChildWhichIsA("ProximityPrompt", true)
		if not prompt then
			warn("[BankController] ProximityPrompt not found on BankTerminal")
			return
		end

		prompt.Triggered:Connect(function()
			if _unbankedLabel then
				_unbankedLabel.Text = "Saldo: " .. tostring(math.floor(_currentUnbanked))
			end
			bankGui.Enabled = true
		end)

		prompt.TriggerEnded:Connect(function()
			bankGui.Enabled = false
		end)
	end)
end

return BankController
