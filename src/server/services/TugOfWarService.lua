-- TugOfWarService runs a timed battle between two players competing for the same vehicle.
--
-- Flow:
--   1. VehicleService:SetAggro detects a second claimant and calls StartBattle.
--   2. Both players receive TugOfWarStart (vehicleId, duration).
--   3. During the window, each player taps the action button; client fires TugOfWarInput.
--   4. Server counts inputs per player (APM-capped at TugOfWarAPMCap/sec).
--   5. After TugOfWarDuration, higher tap count wins.
--      Tie goes to playerA (the incumbent aggro holder).
--   6. Winner: vehicle continues toward their zone (VehicleService:SetAggro re-called).
--      Loser: WhistleService:ApplyLossCooldown.
--   7. Both players receive TugOfWarResult (winnerId).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local TugOfWarService = Knit.CreateService({ Name = "TugOfWarService" })

type BattleEntry = {
	playerA  : Player,
	playerB  : Player,
	scoreA   : number,
	scoreB   : number,
	-- rolling APM window per player: { count: number, windowStart: number }
	apmA     : { count: number, windowStart: number },
	apmB     : { count: number, windowStart: number },
	active   : boolean,
}

-- { [vehicleId]: BattleEntry }
local _battles: { [string]: BattleEntry } = {}

-- ── Initialisation ────────────────────────────────────────────────────────────

function TugOfWarService:KnitStart()
	Remotes.TugOfWarInput:Connect(function(player: Player, vehicleId: string)
		self:_RegisterInput(player, vehicleId)
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Called by VehicleService when a second player aggros an already-aggroed vehicle.
function TugOfWarService:StartBattle(vehicleId: string, playerA: Player, playerB: Player)
	-- Prevent duplicate battles for the same vehicle.
	if _battles[vehicleId] then return end

	local now = os.clock()
	_battles[vehicleId] = {
		playerA  = playerA,
		playerB  = playerB,
		scoreA   = 0,
		scoreB   = 0,
		apmA     = { count = 0, windowStart = now },
		apmB     = { count = 0, windowStart = now },
		active   = true,
	}

	-- Notify both players.
	Remotes.TugOfWarStart:FireClient(playerA, vehicleId, Constants.TugOfWarDuration)
	Remotes.TugOfWarStart:FireClient(playerB, vehicleId, Constants.TugOfWarDuration)

	-- Schedule resolution.
	task.delay(Constants.TugOfWarDuration, function()
		self:_ResolveBattle(vehicleId)
	end)
end

-- ── Private ───────────────────────────────────────────────────────────────────

function TugOfWarService:_RegisterInput(player: Player, vehicleId: string)
	local battle = _battles[vehicleId]
	if not battle or not battle.active then return end

	local now = os.clock()

	if battle.playerA == player then
		local apm = battle.apmA
		-- Reset rolling window if 1 second has elapsed.
		if (now - apm.windowStart) >= 1 then
			apm.count       = 0
			apm.windowStart = now
		end
		if apm.count >= Constants.TugOfWarAPMCap then return end
		apm.count    += 1
		battle.scoreA += 1

	elseif battle.playerB == player then
		local apm = battle.apmB
		if (now - apm.windowStart) >= 1 then
			apm.count       = 0
			apm.windowStart = now
		end
		if apm.count >= Constants.TugOfWarAPMCap then return end
		apm.count    += 1
		battle.scoreB += 1
	end
end

function TugOfWarService:_ResolveBattle(vehicleId: string)
	local battle = _battles[vehicleId]
	if not battle then return end
	battle.active = false
	_battles[vehicleId] = nil

	-- Tie goes to playerA (incumbent).
	local winner, loser
	if battle.scoreB > battle.scoreA then
		winner = battle.playerB
		loser  = battle.playerA
	else
		winner = battle.playerA
		loser  = battle.playerB
	end

	-- Notify both players.
	Remotes.TugOfWarResult:FireClient(battle.playerA, vehicleId, winner.UserId)
	Remotes.TugOfWarResult:FireClient(battle.playerB, vehicleId, winner.UserId)

	-- Redirect the vehicle to the winner's zone.
	local okV, VehicleService = pcall(Knit.GetService, Knit, "VehicleService")
	if okV and VehicleService then
		VehicleService:SetAggro(vehicleId, winner)
	end

	-- Apply loss cooldown to the loser.
	local okW, WhistleService = pcall(Knit.GetService, Knit, "WhistleService")
	if okW and WhistleService then
		WhistleService:ApplyLossCooldown(loser)
	end
end

return TugOfWarService
