-- DragController handles client-side vehicle drag input (Street Tetris).
--
-- Flow:
--   Heartbeat: GetPartBoundsInRadius near player HRP → highlight nearby AtEntrance vehicles.
--   E key / DragBtn press near a highlighted vehicle → fire DragStart to server.
--   While dragging: Heartbeat sends DragPositionUpdate (unreliable) from mouse-ray hit.
--   E key / DragBtn release → fire DragConfirm with final CFrame.
--   DragStartResult(vehicleId, false, "OUT_OF_BOUNDS") → stay in drag mode, show feedback.
--   QTE (P2): listen for QTEPrompt on Supercar confirmation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DragController = Knit.CreateController({ Name = "DragController" })

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ── State ─────────────────────────────────────────────────────────────────────

local _isDragging         = false
local _dragVehicleId: string?  = nil
local _desiredCFrame      = CFrame.new()
local _gridOverlay: Part? = nil
local _highlight: SelectionBox? = nil
local _nearVehicleId: string?   = nil  -- vehicle closest to player for interact hint

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getHRP(): BasePart?
	local char = LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getMouseWorldCFrame(): CFrame?
	local mousePos = UserInputService:GetMouseLocation()
	local ray      = Camera:ScreenPointToRay(mousePos.X, mousePos.Y)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { LocalPlayer.Character or workspace }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 300, rayParams)
	if result then
		-- Orient along the surface normal; keep world Y up when normal is close to vertical.
		local normal = result.Normal
		local up     = math.abs(normal:Dot(Vector3.yAxis)) > 0.7 and Vector3.yAxis or normal
		return CFrame.fromMatrix(result.Position, ray.Direction:Cross(up).Unit * -1, up)
	end
	return nil
end

local function showGridOverlay()
	-- Clone the GridOverlay asset into workspace and make it visible inside the player zone.
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx    = assets and assets:FindFirstChild("VFX")
	local template = vfx and vfx:FindFirstChild("GridOverlay")
	if template and template:IsA("BasePart") then
		if _gridOverlay then
			_gridOverlay:Destroy()
		end
		_gridOverlay = template:Clone() :: Part
		_gridOverlay.Transparency = 0.6
		_gridOverlay.Parent = workspace
	end
end

local function hideGridOverlay()
	if _gridOverlay then
		_gridOverlay:Destroy()
		_gridOverlay = nil
	end
end

local function highlightVehicle(model: Model?)
	if _highlight then
		_highlight:Destroy()
		_highlight = nil
	end
	if not model then return end
	local box = Instance.new("SelectionBox")
	box.Adornee  = model
	box.Color3   = Color3.fromRGB(255, 220, 50)
	box.LineThickness = 0.05
	box.SurfaceTransparency = 0.8
	box.SurfaceColor3 = Color3.fromRGB(255, 220, 50)
	box.Parent   = LocalPlayer.PlayerGui
	_highlight   = box
end

local function clearHighlight()
	if _highlight then
		_highlight:Destroy()
		_highlight = nil
	end
	_nearVehicleId = nil
end

-- Overlap params filtered to VehicleHitbox-tagged parts.
local function makeHitboxParams(): OverlapParams
	local p = OverlapParams.new()
	p.FilterType               = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = CollectionService:GetTagged("VehicleHitbox")
	return p
end

-- ── Drag start / stop ─────────────────────────────────────────────────────────

local function beginDrag()
	if _isDragging then return end
	local vid = _nearVehicleId
	if not vid then return end

	_dragVehicleId = vid
	Remotes.DragStart:FireServer(vid)
	-- Actual drag mode is entered in the DragStartResult callback.
end

local function endDrag()
	if not _isDragging then return end
	Remotes.DragConfirm:FireServer(_dragVehicleId, _desiredCFrame)
	-- Hide grid optimistically; server will re-show drag if OUT_OF_BOUNDS.
	hideGridOverlay()
	_isDragging    = false
	_dragVehicleId = nil
end

-- ── QTE (P2) ──────────────────────────────────────────────────────────────────

local _qteActive           = false
local _qteVehicleId: string? = nil
local _qteExpected: { number } = {}
local _qteInput:    { number } = {}

local function showQTEUI(vehicleId: string, sequence: { number })
	_qteActive    = true
	_qteVehicleId = vehicleId
	_qteExpected  = sequence
	_qteInput     = {}

	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then return end
	local qteGui = playerGui:FindFirstChild("QTEHUD")
	if not qteGui then return end
	qteGui.Enabled = true

	-- Auto-timeout after 3 seconds.
	task.delay(3, function()
		if _qteActive and _qteVehicleId == vehicleId then
			_qteActive = false
			Remotes.QTEResult:FireServer(vehicleId, false)
			qteGui.Enabled = false
		end
	end)
end

local function submitQTEInput(buttonIndex: number)
	if not _qteActive then return end
	table.insert(_qteInput, buttonIndex)

	if #_qteInput >= #_qteExpected then
		local success = true
		for i, v in ipairs(_qteExpected) do
			if _qteInput[i] ~= v then
				success = false
				break
			end
		end
		_qteActive = false
		Remotes.QTEResult:FireServer(_qteVehicleId, success)
		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		local qteGui = playerGui and playerGui:FindFirstChild("QTEHUD")
		if qteGui then
			qteGui.Enabled = false
		end
	end
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function DragController:KnitStart()
	-- Keyboard: E key triggers drag start/stop.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.E then
			if _isDragging then
				endDrag()
			else
				beginDrag()
			end
		end
	end)

	-- Mobile: wire DragBtn when HUD is available.
	task.spawn(function()
		self:_TryWireDragBtn()
	end)

	-- DragStartResult: server response to our DragStart request.
	Remotes.DragStartResult:Connect(function(vehicleId: string, success: boolean, _reason: string?)
		if success and vehicleId == _dragVehicleId then
			_isDragging = true
			showGridOverlay()
		elseif not success then
			if _reason == "OUT_OF_BOUNDS" then
				-- Drag still active; re-show grid overlay if it was hidden.
				_isDragging = (_dragVehicleId == vehicleId)
				if _isDragging then
					showGridOverlay()
				end
			else
				-- Hard fail — exit drag mode.
				_isDragging    = false
				_dragVehicleId = nil
				hideGridOverlay()
			end
		end
	end)

	-- QTEPrompt (P2): server asks us to run a QTE after Supercar confirm.
	Remotes.QTEPrompt:Connect(function(vehicleId: string, sequence: { number })
		showQTEUI(vehicleId, sequence)
	end)

	-- Heartbeat: proximity detection + drag position updates.
	RunService.Heartbeat:Connect(function()
		self:_HeartbeatTick()
	end)
end

function DragController:_HeartbeatTick()
	local hrp = getHRP()
	if not hrp then return end

	-- ── Proximity detection (only when not dragging) ──────────────────────────
	if not _isDragging then
		local params = makeHitboxParams()
		local parts  = workspace:GetPartBoundsInRadius(hrp.Position, 5, params)

		local closestId: string?   = nil
		local closestDist = math.huge
		local closestModel: Model? = nil

		for _, part in ipairs(parts) do
			local vid = part:GetAttribute("VehicleId") :: string?
			if not vid then continue end
			local model = part:FindFirstAncestorOfClass("Model")
			if not model then continue end
			local pp = model.PrimaryPart :: BasePart?
			if not pp then continue end
			local dist = (hrp.Position - pp.Position).Magnitude
			if dist < closestDist then
				closestDist  = dist
				closestId    = vid
				closestModel = model
			end
		end

		if closestId ~= _nearVehicleId then
			_nearVehicleId = closestId
			highlightVehicle(closestModel)
		end
	else
		-- ── Drag position update ──────────────────────────────────────────────
		local cf = getMouseWorldCFrame()
		if cf then
			_desiredCFrame = cf
			if _gridOverlay then
				_gridOverlay.CFrame = cf
			end
			Remotes.DragPositionUpdate:FireServer(_dragVehicleId, cf)
		end
	end
end

function DragController:_TryWireDragBtn()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then return end

	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		task.delay(5, function()
			self:_TryWireDragBtn()
		end)
		return
	end

	local btn = hud:FindFirstChild("DragBtn", true)
	if not btn or not btn:IsA("GuiButton") then return end

	;(btn :: GuiButton).MouseButton1Down:Connect(function()
		if _isDragging then
			endDrag()
		else
			beginDrag()
		end
	end)
end

-- ── QTE button wiring (P2) ────────────────────────────────────────────────────
-- Called externally by HUDController once QTEHUD buttons are ready.
function DragController:OnQTEButtonPressed(buttonIndex: number)
	submitQTEInput(buttonIndex)
end

return DragController
