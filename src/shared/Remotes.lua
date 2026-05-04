-- Creates all RemoteEvents/UnreliableRemoteEvents on server; finds them on client.
-- Server creates before Knit.Start() (services are required first, which require this).
-- Client WaitForChild with generous timeout — server always creates them on boot.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()

-- name → ClassName
-- "RemoteEvent"           = reliable, game-state or important triggers
-- "UnreliableRemoteEvent" = visual-only, high-frequency, drop-safe
local REMOTE_DEFS: { [string]: string } = {
	-- ── Server → Client (reliable) ─────────────────────────────────────────
	SessionPhaseChanged = "RemoteEvent", -- (phase, remainingSeconds)
	TugOfWarStart       = "RemoteEvent", -- (vehicleId)
	TugOfWarResult      = "RemoteEvent", -- (vehicleId, won)
	PayoutReceived      = "RemoteEvent", -- (delta, newUnbankedTotal)
	PenaltyApplied      = "RemoteEvent", -- (delta, newUnbankedTotal)
	DragStartResult     = "RemoteEvent", -- (vehicleId, success, reason?)
	EventStart          = "RemoteEvent", -- (eventType)
	EventEnd            = "RemoteEvent", -- (eventType)
	CosmeticData        = "RemoteEvent", -- (player, data)
	ShiftSummary        = "RemoteEvent", -- (data)
	PlayerStunned       = "RemoteEvent", -- (duration)
	ItemGranted         = "RemoteEvent", -- (itemName)
	ShopPurchaseResult  = "RemoteEvent", -- (itemName, success, reason?, newInventory?)
	QTEPrompt           = "RemoteEvent", -- (vehicleId, sequence)
	HelmetStolen        = "RemoteEvent", -- () — notify zone owner their Sport Bike helmet was taken

	-- ── Server → Client (unreliable / visual-only) ──────────────────────────
	StaminaUpdated = "UnreliableRemoteEvent", -- (newValue) — Heartbeat rate
	ThreatInZone   = "UnreliableRemoteEvent", -- (thiefId, thiefWorldPos) — zone owner only
	RainToggle     = "UnreliableRemoteEvent", -- (enabled)
	WhistleVFX     = "UnreliableRemoteEvent", -- (playerUserId)
	DashTrailVFX   = "UnreliableRemoteEvent", -- (playerUserId, trailAssetName)

	-- ── Client → Server (reliable) ──────────────────────────────────────────
	WhistleStart  = "RemoteEvent", -- ()
	WhistleStop   = "RemoteEvent", -- ()
	TugOfWarInput = "RemoteEvent", -- (vehicleId)
	DragStart     = "RemoteEvent", -- (vehicleId)
	DragConfirm   = "RemoteEvent", -- (vehicleId, desiredCFrame)
	DashRequest   = "RemoteEvent", -- (direction)
	StrikeRequest = "RemoteEvent", -- ()
	PlaceStrip    = "RemoteEvent", -- (position)
	BankEarnings  = "RemoteEvent", -- ()
	ShopPurchase  = "RemoteEvent", -- (itemName)
	ConsumeItem   = "RemoteEvent", -- (itemName)
	QTEResult     = "RemoteEvent", -- (vehicleId, success)
	ReadyUp       = "RemoteEvent", -- ()

	-- ── Client → Server (unreliable / high-frequency) ───────────────────────
	DragPositionUpdate = "UnreliableRemoteEvent", -- (vehicleId, desiredCFrame)
}

local remotesFolder: Folder

if IS_SERVER then
	remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end
else
	remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 30) :: Folder
	assert(remotesFolder, "[KangParkir] Remotes folder missing after 30 s — server failed to boot")
end

local Remotes: { [string]: Instance } = {}

if IS_SERVER then
	for name, className in REMOTE_DEFS do
		local existing = remotesFolder:FindFirstChild(name)
		if existing then
			Remotes[name] = existing
		else
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = remotesFolder
			Remotes[name] = remote
		end
	end
else
	for name in REMOTE_DEFS do
		local remote = remotesFolder:WaitForChild(name, 15)
		assert(remote, ("[KangParkir] Remote '%s' not found after 15 s"):format(name))
		Remotes[name] = remote
	end
end

return Remotes
