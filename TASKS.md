# Scripting Task List: Kang Parkir

All scripts in Luau. Framework: **Knit**. Paths relative to `src/` under Rojo root.
Each task is one atomic unit of work. Done = the described behavior is verifiable in a playtest.

---

## Legend

- [ ] = Not started
- [x] = Done
- **P1** = Blocking (first playtest) | **P2** = Core feature | **P3** = Polish/optional

---

## 1. Project Bootstrap & Framework

- [x] **P1** Create `src/shared/Knit.lua`: require the Wally-installed Knit package from `ReplicatedStorage.Packages.Knit` and return it. All other files that need Knit require this module — never require Packages directly.

- [x] **P1** Create `src/server/init.server.lua`: require every file inside `src/server/services/` using a loop over `script.Services:GetChildren()`, then call `Knit.Start()`. If `Knit.Start()` rejects, print the error and call `game:SetAttribute("BootFailed", true)` so the client can detect it.

- [x] **P1** Create `src/client/init.client.lua`: require every file inside `src/client/controllers/` using a loop over `script.Controllers:GetChildren()`, then call `Knit.Start()`. Wait for `Knit.Start()` to resolve before the player character loads (use `Players.LocalPlayer.CharacterAdded:Wait()` after Knit resolves).

- [x] **P1** Create `src/shared/Constants.lua`: export a frozen table (use `table.freeze`) with the following keys. Every numeric game parameter lives here — no magic numbers anywhere else:
  ```
  WhistleBaseRadius        = 10       -- studs
  WhistleStatScale         = 1.5      -- studs per stat point
  WhistleMaxRadius         = 22       -- studs (hard cap)
  WhistleCooldownOnLoss    = 0.5      -- seconds
  WhistleRateLimit         = 0.5      -- minimum seconds between activations per player
  TugOfWarDuration         = 1.5      -- seconds
  TugOfWarAPMCap           = 10       -- max accepted inputs/second per player during tug
  DashDuration             = 0.3      -- seconds (window for hit detection)
  DashStaminaCost          = 30       -- stamina units
  DashCooldown             = 1.0      -- seconds
  DashMaxAngleDeg          = 45       -- max degrees deviation from character LookVector
  DashRagdollDuration      = 1.5      -- seconds target stays ragdolled
  MeleeRange               = 3        -- studs forward
  MeleeWidth               = 2        -- studs wide
  StaminaMax               = 100      -- base value
  StaminaRegenRate         = 8        -- units/second passive regen
  WhistleStaminaDrain      = 4        -- units/second while whistling
  TipOverThreshold         = 15       -- rad/s angular velocity to trigger tip-over
  TipOverPenaltyPct        = 0.30     -- fraction of vehicle base payout deducted
  TipOverDominoRadius      = 1.5      -- studs radius for domino chain check
  AlignmentDotThreshold    = 0.98     -- DotProduct required for AlignmentBonus
  AlignmentBonusMax        = 15       -- currency units maximum bonus
  VehicleEntranceTimeout   = 15       -- seconds before vehicle at entrance returns to traffic
  TrespasEjectDelay        = 5        -- seconds before foreign vehicle is ejected from zone
  SpikeStripPlaceRadius    = 5        -- max studs from player to place strip
  ThiefInteractDuration    = 3        -- seconds for thief steal animation
  ThiefRagdollDuration     = 1        -- seconds thief stays ragdolled after hit
  ThiefRespawnDelayMin     = 45       -- seconds
  ThiefRespawnDelayMax     = 90       -- seconds
  ThiefMaxAlive            = 2
  ThiefRetargetCooldown    = 10       -- seconds after interrupt before thief re-targets
  PoliceProximityCaught    = 3        -- studs from police to player to start caught timer
  PoliceCaughtTimer        = 2        -- seconds inside proximity before "Caught" fires
  PoliceCaughtPenaltyPct   = 0.20     -- fraction of unbanked currency lost when caught
  PoliceCaughtStunDuration = 3        -- seconds player input is locked after caught
  PoliceSpawnCount         = 3        -- NPCs spawned per Raid event (min 2, max 4)
  EventCooldownMin         = 180      -- seconds between events
  EventCooldownMax         = 420      -- seconds
  MonsoonFriction          = 0.1      -- Friction value applied to ground parts
  MonsoonSpeedMultiplier   = 0.85     -- WalkSpeed multiplier during rain
  FlashMobDuration         = 10       -- seconds of burst injection
  FlashMobVehicleCount     = 30       -- minimum vehicles injected
  FlashMobEventMultiplier  = 0.5      -- payout EventMultiplier during Flash Mob
  FlashMobScooterWeight    = 0.95     -- spawn weight for Scooter during burst
  SessionWarmUpDuration    = 60       -- seconds
  SessionPeakDuration      = 420      -- seconds (7 min)
  SessionRushHourDuration  = 120      -- seconds (2 min)
  SessionShiftEndBuffer    = 30       -- seconds to finish in-progress parks after shift ends
  BankAutoSaveInterval     = 60       -- seconds between auto-saves via ProfileService
  LeaderboardCacheInterval = 300      -- seconds between global leaderboard refreshes
  SpawnWeights = {                    -- vehicle type probability, must sum to 1.0
    Scooter   = 0.45,
    SportBike = 0.25,
    FamilyCar = 0.18,
    AggroSUV  = 0.10,
    Supercar  = 0.02,
  }
  VehicleBasePayouts = {
    Scooter   = 10,
    SportBike = 15,
    FamilyCar = 30,
    AggroSUV  = 40,
    Supercar  = 100,
  }
  ```

- [x] **P1** Create `src/shared/Types.lua`: export Luau type definitions used across server and client. Include:
  - `PlayerData`: `{ BankedEarnings: number, SkillTree: SkillTreeData, OwnedCosmetics: {string}, OwnedGamepasses: {string}, TotalSessions: number, Stats: StatsData, SchemaVersion: number }`
  - `SkillTreeData`: `{ WhistleLevel: number, StrengthLevel: number, SpeedLevel: number, StaminaLevel: number }` (each level 0–3)
  - `StatsData`: `{ ThievesInterrupted: number, RivalsRagdolled: number, TotalParked: number }`
  - `VehicleState`: string union `"Traffic" | "Aggroed" | "AtEntrance" | "Dragging" | "Parked" | "Damaged" | "Departing"`
  - `PlayerActionState`: string union `"Idle" | "Whistling" | "Dragging" | "Dashing" | "Ragdoll" | "Hiding" | "Stunned"`
  - `EventType`: string union `"MonsoonRain" | "SatpolRaid" | "FlashMob"`
  - `NPCState`: string union `"Roam" | "Navigate" | "Interact" | "Flee" | "Ragdoll" | "Despawn"`
  - `SessionPhase`: string union `"Lobby" | "WarmUp" | "PeakShift" | "RushHour" | "ShiftEnd" | "PostSession"`

- [x] **P1** Create `src/shared/Enums.lua`: mirror the string unions from `Types.lua` as string-keyed tables so runtime code can do `Enums.VehicleState.Parked` instead of spelling the string. Use `table.freeze` on each table.

---

## 2. Data Persistence

- [x] **P1** In `src/server/services/DataService.lua`, create a Knit Service named `"DataService"`. On `KnitInit`, call `ProfileService.GetProfileStore("KangParkir_v1", defaultData)` where `defaultData` matches the `PlayerData` type from `Types.lua` with all-zero/empty initial values and `SchemaVersion = 1`. Store the returned ProfileStore in a module-level variable.

- [x] **P1** In `DataService`, on `Players.PlayerAdded`: call `ProfileStore:LoadProfileAsync("Player_" .. player.UserId)`. If the profile returns `nil` (load failed), kick the player with `player:Kick("Data failed to load. Rejoin.")`. If loaded, call `profile:AddUserId(player.UserId)` and `profile:Reconcile()` to fill missing keys from the default template. Store the profile in a `_profiles[player.UserId]` dictionary.

- [x] **P1** In `DataService`, on `Players.PlayerRemoving`: call `_profiles[player.UserId]:Release()` if the profile exists. Remove the entry from `_profiles`.

- [x] **P1** In `DataService`, start a `task.spawn` loop that runs every `Constants.BankAutoSaveInterval` seconds and calls `profile:Save()` for every player currently in `_profiles`.

- [x] **P1** In `DataService`, expose `GetProfile(player: Player) -> Profile | nil`: returns `_profiles[player.UserId]`. Returns `nil` if the player's data has not finished loading yet — callers must handle `nil`.

- [x] **P1** In `DataService`, expose `AddBankedEarnings(player: Player, amount: number) -> ()`: guards `amount > 0`, then does `profile.Data.BankedEarnings += amount`. Fires `Remotes.PayoutReceived:FireClient(player, profile.Data.BankedEarnings)` after update so the client HUD can refresh.

- [x] **P1** In `DataService`, expose `DeductBankedEarnings(player: Player, amount: number) -> success: boolean`: if `profile.Data.BankedEarnings >= amount` then deducts and returns `true`, otherwise does nothing and returns `false`.

- [x] **P2** In `DataService`, expose `GetLeaderboardTop10() -> { {name: string, value: number} }`: reads `OrderedDataStore` keyed `"BankedEarnings_Leaderboard"`, returns top 10 entries as a sorted array. Cache the result in a module-level variable; only re-fetch if the cache is older than `Constants.LeaderboardCacheInterval` seconds. Never yield inside a `RemoteEvent` callback — pre-fetch on a background task.

---

## 3. Session & Zone Management

- [x] **P1** In `src/server/services/SessionService.lua`, create a Knit Service named `"SessionService"`. Store the current phase as a module-level variable initialized to `Enums.SessionPhase.Lobby`. Expose `GetPhase() -> SessionPhase`.

- [x] **P1** In `SessionService`, expose `StartSession()`: transitions phase through `WarmUp → PeakShift → RushHour → ShiftEnd → PostSession` using `task.delay` with durations from `Constants`. After each transition, fire `Remotes.SessionPhaseChanged:FireAllClients(newPhase)` so clients can update HUD timer display. At `ShiftEnd`, call `EconomyService:AutoBankAll()`.

- [x] **P1** In `SessionService`, broadcast the remaining seconds every 1 second using a `task.spawn` loop while not in `Lobby` or `PostSession`: fire `Remotes.SessionPhaseChanged:FireAllClients(currentPhase, remainingSeconds)` so clients keep the Shift Tracker accurate.

- [x] **P1** In `src/server/services/ZoneService.lua`, create a Knit Service named `"ZoneService"`. On `KnitStart`, collect all `BasePart`s tagged `"ParkingZone"` using `CollectionService:GetTagged("ParkingZone")` and store them in a `_zones` array. Store a `_zoneOwners` dictionary mapping zone Part → Player.

- [x] **P1** In `ZoneService`, expose `AssignZone(player: Player) -> Part | nil`: picks the first unassigned zone in `_zones`, writes it to `_zoneOwners`, returns the Part. If all zones are taken, returns `nil` (player cannot join mid-game in v1.0).

- [x] **P1** In `ZoneService`, on `Players.PlayerRemoving`: find the zone owned by the leaving player in `_zoneOwners`, remove the mapping, and do not reassign it to others in the same session.

- [x] **P1** In `ZoneService`, expose `IsInZone(zone: Part, worldPosition: Vector3) -> boolean`: returns `true` if `worldPosition` falls within the zone Part's bounding box (use `zone.CFrame:PointToObjectSpace(worldPosition)` and compare against half-sizes).

- [x] **P1** In `ZoneService`, expose `GetZoneOwner(zone: Part) -> Player | nil`: returns `_zoneOwners[zone]`.

- [x] **P1** In `ZoneService`, run a `task.spawn` loop checking every 1 second for vehicles in a zone not owned by their aggroed player. If a vehicle has been in a foreign zone for more than `Constants.TrespasEjectDelay` seconds, call `VehicleService:ReturnToTraffic(vehicleId)`.

---

## 4. Traffic & Spawn System

- [x] **P1** In `src/server/services/TrafficService.lua`, create a Knit Service named `"TrafficService"`. On `KnitStart`, read all vehicle template models from `ReplicatedStorage.Assets.Vehicles` (one model per vehicle type, named exactly `"Scooter"`, `"SportBike"`, `"FamilyCar"`, `"AggroSUV"`, `"Supercar"`). Store them in a `_templates` dictionary keyed by vehicle type string.

- [x] **P1** In `TrafficService`, on `KnitStart`, after `SessionService` emits the `WarmUp` phase, begin a spawn loop using `task.spawn`. Each tick: if `_aliveCount < _maxVehicles`, pick a vehicle type using `Constants.SpawnWeights` (implement weighted random as: generate a random 0–1 float, walk the cumulative weight table, return the first type whose cumulative weight exceeds the float). Clone the template, position it at the `TrafficSpawnNode` Part's `CFrame`, assign a unique `VehicleId` string (`"V_" .. HttpService:GenerateGUID(false)`), call `VehicleService:RegisterVehicle(vehicleId, model, vehicleType)`. Increment `_aliveCount`. Wait a spawn interval read from `Constants` before next tick.

- [x] **P1** In `TrafficService`, expose `OnVehicleDestroyed(vehicleId: string) -> ()`: decrements `_aliveCount`. Called by `VehicleService` when a vehicle is destroyed.

- [x] **P1** In `TrafficService`, expose `FlashMobBurst() -> ()`: for 10 seconds (`Constants.FlashMobDuration`), override `_currentSpawnWeights` to `{ Scooter = Constants.FlashMobScooterWeight, SportBike = 0.05 }` and set spawn interval to 0.3 seconds to inject at least `Constants.FlashMobVehicleCount` vehicles. After 10 seconds, restore original weights and interval.

- [x] **P1** In `src/server/services/VehicleService.lua`, create a Knit Service named `"VehicleService"`. Maintain a `_vehicles` dictionary keyed by `vehicleId` string, each entry: `{ model: Model, vehicleType: string, state: VehicleState, ownerPlayer: Player | nil, aggroPlayer: Player | nil, pathAgent: PathfindingService agent }`.

- [x] **P1** In `VehicleService`, expose `RegisterVehicle(vehicleId, model, vehicleType)`: adds entry to `_vehicles` with `state = "Traffic"`, starts pathfinding toward `TrafficDespawnNode` using `PathfindingService:CreatePath()` and `path:ComputeAsync()`. Begin moving the vehicle's `HumanoidRootPart` (or `PrimaryPart`) along waypoints each `Heartbeat`.

- [x] **P1** In `VehicleService`, expose `SetAggro(vehicleId: string, player: Player) -> ()`: sets `state = "Aggroed"`, sets `aggroPlayer = player`. Recomputes pathfinding target to the `Part` named `ZoneEntrance_[zoneIndex]` that corresponds to the player's assigned zone. If the vehicle was previously aggroed by a different player, fires `Remotes.TugOfWarStart:FireClient` (handled by `TugOfWarService`).

- [x] **P1** In `VehicleService`, expose `ClearAggro(vehicleId: string) -> ()`: sets `state = "Traffic"`, sets `aggroPlayer = nil`. Recomputes pathfinding back to `TrafficDespawnNode`.

- [x] **P1** In `VehicleService`, expose `SetAtEntrance(vehicleId: string) -> ()`: sets `state = "AtEntrance"`. Stops movement. Starts a `task.delay(Constants.VehicleEntranceTimeout, ...)` that calls `ReturnToTraffic(vehicleId)` if state is still `"AtEntrance"` when the delay fires.

- [x] **P1** In `VehicleService`, expose `SetDragging(vehicleId: string, player: Player) -> ()`: sets `state = "Dragging"`, `ownerPlayer = player`. Cancels the entrance timeout.

- [x] **P1** In `VehicleService`, expose `SetParked(vehicleId: string, player: Player, cf: CFrame) -> ()`: sets `state = "Parked"`. Anchors the model. Records `ownerPlayer`. Stores the final `CFrame`.

- [x] **P1** In `VehicleService`, expose `SetDamaged(vehicleId: string) -> ()`: sets `state = "Damaged"`. Sets `Humanoid.WalkSpeed = 0` on the vehicle's Humanoid (if present) or halts pathfinding directly. Voids payout by setting an `_isPenalized[vehicleId] = true` flag checked by `EconomyService`.

- [x] **P1** In `VehicleService`, expose `ReturnToTraffic(vehicleId: string) -> ()`: resets `state = "Traffic"`, `aggroPlayer = nil`, `ownerPlayer = nil`. Recomputes pathfinding to `TrafficDespawnNode`.

- [x] **P1** In `VehicleService`, expose `GetState(vehicleId: string) -> VehicleState | nil`.

- [x] **P1** In `VehicleService`, when a vehicle's `PrimaryPart` touches `TrafficDespawnNode`: destroy the model, call `TrafficService:OnVehicleDestroyed(vehicleId)`, remove from `_vehicles`.

---

## 5. Whistle System

- [x] **P1** In `src/server/services/WhistleService.lua`, create a Knit Service named `"WhistleService"`. Maintain a `_lastWhistleTime` dictionary keyed by `player.UserId` and a `_whistleCooldown` dictionary for per-player TugOfWar cooldowns.

- [x] **P1** In `WhistleService`, connect `Remotes.WhistleStart.OnServerEvent`: when fired by a player, check `(tick() - _lastWhistleTime[player.UserId]) >= Constants.WhistleRateLimit` — if not, ignore silently. Then check stamina via `StaminaService:GetStamina(player) > 0` — if zero, ignore. Update `_lastWhistleTime`. Begin draining stamina via `StaminaService:BeginDrain(player, "whistle")`. Run `workspace:GetPartBoundsInRadius(hrp.Position, radius, overlapParams)` where `radius = Constants.WhistleBaseRadius + (profile.Data.SkillTree.WhistleLevel * Constants.WhistleStatScale)` capped at `Constants.WhistleMaxRadius`. `overlapParams` filters to `CollisionGroup = "VehicleHitbox"` only. For each vehicle model hit whose state is `"Traffic"` or `"Aggroed"`, call `VehicleService:SetAggro(vehicleId, player)`.

- [x] **P1** In `WhistleService`, connect `Remotes.WhistleStop.OnServerEvent`: call `StaminaService:EndDrain(player, "whistle")`.

- [x] **P1** In `WhistleService`, expose `ApplyCooldown(player: Player) -> ()`: sets `_whistleCooldown[player.UserId] = tick() + Constants.WhistleCooldownOnLoss`. `WhistleStart` checks this timestamp and ignores activations during cooldown.

- [x] **P1** In `src/server/services/TugOfWarService.lua`, create a Knit Service named `"TugOfWarService"`. Maintain `_activeBattles` dictionary keyed by `vehicleId`, storing `{ playerA, playerB, scoreA, scoreB, startTime }`.

- [x] **P1** In `TugOfWarService`, expose `StartBattle(vehicleId: string, playerA: Player, playerB: Player) -> ()`: if a battle already exists for this vehicleId, ignore. Populate `_activeBattles[vehicleId]`. Fire `Remotes.TugOfWarStart:FireClient(playerA, vehicleId)` and same for `playerB`. After `Constants.TugOfWarDuration` seconds (use `task.delay`), call `_ResolveBattle(vehicleId)`.

- [x] **P1** In `TugOfWarService`, connect `Remotes.TugOfWarInput.OnServerEvent`: when fired by a player with `vehicleId`, find the battle in `_activeBattles`. Check input rate: if the player has sent more than `Constants.TugOfWarAPMCap` inputs this second for this battle, ignore. Increment their score (`scoreA` or `scoreB`).

- [x] **P1** In `TugOfWarService`, implement `_ResolveBattle(vehicleId)`: compare `scoreA` vs `scoreB`. Winner = higher score (tie goes to `playerA`). Call `VehicleService:SetAggro(vehicleId, winner)`. Call `WhistleService:ApplyCooldown(loser)`. Fire `Remotes.TugOfWarResult:FireClient(winner, vehicleId, true)` and `Remotes.TugOfWarResult:FireClient(loser, vehicleId, false)`. Remove from `_activeBattles`.

- [x] **P1** In `src/server/services/StaminaService.lua`, create a Knit Service named `"StaminaService"`. Maintain `_stamina` (current value per player) and `_drainSources` (set of active drain labels per player, e.g. `"whistle"`). On `Heartbeat`, for each player: if `_drainSources[uid]` contains `"whistle"`, subtract `Constants.WhistleStaminaDrain * dt`. Add passive regen `Constants.StaminaRegenRate * dt` always. Clamp to `[0, maxStamina]` where `maxStamina = Constants.StaminaMax + (profile.Data.SkillTree.StaminaLevel * 30)`. Fire `Remotes.StaminaUpdated:FireClient(player, newValue)` (use `UnreliableRemoteEvent`).

- [x] **P1** In `StaminaService`, expose `GetStamina(player) -> number`, `BeginDrain(player, label)`, `EndDrain(player, label)`, `Consume(player, amount) -> success: boolean` (used for dash cost — deducts if sufficient, returns false if not).

- [x] **P1** In `src/client/controllers/WhistleController.lua`, create a Knit Controller named `"WhistleController"`. On `KnitStart`, bind the Whistle input to `UserInputService` `InputBegan` / `InputEnded` for keyboard key `F` and the Whistle `ImageButton` for mobile (by name `HUD.ActionButtons.WhistleBtn`). On input began: fire `Remotes.WhistleStart:FireServer()`. Start local stamina drain animation (update stamina bar UI). On input ended: fire `Remotes.WhistleStop:FireServer()`. Stop local stamina animation.

- [x] **P1** In `WhistleController`, on `KnitStart`, listen to `Remotes.StaminaUpdated` (UnreliableRemoteEvent) to update the local stamina bar `Frame.Size` property.

- [x] **P1** In `WhistleController`, on whistle input began: play the player's assigned whistle SFX (pitch assigned by `CosmeticController`). Trigger the whistle VFX `ParticleEmitter` at the mouth `Attachment` on the local character for 0.3 seconds.

---

## 6. Vehicle Drag (Street Tetris)

- [x] **P1** In `src/server/services/DragService.lua`, create a Knit Service named `"DragService"`. Maintain `_activeDrags` dictionary keyed by `vehicleId`: `{ player, alignConstraint, posConstraint, startTime }`.

- [x] **P1** In `DragService`, connect `Remotes.DragStart.OnServerEvent` with args `(player, vehicleId: string)`:
  1. Reject if `VehicleService:GetState(vehicleId) ~= "AtEntrance"` — fire `Remotes.DragStart:FireClient(player, vehicleId, false, "NOT_AT_ENTRANCE")`.
  2. Reject if `ZoneService:GetZoneOwner(player's zone) ~= player` — fire fail reason `"NOT_OWNER"`.
  3. Reject if `_activeDrags[vehicleId]` already exists — fire fail reason `"ALREADY_DRAGGED"`.
  4. On pass: call `VehicleService:SetDragging(vehicleId, player)`. Unanchor all `BasePart`s in the vehicle model. Create an `AlignPosition` constraint between vehicle `PrimaryPart` and player `HumanoidRootPart`, set `MaxForce = 10000`, `Responsiveness = 50`. Create an `AlignOrientation` constraint, `MaxTorque = 10000`, `Responsiveness = 25`. Set `RigidityEnabled = false` on both. Add both constraints to `_activeDrags[vehicleId]`. Set vehicle model's parts to `CollisionGroup = "DraggedVehicles"`. Fire `Remotes.DragStart:FireClient(player, vehicleId, true)`.

- [x] **P1** In `DragService`, connect `Remotes.DragConfirm.OnServerEvent` with args `(player, vehicleId: string, desiredCFrame: CFrame)`:
  1. Reject if `_activeDrags[vehicleId] == nil` or `_activeDrags[vehicleId].player ~= player`.
  2. Reject if `desiredCFrame.Position` is outside the player's zone bounds — call `ZoneService:IsInZone(zone, desiredCFrame.Position)`. If false, fire fail reason `"OUT_OF_BOUNDS"` (vehicle stays in dragging state; player must try again).
  3. On pass: destroy both constraints. Re-anchor vehicle. Set `PrimaryPart.CFrame = desiredCFrame`. Set parts to `CollisionGroup = "ParkedVehicles"`. Call `VehicleService:SetParked(vehicleId, player, desiredCFrame)`. Compute `alignmentBonus` (see task below). Call `EconomyService:AddPayout(player, EconomyService:CalculatePayout(vehicleType, alignmentBonus, currentEventMultiplier, 0))`. Remove from `_activeDrags`. Fire `Remotes.PayoutReceived:FireClient(player, payoutAmount)`.

- [x] **P1** In `DragService`, implement `_ComputeAlignmentBonus(vehicleId: string) -> number`: get the placed vehicle's `PrimaryPart.CFrame.LookVector`. Use `workspace:GetPartBoundsInBox(vehicleCFrame, vehicleSize * 1.2, overlapParams)` to find adjacent parked vehicles. For each adjacent vehicle whose `PrimaryPart.CFrame.LookVector:Dot(thisLookVector) >= Constants.AlignmentDotThreshold`, increment an aligned count. Return `math.min(alignedCount * 5, Constants.AlignmentBonusMax)`.

- [x] **P1** In `DragService`, on every `RunService.Heartbeat`, for each entry in `_activeDrags`: read `vehicle.PrimaryPart.AssemblyAngularVelocity.Magnitude`. If it exceeds `Constants.TipOverThreshold`:
  1. Destroy both constraints. Call `VehicleService:ReturnToTraffic(vehicleId)` — vehicle physics simulate freely.
  2. Call `EconomyService:ApplyPenalty(player, vehicleBasePayout * Constants.TipOverPenaltyPct)`.
  3. Run domino check: `workspace:GetPartBoundsInRadius(primaryPart.Position, Constants.TipOverDominoRadius, overlapParams)` filtering to `CollisionGroup = "ParkedVehicles"`. For each hit vehicle, apply `BasePart:ApplyImpulse(Vector3.new(0, 200, 0))` to dislodge it.
  4. Remove from `_activeDrags`.
  5. Fire `Remotes.PenaltyApplied:FireClient(player, penaltyAmount)`.

- [x] **P1** In `src/client/controllers/DragController.lua`, create a Knit Controller named `"DragController"`. On `KnitStart`, detect proximity to vehicles in state `"AtEntrance"` using a `RunService.Heartbeat` loop: cast `workspace:GetPartBoundsInRadius(hrp.Position, 5, params)`. If a valid vehicle is nearby, show `ProximityPrompt` or action button highlight for the Interact button.

- [x] **P1** In `DragController`, on Interact input while near a vehicle at entrance: fire `Remotes.DragStart:FireServer(vehicleId)`. Wait for `Remotes.DragStart` callback with matching vehicleId. On success: enter drag visual mode — show spatial grid overlay (`ReplicatedStorage.Assets.VFX.GridOverlay` Part made visible in the player's zone). Begin sending `Remotes.DragPositionUpdate:FireServer(vehicleId, desiredCFrame)` every `Heartbeat` while dragging using `UnreliableRemoteEvent`. On fail: show reason in screen UI for 2 seconds.

- [x] **P1** In `DragController`, on Interact release while in drag mode: fire `Remotes.DragConfirm:FireServer(vehicleId, currentDesiredCFrame)`. Hide grid overlay. Exit drag mode regardless of server confirmation (server will re-enter drag mode if confirmation is rejected).

- [x] **P2** In `DragController`, if the confirmed vehicle type is `"Supercar"`: after server fires `Remotes.QTEPrompt:FireClient()`, display a QTE UI (`StarterGui/QTEHUD`) showing a button sequence (3 buttons, randomized). Player has 3 seconds. On success, fire `Remotes.QTEResult:FireServer(vehicleId, true)`. On timeout or wrong input, fire `Remotes.QTEResult:FireServer(vehicleId, false)`.

- [x] **P2** In `DragService`, connect `Remotes.QTEResult.OnServerEvent` with args `(player, vehicleId, success: boolean)`: if vehicle is `"Supercar"` and `success = false`, multiply the payout by `0.5` before calling `EconomyService:AddPayout`.

---

## 7. PvP Combat

- [ ] **P1** In `src/server/services/CombatService.lua`, create a Knit Service named `"CombatService"`. Maintain `_dashCooldowns` and `_strikeCooldowns` dictionaries keyed by `player.UserId`.

- [ ] **P1** In `CombatService`, connect `Remotes.DashRequest.OnServerEvent` with args `(player, directionRaw: Vector3)`:
  1. Check `_dashCooldowns[uid]`: if `tick() < cooldownEnd`, ignore.
  2. Check `StaminaService:Consume(player, Constants.DashStaminaCost)`: if returns false, ignore.
  3. Normalize `directionRaw`. Compute angle between `directionRaw` and `player.Character.HumanoidRootPart.CFrame.LookVector` using `math.acos(math.clamp(directionRaw:Dot(lookVec), -1, 1))`. If angle in degrees > `Constants.DashMaxAngleDeg`, clamp the direction to the closest allowed direction (project onto the allowed cone — do not reject; clamping prevents exploit while still responding).
  4. Apply `HumanoidRootPart:ApplyImpulse(clampedDir * 8000)`.
  5. Set `_dashCooldowns[uid] = tick() + Constants.DashCooldown`.
  6. Begin hit detection loop for `Constants.DashDuration` seconds using `task.spawn` + `RunService.Heartbeat`: each frame, run `workspace:GetPartBoundsInBox(hrp.CFrame, Vector3.new(4, 5, 3), overlapParams)` filtering to `CollisionGroup = "Players"`. For each result that is not the attacker's own character: call `_ApplyRagdoll(hitPlayer, Constants.DashRagdollDuration)`. Cancel any active drag for `hitPlayer` by calling `DragService:ForceRelease(hitPlayer)`. Break the loop after first hit.

- [ ] **P1** In `CombatService`, implement `_ApplyRagdoll(player: Player, duration: number) -> ()`: set `player.Character.Humanoid.PlatformStand = true`. After `duration` seconds, set `PlatformStand = false`.

- [ ] **P1** In `CombatService`, expose `ForceRagdoll(player, duration)` publicly so `PoliceService` and `VehicleService` (AggroSUV knockback) can reuse it.

- [ ] **P1** In `CombatService`, connect `Remotes.StrikeRequest.OnServerEvent` with args `(player)`:
  1. Check strike cooldown (0.5s hardcoded) — if within cooldown, ignore.
  2. Run `workspace:GetPartBoundsInBox(hrp.CFrame * CFrame.new(0, 0, -2), Vector3.new(Constants.MeleeWidth, 4, Constants.MeleeRange), overlapParams)`.
  3. Iterate results. Priority order: first check for any part tagged `"ThiefNPC"` — if found, call `ThiefService:Interrupt(thiefId)` and stop. Then check for any part belonging to a rival player character — if found, apply `HumanoidRootPart:ApplyImpulse(attacker.LookVector * 3000)` and cancel their active action via `DragService:ForceRelease(rival)` and `WhistleService:ForceStop(rival)`.
  4. Update cooldown timestamp.

- [ ] **P1** In `src/client/controllers/CombatController.lua`, create a Knit Controller named `"CombatController"`. Bind Dash to `Q` key and Dash mobile button (`HUD.ActionButtons.DashBtn`). Bind Strike to `E` key and Strike mobile button (`HUD.ActionButtons.StrikeBtn`). On Dash input: fire `Remotes.DashRequest:FireServer(hrp.CFrame.LookVector)`. On Strike input: fire `Remotes.StrikeRequest:FireServer()`. Both inputs deduct stamina locally for visual responsiveness only — server is authoritative.

- [ ] **P2** In `CombatService`, connect `Remotes.PlaceStrip.OnServerEvent` with args `(player, position: Vector3)`:
  1. Check player has ≥1 Spike Strip in `MonetizationService:GetInventory(player).SpikeStrip`.
  2. Check `(position - hrp.Position).Magnitude <= Constants.SpikeStripPlaceRadius`.
  3. Check position is on a ground surface: run `workspace:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -2, 0))` — reject if no hit.
  4. On pass: deduct 1 Spike Strip via `MonetizationService:ConsumeItem(player, "SpikeStrip")`. Create a `Part` in workspace at `position`, size `Vector3.new(4, 0.2, 1)`, `CollisionGroup = "Environment"`, `Anchored = true`, tag it `"SpikeStrip"`, set `Attribute("OwnerId", player.UserId)`.
  5. Bind `part.Touched:Connect(...)`: when a part tagged `"VehicleHitbox"` touches the strip, call `VehicleService:SetDamaged(vehicleId)`, then `part:Destroy()`.
  6. Also bind: when a player's character touches the strip with a melee strike hit (detected via `StrikeRequest` handler checking hit tag `"SpikeStrip"`), destroy the strip immediately.

---

## 8. Economy System

- [ ] **P1** In `src/server/services/EconomyService.lua`, create a Knit Service named `"EconomyService"`. Maintain `_unbanked` dictionary keyed by `player.UserId`, initialized to `0` on player join. Maintain `_currentEventMultiplier = 0` (updated by `EventService`).

- [ ] **P1** In `EconomyService`, expose `CalculatePayout(vehicleType: string, alignmentBonus: number, eventMultiplier: number, penalties: number) -> number`: implements `(Constants.VehicleBasePayouts[vehicleType] + alignmentBonus) * (1 + eventMultiplier) - penalties`. Floors result at `0`. Returns integer (use `math.floor`).

- [ ] **P1** In `EconomyService`, expose `AddPayout(player: Player, amount: number) -> ()`: add `amount` to `_unbanked[uid]`. Fire `Remotes.PayoutReceived:FireClient(player, amount, _unbanked[uid])` so HUD shows both the delta and the new total.

- [ ] **P1** In `EconomyService`, expose `ApplyPenalty(player: Player, amount: number) -> ()`: subtract `amount` from `_unbanked[uid]`, floor at `0`. Fire `Remotes.PenaltyApplied:FireClient(player, amount, _unbanked[uid])`.

- [ ] **P1** In `EconomyService`, expose `BankEarnings(player: Player) -> ()`: add `_unbanked[uid]` to `DataService:GetProfile(player).Data.BankedEarnings`, then set `_unbanked[uid] = 0`. Fire `Remotes.PayoutReceived:FireClient(player, 0, 0)` to update HUD unbanked display to 0. Call `DataService:AddBankedEarnings(player, amount)` which fires its own client event for banked total refresh.

- [ ] **P1** In `EconomyService`, expose `SpendShiftCurrency(player: Player, amount: number) -> boolean`: if `_unbanked[uid] >= amount`, deduct and return `true`. Otherwise return `false` without deducting.

- [ ] **P1** In `EconomyService`, expose `GetUnbanked(player: Player) -> number`.

- [ ] **P1** In `EconomyService`, expose `SetEventMultiplier(multiplier: number) -> ()`: sets `_currentEventMultiplier`. Called by `EventService`.

- [ ] **P2** In `EconomyService`, expose `AutoBankAll() -> ()`: iterate all players in `Players:GetPlayers()`, call `BankEarnings(player)` for each. Called by `SessionService` at `ShiftEnd`.

---

## 9. Helmet Thief AI

- [ ] **P1** In `src/server/services/ThiefService.lua`, create a Knit Service named `"ThiefService"`. Maintain `_activeThieves` dictionary keyed by a `thiefId` string: `{ model, state: NPCState, targetVehicleId, heldHelmet, coroutine }`.

- [ ] **P1** In `ThiefService`, on `KnitStart`: start a spawn manager loop using `task.spawn`. Every 5 seconds, if `#_activeThieves < Constants.ThiefMaxAlive` and `_respawnCooldown <= tick()`: find all Sport Bike vehicles in `VehicleService` where state is `"Parked"` and the helmet weld is still attached. If any exist, pick one at random, spawn a Thief NPC from `ReplicatedStorage.Assets.NPCs.HelmetThief` at `ThiefDespawnNode` position, assign a `thiefId`, call `_StartBehaviorTree(thiefId, targetVehicleId)`.

- [ ] **P1** In `ThiefService`, implement `_StartBehaviorTree(thiefId, targetVehicleId)` as a coroutine stored in `_activeThieves[thiefId].coroutine`:
  - **Roam state**: if no target, pick a random waypoint in the map and navigate there via `PathfindingService`. Loop until a target is assigned.
  - **Navigate state**: compute path to the target vehicle's `PrimaryPart.Position`. Move the NPC along waypoints each Heartbeat.
  - **Interact state**: play `"Rummage"` animation on NPC Humanoid. Wait `Constants.ThiefInteractDuration` seconds. If not interrupted: un-weld the helmet from the Sport Bike (call `helmet:SetAttribute("Stolen", true)`, disconnect the `WeldConstraint`). Transition to Flee state.
  - **Flee state**: weld the helmet to the NPC's right hand `Attachment`. Compute path to `ThiefDespawnNode`. Move NPC there. On arrival: fire `_OnHelmetStolen(targetVehicleId)`. Destroy thief and helmet. Remove from `_activeThieves`. Set `_respawnCooldown = tick() + math.random(Constants.ThiefRespawnDelayMin, Constants.ThiefRespawnDelayMax)`.

- [ ] **P1** In `ThiefService`, expose `Interrupt(thiefId: string) -> ()`:
  1. Resume the coroutine with an interrupt signal by setting `_activeThieves[thiefId].interrupted = true` — the coroutine checks this flag at each `task.wait()` call.
  2. Drop the helmet: unweld from NPC, unanchor at current NPC position as a loose physics Part.
  3. Set NPC `Humanoid.PlatformStand = true` for `Constants.ThiefRagdollDuration` seconds, then `PlatformStand = false`.
  4. Transition thief to `Roam` state after ragdoll. Set a per-thief retarget cooldown: thief ignores Sport Bikes for `Constants.ThiefRetargetCooldown` seconds.

- [ ] **P1** In `ThiefService`, implement `_OnHelmetStolen(vehicleId)`: look up the vehicle's `ownerPlayer`. Call `EconomyService:ApplyPenalty(ownerPlayer, 0.4 * baseVehiclePayout)` (40% penalty on the Sport Bike payout for that cycle). Fire a `RemoteEvent` to the owning player's client to show a `"Helmet stolen!"` screen notification.

- [ ] **P2** In `ThiefService`, on every `Heartbeat`: for each thief navigating toward a zone, check if the thief's position is inside any `ParkingZone` Part's bounding box using `ZoneService:IsInZone`. If inside, fire `Remotes.ThreatInZone:FireClient(zoneOwner, thiefId, thief.model.PrimaryPart.Position)` via `UnreliableRemoteEvent`.

---

## 10. Police AI (Satpol PP)

- [ ] **P2** In `src/server/services/PoliceService.lua`, create a Knit Service named `"PoliceService"`. Maintain `_activePolice` array of `{ model, targetPlayer, caughtTimer }`. Maintain `_bribes` set of `player.UserId` values that have used Bribe Money this event.

- [ ] **P2** In `PoliceService`, expose `StartRaid() -> ()`: spawn `Constants.PoliceSpawnCount` NPCs from `ReplicatedStorage.Assets.NPCs.SatpolPP` at parts tagged `"PoliceSpawnNode"`. For each NPC, start a `task.spawn` loop that runs every 0.5 seconds:
  1. Find the nearest player not in a `HidingVolume` and not in `_bribes`. Do a LoS raycast from NPC head position to player `HumanoidRootPart`: `workspace:Raycast(from, to - from, raycastParams)` where `raycastParams` ignores `Players` collision group but hits `HidingVolume` parts. If raycast hits a `HidingVolume` before reaching the player, that player is hidden — skip.
  2. Set `targetPlayer` to the closest visible player. Pathfind NPC toward target using `PathfindingService`.
  3. If `(npc.PrimaryPart.Position - target.HumanoidRootPart.Position).Magnitude <= Constants.PoliceProximityCaught`: increment `caughtTimer` by `0.5`. If `caughtTimer >= Constants.PoliceCaughtTimer`: call `_CaughtPlayer(target)`. Reset `caughtTimer`.
  4. If target moves out of proximity, reset `caughtTimer = 0`.

- [ ] **P2** In `PoliceService`, implement `_CaughtPlayer(player: Player) -> ()`:
  1. Call `EconomyService:ApplyPenalty(player, EconomyService:GetUnbanked(player) * Constants.PoliceCaughtPenaltyPct)`.
  2. Teleport player character to the `Part` named `CitationNode`.
  3. Set a `_stunned[player.UserId] = true` flag. Fire `Remotes.PlayerStunned:FireClient(player, Constants.PoliceCaughtStunDuration)`. After `Constants.PoliceCaughtStunDuration` seconds, clear the stun flag.
  4. All `CombatService` and `WhistleService` OnServerEvent handlers check `_stunned` flag and ignore inputs during stun.

- [ ] **P2** In `PoliceService`, expose `EndRaid() -> ()`: for each NPC in `_activePolice`, destroy the model. Clear `_activePolice`. Clear `_bribes`.

- [ ] **P2** In `PoliceService`, expose `ClearTargeting(player: Player) -> ()`: add `player.UserId` to `_bribes`. All police NPCs will skip this player for LoS targeting for the remainder of the event.

---

## 11. Dynamic Event System

- [ ] **P1** In `src/server/services/EventService.lua`, create a Knit Service named `"EventService"`. Maintain `_activeEvent: EventType | nil = nil`.

- [ ] **P1** In `EventService`, on `KnitStart`: wait for `SessionService` to emit `PeakShift` phase. Then begin the event scheduling loop using `task.spawn`: `task.wait(math.random(Constants.EventCooldownMin, Constants.EventCooldownMax))`. Pick a random `EventType` from `{ "MonsoonRain", "SatpolRaid", "FlashMob" }` — each equally weighted. Call `_StartEvent(eventType)`.

- [ ] **P1** In `EventService`, implement `_StartEvent(eventType: EventType) -> ()`: set `_activeEvent = eventType`. Fire `Remotes.EventStart:FireAllClients(eventType)`. Dispatch to the correct handler based on `eventType`. After the event's natural duration ends, call `_EndEvent(eventType)`.

- [ ] **P1** In `EventService`, implement `_EndEvent(eventType: EventType) -> ()`: set `_activeEvent = nil`. Fire `Remotes.EventEnd:FireAllClients(eventType)`. Dispatch cleanup to the correct handler. After cleanup, reschedule next event by looping back to the random wait.

- [ ] **P2** In `EventService`, implement Monsoon Rain handler:
  - `_StartMonsoon()`: collect all `BasePart`s in `Workspace.Map` (a `Folder` holding environment geometry). For each with `Material ~= Enum.Material.Air`: store original `Friction` in a `_originalFriction` table, set `Friction = Constants.MonsoonFriction`. For each player: store original `WalkSpeed`, set `Humanoid.WalkSpeed = originalSpeed * Constants.MonsoonSpeedMultiplier`. Fire `Remotes.RainToggle:FireAllClients(true)`.
  - `_EndMonsoon()`: restore all `Friction` values from `_originalFriction`. Restore all player `WalkSpeed` values. Fire `Remotes.RainToggle:FireAllClients(false)`. Clear `_originalFriction`.
  - Duration: 90 seconds.

- [ ] **P2** In `EventService`, implement Satpol PP Raid handler:
  - `_StartRaid()`: call `PoliceService:StartRaid()`. Duration: 120 seconds, then call `_EndRaid()`.
  - `_EndRaid()`: call `PoliceService:EndRaid()`.

- [ ] **P2** In `EventService`, implement Flash Mob handler:
  - `_StartFlashMob()`: call `TrafficService:FlashMobBurst()`. Call `EconomyService:SetEventMultiplier(Constants.FlashMobEventMultiplier)`. Duration equals `Constants.FlashMobDuration` (10 seconds for the burst), but the multiplier stays active for 60 additional seconds to reward the players who managed the surge.
  - `_EndFlashMob()`: call `EconomyService:SetEventMultiplier(0)`. Restore `TrafficService` weights (already handled inside `FlashMobBurst`, but call `TrafficService:RestoreWeights()` as a safety explicit call).

---

## 12. Monetization & Gamepasses

- [ ] **P2** In `src/server/services/MonetizationService.lua`, create a Knit Service named `"MonetizationService"`. On `KnitStart`, connect `MarketplaceService.ProcessReceipt` to `_HandleReceipt`. Note: `ProcessReceipt` must return `Enum.ProductPurchaseDecision.PurchaseGranted` or `NotProcessedYet` — never error silently.

- [ ] **P2** In `MonetizationService`, implement `_HandleReceipt(receiptInfo) -> Enum.ProductPurchaseDecision`:
  - Find the player by `receiptInfo.PlayerId`. If player is not in server, return `NotProcessedYet` (Roblox will retry).
  - Match `receiptInfo.ProductId` to known Developer Product IDs (store IDs in `Constants` as `ProductId_EnergyDrink` and `ProductId_BribeMoney`). Call the appropriate grant function. Return `PurchaseGranted`.

- [ ] **P2** In `MonetizationService`, implement `_GrantEnergyDrink(player)`: call `_AddInventory(player, "EnergyDrink", 1)`. Also immediately call `StaminaService:SetFull(player)` if the player wants to use it instantly (fire `Remotes.ItemGranted:FireClient(player, "EnergyDrink")`; client chooses when to consume via `Remotes.ConsumeItem`).

- [ ] **P2** In `MonetizationService`, implement `_GrantBribeMoney(player)`: call `_AddInventory(player, "BribeMoney", 1)`.

- [ ] **P2** In `MonetizationService`, on each player join: call `MarketplaceService:UserOwnsGamePassAsync(player.UserId, Constants.GamepassId_VIPWhistle)` and `Constants.GamepassId_Landlord` (wrap in `pcall`). Store results in a `_ownedPasses[uid]` table. Expose `OwnsPass(player, passName) -> boolean`.

- [ ] **P2** In `WhistleService`, when computing whistle radius: check `MonetizationService:OwnsPass(player, "VIPWhistle")` — if true, multiply final radius by `1.2`.

- [ ] **P2** In `MonetizationService`, maintain `_inventory` dictionary keyed by `player.UserId`: `{ SpikeStrip: number, EnergyDrink: number, BribeMoney: number }`. Expose `GetInventory(player) -> table`, `ConsumeItem(player, itemName) -> boolean` (deducts 1, returns false if 0), `AddItem(player, itemName, count)`.

- [ ] **P2** In `MonetizationService`, connect `Remotes.ShopPurchase.OnServerEvent` with args `(player, itemName: string)`:
  - Validate `itemName` is one of `"SpikeStrip"`, `"EnergyDrink"`, `"BribeMoney"`.
  - Look up price in `Constants.ShopPrices[itemName]`.
  - Call `EconomyService:SpendShiftCurrency(player, price)` — if false, fire `Remotes.ShopPurchase:FireClient(player, itemName, false, "INSUFFICIENT_FUNDS")`.
  - On success: call `AddItem(player, itemName, 1)`. Fire `Remotes.ShopPurchase:FireClient(player, itemName, true, GetInventory(player))`.

- [ ] **P2** In `MonetizationService`, connect `Remotes.ConsumeItem.OnServerEvent` with args `(player, itemName: string)`:
  - Validate `itemName`. Call `ConsumeItem(player, itemName)` — if false, ignore.
  - Dispatch effect: `"EnergyDrink"` → `StaminaService:SetFull(player)`. `"BribeMoney"` → `PoliceService:ClearTargeting(player)`. `"SpikeStrip"` → handled separately via `Remotes.PlaceStrip`.

---

## 13. Client UI Controllers

- [ ] **P1** In `src/client/controllers/HUDController.lua`, create a Knit Controller named `"HUDController"`. On `KnitStart`:
  - Get references to `HUD.ShiftTracker.TimeLabel`, `HUD.ShiftTracker.UnbankedLabel`, `HUD.ShiftTracker.BankedLabel`, `HUD.StaminaBar.Fill`.
  - Listen to `Remotes.SessionPhaseChanged`: update `TimeLabel.Text` with remaining seconds formatted as `"MM:SS"` using `string.format("%02d:%02d", math.floor(s/60), s%60)`.
  - Listen to `Remotes.PayoutReceived` with args `(delta, newUnbanked)`: tween `UnbankedLabel` text to `newUnbanked`. Show a floating `"+N"` `TextLabel` above the HUD that tweens upward and fades in 1.5 seconds using `TweenService`.
  - Listen to `Remotes.PenaltyApplied` with args `(delta, newUnbanked)`: tween `UnbankedLabel` text. Show a floating `"-N"` in red using the same tween pattern.
  - Listen to `Remotes.StaminaUpdated` (UnreliableRemoteEvent): set `StaminaBar.Fill.Size = UDim2.new(newValue/maxStamina, 0, 1, 0)`. Change `BackgroundColor3` based on thresholds: `>60%` = green, `30–60%` = yellow, `<30%` = red.

- [ ] **P1** In `src/client/controllers/ThreatController.lua`, create a Knit Controller named `"ThreatController"`. On `KnitStart`:
  - Listen to `Remotes.ThreatInZone` (UnreliableRemoteEvent) with args `(thiefId, thiefWorldPos: Vector3)`.
  - On each receive: compute screen direction using `workspace.Camera:WorldToViewportPoint(thiefWorldPos)`. If the result's `z < 0` or position is outside `[0,1]` screen UV, the threat is off-screen — show the edge arrow. Compute the angle from screen center to the clamped screen position using `math.atan2`. Set `ThreatArrow.Rotation` to that angle in degrees. Set `ThreatArrow.Visible = true`.
  - Scale `ThreatArrow.ImageTransparency` inversely with `(thiefWorldPos - hrp.Position).Magnitude`: at 5 studs = 0 (fully opaque), at 25 studs = 0.7.
  - If no `ThreatInZone` event is received for 2 seconds, hide the arrow.

- [ ] **P1** In `src/client/controllers/TugOfWarController.lua`, create a Knit Controller named `"TugOfWarController"`. On `KnitStart`:
  - Listen to `Remotes.TugOfWarStart` with args `(vehicleId)`: show `TugOfWarGui.Bar` as a `BillboardGui` parented to `LocalPlayer.Character.HumanoidRootPart`, offset `UDim2.new(0,0,0,-3)` in stud space. Show centered fill bar.
  - On each `UserInputService.InputBegan` while bar is visible (any key or tap): fire `Remotes.TugOfWarInput:FireServer(vehicleId)`. Animate the player's side of the bar by incrementing fill width locally (cosmetic only; server is authoritative on score).
  - Listen to `Remotes.TugOfWarResult` with args `(vehicleId, won: boolean)`: flash bar green if `won`, red if not. Hide bar after 0.5 seconds.

- [ ] **P2** In `src/client/controllers/EventController.lua`, create a Knit Controller named `"EventController"`. On `KnitStart`:
  - Listen to `Remotes.EventStart` with args `(eventType: string)`: show `EventBanner.Frame` by tweening it in from off-screen top using `TweenService` over 0.4 seconds. Set `EventBanner.TitleLabel.Text` based on `eventType`: `"MonsoonRain"` → `"⛈ HUJAN DERAS!"`, `"SatpolRaid"` → `"🚨 RAZIA SATPOL PP!"`, `"FlashMob"` → `"🎶 KONSER DADAKAN!"`. Hide the banner after 4 seconds.
  - `"MonsoonRain"` start: enable `ReplicatedStorage.Assets.VFX.RainEmitter` cloned into workspace, `Rate = 200`.
  - `"MonsoonRain"` end (via `Remotes.EventEnd`): destroy rain emitter clone.
  - `"SatpolRaid"` start: play `ReplicatedStorage.Assets.Audio.PoliceSiren` sound in `SoundService`, looped.
  - `"SatpolRaid"` end: stop and destroy the siren sound.

- [ ] **P2** In `src/client/controllers/ShopController.lua`, create a Knit Controller named `"ShopController"`. On `KnitStart`:
  - Detect proximity to `ShopVendor` part via the `ProximityPrompt.Triggered` event. On trigger: set `ShopGui.Enabled = true`. Populate 3 item card `Frame`s with names, icons, and prices from `Constants.ShopPrices`.
  - On item card click: fire `Remotes.ShopPurchase:FireServer(itemName)`.
  - Listen to `Remotes.ShopPurchase` callback: if success, update item card count label. If fail `"INSUFFICIENT_FUNDS"`, flash the card border red.
  - On `ProximityPrompt.TriggerEnded` or player moves > 8 studs from vendor: set `ShopGui.Enabled = false`.

- [ ] **P2** In `src/client/controllers/BankController.lua`, create a Knit Controller named `"BankController"`. On `KnitStart`:
  - Detect `ProximityPrompt.Triggered` on `BankTerminal`. On trigger: show `BankGui` with current unbanked amount and a `"SETOR"` confirm button.
  - On confirm: fire `Remotes.BankEarnings:FireServer()`. Show a brief `"Tersimpan!"` text for 2 seconds. Close `BankGui`.
  - `Remotes.BankEarnings` has no client callback — the subsequent `Remotes.PayoutReceived` event (fired by `DataService:AddBankedEarnings`) updates the HUD.

- [ ] **P2** In `src/client/controllers/PostSessionController.lua`, create a Knit Controller named `"PostSessionController"`. On `KnitStart`:
  - Listen to `Remotes.ShiftSummary` with args `(data: { totalEarned, penalties, bankedThisSession, topEarnerName, topEarnerAmount })`.
  - On receive: set `PostSessionGui.Enabled = true`. Populate labels. If local player is top earner, show a golden border on their name entry.
  - Show `"SIAP"` button that fires `Remotes.ReadyUp:FireServer()` when clicked.

---

## 14. Cosmetics System

- [ ] **P2** In `src/server/services/CosmeticService.lua`, create a Knit Service named `"CosmeticService"`. On player character spawn (`Players.PlayerAdded` + `player.CharacterAdded`):
  1. Load the player's `OwnedCosmetics` list from `DataService:GetProfile(player)`.
  2. If a vest cosmetic is equipped (stored as e.g. `"Vest_Neon"`): clone the matching `MeshPart` from `ReplicatedStorage.Assets.Cosmetics.Vests[vestName]`. Parent it to the character's `UpperTorso`. Weld it with a `WeldConstraint` to `UpperTorso`. Apply to all clients via `Remotes.CosmeticData:FireAllClients(player, cosmeticData)`.
  3. Assign the player a whistle pitch index (`1` through `8`) based on join order. Store in `_pitchAssignments[player.UserId]`. Include in `cosmeticData`.

- [ ] **P2** In `src/client/controllers/CosmeticController.lua`, create a Knit Controller named `"CosmeticController"`. On `KnitStart`:
  - Listen to `Remotes.CosmeticData` with args `(targetPlayer: Player, data)`. Apply the vest mesh for `targetPlayer`'s character locally (already done server-side; this ensures late-joining clients see others' cosmetics).
  - Store the local player's assigned `pitchIndex` from their `CosmeticData`. In `WhistleController`, the whistle SFX `Pitch` is set to `0.75 + (pitchIndex - 1) * 0.0357` (maps indices 1–8 linearly from pitch 0.75 to 1.0).
  - Listen to `Remotes.DashTrailVFX` (UnreliableRemoteEvent) with args `(player, trailAssetName)`: clone the trail `Attachment`+`Trail` from `ReplicatedStorage.Assets.Cosmetics.Trails[trailAssetName]` into the target player's character `HumanoidRootPart`.

---

## 15. Syndicate System

- [ ] **P3** In `src/server/services/SyndicateService.lua`, create a Knit Service named `"SyndicateService"`. Store syndicates in a DataStore `"SyndicateStore"` as a table keyed by `syndicateId`: `{ name, members: {userId}, weeklyEarnings, bannerReward }`. Max 8 members per syndicate enforced on `JoinSyndicate`.

- [ ] **P3** In `SyndicateService`, expose `CreateSyndicate(player, name) -> syndicateId | nil`: fails if player already in a syndicate. Creates entry, adds player as first member.

- [ ] **P3** In `SyndicateService`, expose `JoinSyndicate(player, syndicateId) -> success: boolean`: fails if player already in syndicate or syndicate is full.

- [ ] **P3** In `SyndicateService`, expose `LeaveSyndicate(player) -> ()`.

- [ ] **P3** In `SyndicateService`, in `EconomyService:AddPayout`, before firing the client event: check if the paying player is in a syndicate and if any syndicate member's zone is adjacent (zones are adjacent if their bounding boxes share an edge within 0.5 stud tolerance). If true, multiply the final payout by `1.05` before adding.

- [ ] **P3** In `SyndicateService`, run a weekly reset on the first server start after Monday 00:00 UTC: compare `os.date("!*t")` weekday. Identify top 3 syndicates by `weeklyEarnings`. Call `CosmeticService:GrantBannerReward(memberUserId, syndicateId)` for each member of top 3. Reset all `weeklyEarnings` to 0.

- [ ] **P3** In `src/client/controllers/SyndicateController.lua`, create a Knit Controller. On `KnitStart`: request syndicate data from server on join, populate `SyndicateGui` with member list and `weeklyEarnings` contribution bar. Bind create/join/leave buttons to their respective server remotes.

---

## 16. Anti-Exploit & Sanity Checks

All checks are already specified inline in the relevant service tasks above. This section is an audit checklist — each item must be verified by reading the corresponding service implementation.

- [ ] **P1** `WhistleService`: rate limit of 1 activation per `Constants.WhistleRateLimit` seconds is implemented and stamina is checked server-side before `OverlapParams` runs.
- [ ] **P1** `CombatService` Dash: direction is normalized and clamped to 45° cone server-side; stamina cost is consumed via `StaminaService:Consume` before `VectorForce` is applied; cooldown timestamp is checked before any processing.
- [ ] **P1** `DragService` `DragConfirm`: position is validated inside zone bounds via `ZoneService:IsInZone` before re-anchoring; player ownership of the zone is confirmed; vehicleId ownership is confirmed against `_activeDrags`.
- [ ] **P1** `VehicleService` payout: `_isPenalized[vehicleId]` flag is checked before `EconomyService:AddPayout` is called; vehicle must be in `Parked` state.
- [ ] **P1** `MonetizationService`: `ConsumeItem` checks `count > 0` before decrementing and before dispatching any effect; `ShopPurchase` validates `itemName` against a whitelist before calling `EconomyService:SpendShiftCurrency`.
- [ ] **P2** No `RemoteFunction` exists that writes to economy state — all economy writes are `RemoteEvent` handlers inside server services only.
- [ ] **P2** `TugOfWarService`: per-player input rate is capped at `Constants.TugOfWarAPMCap` inputs/second using a rolling counter reset every second.
- [ ] **P2** `PoliceService` `CaughtPlayer`: penalty is computed as a fraction of `GetUnbanked` at the moment of catch — not a fixed amount — so it scales correctly regardless of the player's current balance.

---

## 17. Optimization & Networking

- [ ] **P1** In `src/server/services/PhysicsService.lua`, create a Knit Service named `"PhysicsService"`. Expose `AssignServerOwnership(model: Model) -> ()`: iterates all `BasePart`s in the model and calls `part:SetNetworkOwner(nil)` (nil = server). Call this immediately after every vehicle is spawned by `TrafficService`. Never call `SetNetworkOwner` with a Player argument for vehicles — vehicle physics must always run on the server.

- [ ] **P1** In `PhysicsService`, expose `AnchorModel(model: Model) -> ()` and `UnanchorModel(model: Model) -> ()`: iterate all `BasePart`s and set `Anchored`. `AnchorModel` is called on every vehicle at spawn and after `SetParked`. `UnanchorModel` is called only during drag.

- [ ] **P2** Audit every `RemoteEvent:FireAllClients` and `FireClient` call in every service. For each one, confirm: if the data is used to update a visual element only (VFX, animation, trail, particle), it must use `UnreliableRemoteEvent`. If it carries game state (payout amount, phase change, stun, caught penalty), it must use `RemoteEvent`. Document any mismatches found and fix them.

- [ ] **P2** In `TrafficService`, enforce a hard cap `_maxVehicles`: `math.min(8 * Players:GetPlayerCount(), 40)`. Recalculate when a player joins or leaves. Never spawn above this cap regardless of event state.

- [ ] **P3** In `DragController`, implement client-side visual interpolation for dragged vehicles: instead of setting the vehicle position directly each `Heartbeat` from server position updates, lerp the local visual position using `RunService.RenderStepped` with `alpha = math.min(1, dt * 20)`. The server position is the authority; the lerp is cosmetic smoothing only.
