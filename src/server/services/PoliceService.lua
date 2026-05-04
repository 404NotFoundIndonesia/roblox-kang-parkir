-- PoliceService manages Satpol PP NPC units during a Raid event.
--
-- Each NPC runs in its own 0.5 s task loop:
--   1. Find nearest visible, un-bribed player (LoS raycast, HidingVolume check).
--   2. Navigate toward that player via PathfindingService (one path step per tick).
--   3. Accumulate caughtTimer while in proximity; call _CaughtPlayer when threshold hit.
--
-- EndRaid destroys all NPCs and clears state.
-- ClearTargeting adds a player to _bribes, making them invisible to all NPCs.
-- _CaughtPlayer delegates the stun flag to CombatService:SetStunned.

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService  = game:GetService("CollectionService")
local Players            = game:GetService("Players")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local PoliceService = Knit.CreateService({ Name = "PoliceService" })

type PoliceEntry = {
	model        : Model,
	targetPlayer : Player?,
	caughtTimer  : number,
	active       : boolean,
}

local _activePolice: { PoliceEntry }     = {}
local _bribes:       { [number]: boolean } = {}

-- Per-player cooldown so the same player cannot be caught twice in quick succession.
local _catchCooldown: { [number]: number } = {}  -- uid → tick() expiry

-- ── Map helpers ───────────────────────────────────────────────────────────────

local function getCitationNode(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local node = map and map:FindFirstChild("CitationNode") :: BasePart?
	return node or workspace:FindFirstChild("CitationNode") :: BasePart?
end

local function getSpawnNodes(): { BasePart }
	local nodes: { BasePart } = {}
	for _, part in CollectionService:GetTagged("PoliceSpawnNode") do
		if part:IsA("BasePart") then
			table.insert(nodes, part)
		end
	end
	return nodes
end

local function getTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local npcs   = assets and assets:FindFirstChild("NPCs")
	local tmpl   = npcs and npcs:FindFirstChild("SatpolPP")
	return tmpl and tmpl:IsA("Model") and tmpl or nil
end

-- ── LoS check ─────────────────────────────────────────────────────────────────

-- Returns true if a HidingVolume blocks the line of sight between npcHead and playerHRP.
local function isHiddenBehindVolume(npcHead: BasePart, playerHRP: BasePart): boolean
	local from = npcHead.Position
	local dir  = playerHRP.Position - from

	-- Exclude all player characters so the ray passes through them.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local chars: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	params.FilterDescendantsInstances = chars

	local result = workspace:Raycast(from, dir, params)
	if not result then return false end  -- unobstructed; player is visible

	-- If the ray hit something, check whether it's a HidingVolume.
	local hit = result.Instance
	return CollectionService:HasTag(hit, "HidingVolume")
		or hit.Name == "HidingVolume"
		or (hit.Parent ~= nil and hit.Parent.Name == "HidingVolume")
end

-- ── Navigation (one step per tick) ───────────────────────────────────────────

local function navigateStep(npcModel: Model, targetPos: Vector3)
	local humanoid   = npcModel:FindFirstChildOfClass("Humanoid")
	local primaryPart = npcModel.PrimaryPart :: BasePart?
	if not humanoid or not primaryPart then return end

	local path = PathfindingService:CreatePath({
		AgentRadius   = 1.5,
		AgentHeight   = 5,
		AgentCanJump  = false,
		AgentCanClimb = false,
	})

	local ok = pcall(path.ComputeAsync, path, primaryPart.Position, targetPos)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		-- Fallback: move directly.
		humanoid:MoveTo(targetPos)
		return
	end

	local waypoints = path:GetWaypoints()
	-- Move toward the second waypoint (first is current position).
	if #waypoints >= 2 then
		humanoid:MoveTo(waypoints[2].Position)
	elseif #waypoints == 1 then
		humanoid:MoveTo(waypoints[1].Position)
	end
end

-- ── Per-NPC tick loop ─────────────────────────────────────────────────────────

function PoliceService:_StartNPCLoop(entry: PoliceEntry)
	task.spawn(function()
		while entry.active do
			task.wait(0.5)
			if not entry.active then break end

			local npcModel = entry.model
			local primaryPart = npcModel.PrimaryPart :: BasePart?
			local npcHead     = npcModel:FindFirstChild("Head") :: BasePart?
			if not primaryPart or not npcHead then continue end

			-- ── Find nearest visible, un-bribed player ──────────────────────
			local bestPlayer: Player? = nil
			local bestDist            = math.huge

			for _, player in Players:GetPlayers() do
				if _bribes[player.UserId] then continue end

				local char = player.Character
				local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not hrp then continue end

				-- LoS check.
				if isHiddenBehindVolume(npcHead, hrp) then continue end

				local dist = (primaryPart.Position - hrp.Position).Magnitude
				if dist < bestDist then
					bestDist   = dist
					bestPlayer = player
				end
			end

			entry.targetPlayer = bestPlayer

			-- ── Navigate toward target ──────────────────────────────────────
			if bestPlayer then
				local targetChar = bestPlayer.Character
				local targetHRP  = targetChar and targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
				if targetHRP then
					navigateStep(npcModel, targetHRP.Position)

					-- ── Proximity / caught timer ────────────────────────────
					local proximity = (primaryPart.Position - targetHRP.Position).Magnitude
					if proximity <= Constants.PoliceProximityCaught then
						entry.caughtTimer += 0.5

						if entry.caughtTimer >= Constants.PoliceCaughtTimer then
							entry.caughtTimer = 0
							self:_CaughtPlayer(bestPlayer)
						end
					else
						entry.caughtTimer = 0
					end
				else
					entry.caughtTimer = 0
				end
			else
				entry.caughtTimer = 0
			end
		end
	end)
end

-- ── Caught player ─────────────────────────────────────────────────────────────

function PoliceService:_CaughtPlayer(player: Player)
	local uid = player.UserId

	-- Per-player catch cooldown: don't trigger twice in quick succession.
	if tick() < (_catchCooldown[uid] or 0) then return end
	_catchCooldown[uid] = tick() + Constants.PoliceCaughtStunDuration + 1

	-- 1. Apply penalty: fraction of current unbanked balance.
	local okE, EconomyService = pcall(Knit.GetService, Knit, "EconomyService")
	if okE and EconomyService then
		local unbanked = EconomyService:GetUnbanked(player)
		local penalty  = math.floor(unbanked * Constants.PoliceCaughtPenaltyPct)
		if penalty > 0 then
			EconomyService:ApplyPenalty(player, penalty)
		end
	end

	-- 2. Teleport to CitationNode.
	local citationNode = getCitationNode()
	if citationNode then
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			hrp.CFrame = citationNode.CFrame + Vector3.new(0, 3, 0)
		end
	end

	-- 3. Apply stun via CombatService (which owns the stun flag and fires PlayerStunned).
	local okC, CombatService = pcall(Knit.GetService, Knit, "CombatService")
	if okC and CombatService then
		CombatService:SetStunned(player, Constants.PoliceCaughtStunDuration)
	end
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function PoliceService:KnitStart()
	-- Nothing to wire at startup; StartRaid is called by EventService.
end

-- ── Public API ────────────────────────────────────────────────────────────────

function PoliceService:StartRaid()
	-- Guard against double-start.
	if #_activePolice > 0 then return end

	local template    = getTemplate()
	local spawnNodes  = getSpawnNodes()

	if not template then
		warn("[PoliceService] SatpolPP template missing in ReplicatedStorage.Assets.NPCs")
		return
	end
	if #spawnNodes == 0 then
		warn("[PoliceService] No parts tagged 'PoliceSpawnNode' found")
		return
	end

	for i = 1, Constants.PoliceSpawnCount do
		-- Cycle through available spawn nodes.
		local spawnNode = spawnNodes[((i - 1) % #spawnNodes) + 1]

		local model = template:Clone()
		model:PivotTo(spawnNode.CFrame)
		model.Parent = workspace

		local entry: PoliceEntry = {
			model        = model,
			targetPlayer = nil,
			caughtTimer  = 0,
			active       = true,
		}
		table.insert(_activePolice, entry)

		self:_StartNPCLoop(entry)
	end
end

function PoliceService:EndRaid()
	for _, entry in _activePolice do
		entry.active = false
		if entry.model and entry.model.Parent then
			entry.model:Destroy()
		end
	end
	table.clear(_activePolice)
	table.clear(_bribes)
	table.clear(_catchCooldown)
end

-- Add player to bribe list — police NPCs skip them for the rest of this event.
function PoliceService:ClearTargeting(player: Player)
	_bribes[player.UserId] = true
end

return PoliceService
