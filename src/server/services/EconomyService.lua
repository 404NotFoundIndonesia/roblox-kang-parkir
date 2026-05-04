-- EconomyService owns the shift-currency layer (unbanked earnings) that sits
-- on top of DataService's persistent BankedEarnings.
--
-- Unbanked currency is the "working" balance earned during a shift.
-- It is lost if the player leaves without banking. At ShiftEnd, AutoBankAll
-- flushes every player's unbanked balance into their persistent profile.
--
-- Event multiplier: set by EventService during Flash Mob; affects CalculatePayout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = Knit.CreateService({ Name = "EconomyService" })

local _unbanked:               { [number]: number } = {}
local _currentEventMultiplier: number               = 0

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getDataService()
	local ok, svc = pcall(Knit.GetService, Knit, "DataService")
	return ok and svc or nil
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function EconomyService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		_unbanked[player.UserId] = 0
	end)

	Players.PlayerRemoving:Connect(function(player)
		_unbanked[player.UserId] = nil
	end)

	for _, player in Players:GetPlayers() do
		_unbanked[player.UserId] = 0
	end

	-- Client requests to bank their unbanked earnings at the BankTerminal.
	Remotes.BankEarnings:Connect(function(player: Player)
		self:BankEarnings(player)
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Formula: (basePayout + alignmentBonus) × (1 + eventMultiplier) − penalties.
-- Result is floored at 0.
function EconomyService:CalculatePayout(
	vehicleType:     string,
	alignmentBonus:  number,
	eventMultiplier: number,
	penalties:       number
): number
	local base    = Constants.VehicleBasePayouts[vehicleType] or 0
	local gross   = (base + alignmentBonus) * (1 + eventMultiplier) - penalties
	return math.max(0, math.floor(gross))
end

-- Add earned currency to the player's unbanked balance.
-- Fires PayoutReceived(delta, newUnbankedTotal) so HUD can update both values.
function EconomyService:AddPayout(player: Player, amount: number)
	if amount <= 0 then return end
	local uid = player.UserId
	if _unbanked[uid] == nil then return end

	-- Syndicate adjacency bonus: +5% if any member's zone is adjacent.
	local okS, SyndicateService = pcall(Knit.GetService, Knit, "SyndicateService")
	if okS and SyndicateService and SyndicateService:GetAdjacentBonus(player) then
		amount = math.floor(amount * 1.05)
		SyndicateService:RecordEarning(player, amount)
	end

	_unbanked[uid] += amount
	Remotes.PayoutReceived:FireClient(player, amount, _unbanked[uid])
end

-- Deduct a penalty from unbanked, floored at 0.
-- Fires PenaltyApplied(delta, newUnbankedTotal) so HUD can update.
function EconomyService:ApplyPenalty(player: Player, amount: number)
	if amount <= 0 then return end
	local uid = player.UserId
	if _unbanked[uid] == nil then return end

	local actual = math.min(amount, _unbanked[uid])
	_unbanked[uid] = math.max(0, _unbanked[uid] - amount)
	Remotes.PenaltyApplied:FireClient(player, actual, _unbanked[uid])
end

-- Flush unbanked earnings into the persistent profile.
-- Called by BankTerminal (client fires BankEarnings remote) and AutoBankAll at ShiftEnd.
function EconomyService:BankEarnings(player: Player)
	local uid    = player.UserId
	local amount = _unbanked[uid]
	if not amount or amount <= 0 then return end

	_unbanked[uid] = 0

	-- Persist via DataService (also fires its own PayoutReceived for the banked total).
	local DataService = getDataService()
	if DataService then
		DataService:AddBankedEarnings(player, amount)
	end

	-- Reset the unbanked display on the client HUD.
	Remotes.PayoutReceived:FireClient(player, 0, 0)
end

-- Deduct shift currency (unbanked) for in-shift shop purchases.
-- Returns false without deducting if insufficient funds.
function EconomyService:SpendShiftCurrency(player: Player, amount: number): boolean
	local uid = player.UserId
	if _unbanked[uid] == nil then return false end
	if _unbanked[uid] < amount then return false end

	_unbanked[uid] -= amount
	Remotes.PayoutReceived:FireClient(player, -amount, _unbanked[uid])
	return true
end

function EconomyService:GetUnbanked(player: Player): number
	return _unbanked[player.UserId] or 0
end

-- Set by EventService; used in CalculatePayout for the active event window.
function EconomyService:SetEventMultiplier(multiplier: number)
	_currentEventMultiplier = multiplier
end

-- Read the current event multiplier (used by DragService at payout time).
function EconomyService:GetEventMultiplier(): number
	return _currentEventMultiplier
end

-- Bank every online player's unbanked balance. Called by SessionService at ShiftEnd.
function EconomyService:AutoBankAll()
	for _, player in Players:GetPlayers() do
		self:BankEarnings(player)
	end
end

return EconomyService
