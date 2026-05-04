-- SyndicateController manages the SyndicateGui.
--
-- SyndicateData(payload | nil):
--   • payload = { syndicateId, name, members: {userId}, weeklyEarnings } | nil
--   • Populates member list, weekly earnings bar, and header label.
--   • nil means the local player is not in a syndicate — shows "no syndicate" state.
--
-- Buttons:
--   CreateBtn  → opens CreatePanel; ConfirmCreate fires SyndicateCreate(name)
--   JoinBtn    → opens JoinPanel;   ConfirmJoin   fires SyndicateJoin(syndicateId)
--   LeaveBtn   → fires SyndicateLeave
--
-- Weekly earnings bar width = weeklyEarnings / EARNINGS_BAR_MAX (clamped 0–1).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SyndicateController = Knit.CreateController({ Name = "SyndicateController" })

local LocalPlayer = Players.LocalPlayer

local EARNINGS_BAR_MAX = 10000  -- earnings value that fills the bar to 100%

-- ── GUI references (populated in KnitStart after gui loads) ───────────────────

local _gui:           ScreenGui?   = nil
local _noSyndicateFrame: Frame?    = nil
local _syndicateFrame:   Frame?    = nil
local _nameLabel:        TextLabel? = nil
local _earningsBar:      Frame?    = nil
local _memberList:       Frame?    = nil  -- ScrollingFrame or Frame holding member rows
local _earningsLabel:    TextLabel? = nil

-- Create / Join panels
local _createPanel:  Frame?      = nil
local _createInput:  TextBox?    = nil
local _joinPanel:    Frame?      = nil
local _joinInput:    TextBox?    = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function setGuiVisible(visible: boolean)
	if _gui then _gui.Enabled = visible end
end

local function clearMemberList()
	if not _memberList then return end
	for _, child in _memberList:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Template" then
			child:Destroy()
		end
	end
end

local function makeMemberRow(userId: number): Frame?
	if not _memberList then return nil end
	local template = _memberList:FindFirstChild("Template")
	if not template or not template:IsA("Frame") then return nil end

	local row    = template:Clone() :: Frame
	row.Name     = tostring(userId)
	row.Visible  = true

	local nameLabel = row:FindFirstChild("NameLabel") :: TextLabel?
	if nameLabel then
		-- Resolve display name asynchronously to avoid yielding the main thread.
		task.spawn(function()
			local ok, displayName = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			if ok and nameLabel and nameLabel.Parent then
				nameLabel.Text = displayName
			elseif nameLabel and nameLabel.Parent then
				nameLabel.Text = "[" .. userId .. "]"
			end
		end)
	end

	row.Parent = _memberList
	return row
end

-- ── State update ──────────────────────────────────────────────────────────────

local function applyPayload(payload: { [string]: any }?)
	if not _gui then return end

	if not payload then
		-- Not in a syndicate.
		if _noSyndicateFrame then _noSyndicateFrame.Visible = true end
		if _syndicateFrame   then _syndicateFrame.Visible = false end
		return
	end

	if _noSyndicateFrame then _noSyndicateFrame.Visible = false end
	if _syndicateFrame   then _syndicateFrame.Visible = true end

	-- Header name.
	if _nameLabel then
		_nameLabel.Text = tostring(payload.name or "Syndicate")
	end

	-- Weekly earnings bar.
	local earnings = tonumber(payload.weeklyEarnings) or 0
	if _earningsBar then
		local pct = math.clamp(earnings / EARNINGS_BAR_MAX, 0, 1)
		_earningsBar.Size = UDim2.new(pct, 0, 1, 0)
	end
	if _earningsLabel then
		_earningsLabel.Text = tostring(earnings)
	end

	-- Member list.
	clearMemberList()
	local members = payload.members
	if type(members) == "table" then
		for _, userId in ipairs(members) do
			makeMemberRow(userId)
		end
	end
end

-- ── Panels ────────────────────────────────────────────────────────────────────

local function hideAllPanels()
	if _createPanel then _createPanel.Visible = false end
	if _joinPanel   then _joinPanel.Visible   = false end
end

local function openCreatePanel()
	hideAllPanels()
	if _createPanel then
		_createPanel.Visible = true
		if _createInput then _createInput.Text = "" end
	end
end

local function openJoinPanel()
	hideAllPanels()
	if _joinPanel then
		_joinPanel.Visible = true
		if _joinInput then _joinInput.Text = "" end
	end
end

-- ── Button wiring ─────────────────────────────────────────────────────────────

local function wireButtons()
	if not _gui then return end

	-- Main buttons.
	local createBtn = _gui:FindFirstChild("CreateBtn", true) :: GuiButton?
	local joinBtn   = _gui:FindFirstChild("JoinBtn",   true) :: GuiButton?
	local leaveBtn  = _gui:FindFirstChild("LeaveBtn",  true) :: GuiButton?

	if createBtn and createBtn:IsA("GuiButton") then
		createBtn.Activated:Connect(openCreatePanel)
	end
	if joinBtn and joinBtn:IsA("GuiButton") then
		joinBtn.Activated:Connect(openJoinPanel)
	end
	if leaveBtn and leaveBtn:IsA("GuiButton") then
		leaveBtn.Activated:Connect(function()
			Remotes.SyndicateLeave:FireServer()
		end)
	end

	-- Create panel confirm.
	local confirmCreate = _gui:FindFirstChild("ConfirmCreate", true) :: GuiButton?
	if confirmCreate and confirmCreate:IsA("GuiButton") then
		confirmCreate.Activated:Connect(function()
			if not _createInput then return end
			local name = _createInput.Text:match("^%s*(.-)%s*$")  -- trim
			if #name == 0 then return end
			Remotes.SyndicateCreate:FireServer(name)
			hideAllPanels()
		end)
	end

	local cancelCreate = _gui:FindFirstChild("CancelCreate", true) :: GuiButton?
	if cancelCreate and cancelCreate:IsA("GuiButton") then
		cancelCreate.Activated:Connect(hideAllPanels)
	end

	-- Join panel confirm.
	local confirmJoin = _gui:FindFirstChild("ConfirmJoin", true) :: GuiButton?
	if confirmJoin and confirmJoin:IsA("GuiButton") then
		confirmJoin.Activated:Connect(function()
			if not _joinInput then return end
			local syndicateId = _joinInput.Text:match("^%s*(.-)%s*$")
			if #syndicateId == 0 then return end
			Remotes.SyndicateJoin:FireServer(syndicateId)
			hideAllPanels()
		end)
	end

	local cancelJoin = _gui:FindFirstChild("CancelJoin", true) :: GuiButton?
	if cancelJoin and cancelJoin:IsA("GuiButton") then
		cancelJoin.Activated:Connect(hideAllPanels)
	end
end

-- ── KnitStart ─────────────────────────────────────────────────────────────────

function SyndicateController:KnitStart()
	-- Wait for PlayerGui and SyndicateGui.
	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 15)
	if not playerGui then return end

	local gui = playerGui:WaitForChild("SyndicateGui", 15) :: ScreenGui?
	if not gui or not gui:IsA("ScreenGui") then return end
	_gui = gui

	-- Resolve child references (all optional — graceful if GUI layout differs).
	_noSyndicateFrame = gui:FindFirstChild("NoSyndicateFrame", true) :: Frame?
	_syndicateFrame   = gui:FindFirstChild("SyndicateFrame",   true) :: Frame?
	_nameLabel        = gui:FindFirstChild("SyndicateNameLabel", true) :: TextLabel?
	_earningsLabel    = gui:FindFirstChild("EarningsLabel",    true) :: TextLabel?
	_memberList       = gui:FindFirstChild("MemberList",       true) :: Frame?
	_createPanel      = gui:FindFirstChild("CreatePanel",      true) :: Frame?
	_joinPanel        = gui:FindFirstChild("JoinPanel",        true) :: Frame?
	_createInput      = gui:FindFirstChild("CreateNameInput",  true) :: TextBox?
	_joinInput        = gui:FindFirstChild("JoinIdInput",      true) :: TextBox?

	-- EarningsBar is the fill bar inside an EarningsBarBg container.
	local earningsBg  = gui:FindFirstChild("EarningsBarBg", true) :: Frame?
	if earningsBg then
		_earningsBar = earningsBg:FindFirstChild("Fill") :: Frame?
	end

	-- Start hidden; panels hidden.
	hideAllPanels()
	applyPayload(nil)

	wireButtons()

	-- Listen for server-pushed syndicate state.
	Remotes.SyndicateData:Connect(function(payload: { [string]: any }?)
		applyPayload(payload)
	end)
end

return SyndicateController
